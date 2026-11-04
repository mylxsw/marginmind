import 'package:mm_sync/mm_sync.dart';
import 'package:test/test.dart';

void main() {
  SyncCommit commit(
    String device, {
    int sequence = 1,
    List<SyncCommit> parents = const [],
    String scope = 'set',
    Map<String, Object?> payload = const {'name': 'base'},
    bool deleted = false,
  }) => SyncCommit.create(
    libraryId: 'library',
    deviceId: device,
    scope: scope,
    sequence: sequence,
    parents: parents.map((c) => c.id).toList(),
    payload: deleted ? {} : payload,
    deleted: deleted,
  );
  Map<String, SyncCommit> known(List<SyncCommit> values) => {for (final c in values) c.id: c};

  test('missing ancestors and invalid causal graphs stay pending or conflicted', () {
    final base = commit('a');
    final child = commit('b', parents: [base]);
    final plan = planSyncMerge(known([child]), remote: child.id);
    expect(plan.state, SyncMergeState.waiting);
    expect(plan.missing, [base.id]);
    expect(plan.toJson()['missing'], [base.id]);
    final cross = commit('c', scope: 'another', parents: [base]);
    expect(planSyncMerge(known([base, cross]), remote: cross.id).reason, 'invalidHistory');
    final fork = commit('a', payload: {'name': 'fork'});
    expect(planSyncMerge(known([base, fork]), remote: base.id).reason, 'invalidHistory');
    // An unaccepted bad receipt cannot prevent editing an accepted lineage.
    expect(syncAncestry(known([base, fork]), [base.id], checkKnownForks: false).keys, [base.id]);
  });

  test('unknown and ambiguous merge bases never choose a branch', () {
    final a = commit('a'), b = commit('b');
    expect(planSyncMerge(known([a, b]), local: a.id, remote: b.id).reason, 'noBase');
    final left = commit('left', parents: [a]);
    final right = commit('right', parents: [a]);
    final m1 = commit('m1', parents: [left, right]);
    final m2 = commit('m2', parents: [left, right]);
    final plan = planSyncMerge(known([a, left, right, m1, m2]), local: m1.id, remote: m2.id);
    expect(plan.reason, 'multipleBases');
    expect(plan.bases.toSet(), {left.id, right.id});
  });

  test('causal fast-forward and duplicate delivery need no new local commit', () {
    final base = commit('a'), otherScope = commit('x', scope: 'other');
    final child = commit('a', sequence: 2, parents: [base]);
    final history = known([base, child, otherScope]);
    expect(planSyncMerge(history, local: base.id, remote: child.id).adopt, isTrue);
    expect(planSyncMerge(history, local: child.id, remote: base.id).state, SyncMergeState.unchanged);
    expect(planSyncMerge(history, local: base.id, remote: otherScope.id).reason, 'differentScope');
  });

  test('delete/delete converges, delete/edit and resurrected branches retain both inputs', () {
    final base = commit('base');
    final left = commit('left', parents: [base], deleted: true);
    final right = commit('right', parents: [base], deleted: true);
    final both = planSyncMerge(known([base, left, right]), local: left.id, remote: right.id);
    expect(both.state, SyncMergeState.ready);
    expect(both.deleted, isTrue);
    final edit = commit('edit', parents: [base], payload: {'name': 'edit'});
    expect(planSyncMerge(known([base, left, edit]), local: left.id, remote: edit.id).reason, 'deleteEdit');
    final x = commit('x', parents: [left]), y = commit('y', parents: [left]);
    expect(planSyncMerge(known([base, left, x, y]), local: x.id, remote: y.id).reason, 'deleteEdit');
  });

  test('independent fields merge; contested fields carry recoverable variants', () {
    final base = commit('a', payload: {'title': 't', 'body': 'b'});
    final left = commit('b', parents: [base], payload: {'title': 'left', 'body': 'b'});
    final right = commit('c', parents: [base], payload: {'title': 't', 'body': 'right'});
    final merged = planSyncMerge(known([base, left, right]), local: left.id, remote: right.id);
    expect(merged.payload, {'title': 'left', 'body': 'right'});
    final conflict = commit('d', parents: [base], payload: {'title': 'other', 'body': 'b'});
    final plan = planSyncMerge(known([base, left, conflict]), local: left.id, remote: conflict.id);
    expect(plan.state, SyncMergeState.conflict);
    expect(plan.conflicts.single.path, ['title']);
    expect(plan.toJson()['conflicts'], isNotEmpty);
  });
}
