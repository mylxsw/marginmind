import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

void main() {
  test('scope snapshots authorization; port DTOs serialize known locators only', () {
    final pages = {
      'd': {1},
    };
    final scope = ReadScope(
      studySetId: 's',
      pages: pages,
      documents: {'whole'},
      selections: {'sel'},
      maps: {'m'},
      branches: {
        'branchMap': {'n'},
      },
    );
    pages['d']!.add(2);
    expect(scope.allowsPage('d', 2), false);
    expect(scope.allowsPage('d', 1), true);
    expect(scope.allowsPage('whole', 10), true);
    expect(scope.allowsPage('whole', 0), false);
    expect(scope.allowsBranch('m', 'any'), true);
    expect(scope.allowsBranch('branchMap', 'n'), true);
    expect(scope.allowsBranch('branchMap', 'other'), false);
    expect(const ReadPage('d', 1, 'text').toJson()['text'], 'text');
    expect(const StudySearchHit(title: 't', locator: 'd:1').toJson()['locator'], 'd:1');
    expect(const BranchNode(id: 'n', title: 't', parentId: 'p', body: 'b').toJson()['body'], 'b');
    expect(AssistantSearchResult('title', Uri.parse('https://example.com'), 'summary').toJson()['summary'], 'summary');
    final source = AssistantSource(
      id: 's',
      version: 1,
      kind: 'snapshot',
      title: 'title',
      url: Uri.parse('https://example.com'),
      paragraphs: {'p': 'text'},
    );
    expect(() => source.paragraphs.clear(), throwsUnsupportedError);
  });
  test('closed operation fields, proposal and execution receipt roundtrip', () {
    final ops = [
      const MapEditOperation(id: '1', kind: MapEditKind.addTopic, parentId: 'root', title: 'T'),
      const MapEditOperation(id: '2', kind: MapEditKind.addNote, parentId: 'root', title: 'T', body: 'B'),
      const MapEditOperation(id: '3', kind: MapEditKind.addReviewCard, parentId: 'root', question: 'Q', answer: 'A'),
      const MapEditOperation(id: '4', kind: MapEditKind.move, nodeId: 'n', parentId: 'root'),
      const MapEditOperation(id: '5', kind: MapEditKind.rename, nodeId: 'n', title: 'T'),
    ];
    final proposal = MapEditProposal(id: 'p', studySetId: 's', mapId: 'm', baseRevision: 2, operations: ops);
    expect(MapEditProposal.fromJson(Map<String, dynamic>.from(proposal.toJson())).operations, hasLength(5));
    final receipt = MapEditReceipt(
      proposalId: 'p',
      revision: 3,
      undoHandle: 'undo',
      operationIds: ['1'],
      nodeIds: ['new'],
    );
    expect(MapEditReceipt.fromJson(Map<String, dynamic>.from(receipt.toJson())).undoHandle, 'undo');
    for (final bad in [
      {'id': '1', 'kind': 'addTopic', 'parentId': 'root', 'title': 'T', 'nodeId': 'root'},
      {'id': 'x', 'kind': 'rename', 'nodeId': 'n'},
      {'kind': 'move'},
      {'id': '', 'kind': 'move'},
      {'id': 'x', 'kind': 'move', 'delete': true},
    ]) {
      expect(() => MapEditOperation.fromJson(bad), throwsA(anything));
    }
    expect(const SaveNoteRequest(title: 'title', mapId: 'm', parentId: 'root').mapId, 'm');
  });
}
