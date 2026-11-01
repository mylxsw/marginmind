import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart' show MMMotion;

import '../../app/providers.dart';
import '../../settings/app_settings.dart';
import '../workspace/workspace_controller.dart';

class DocumentMapNotice {
  const DocumentMapNotice({this.documentId, this.switchedMapId});
  final String? documentId;
  final String? switchedMapId;
}

final documentMapNavigationProvider = NotifierProvider.autoDispose
    .family<DocumentMapNavigation, DocumentMapNotice, String>(
      DocumentMapNavigation.new,
      dependencies: [workspaceProvider],
    );

/// Presentation history belongs to the learning set, never to generated content
/// or its undo stack. Opening a citation keeps the current map in view.
class DocumentMapNavigation extends Notifier<DocumentMapNotice> {
  DocumentMapNavigation(this.studySetId);
  final String studySetId;
  Timer? _timer;
  int _epoch = 0;
  String get _key => 'map_navigation.$studySetId';

  @override
  DocumentMapNotice build() {
    ref.onDispose(() => _timer?.cancel());
    return const DocumentMapNotice();
  }

  void dismiss() {
    _timer?.cancel();
    state = const DocumentMapNotice();
  }

  void recordMap(String id) {
    final prefs = ref.read(sharedPreferencesProvider);
    final recent = prefs.getStringList('$_key.recent') ?? [];
    unawaited(prefs.setStringList('$_key.recent', [id, ...recent.where((m) => m != id)]));
  }

  Future<void> documentChanged(String? id, {bool followMap = true}) async {
    final epoch = ++_epoch;
    dismiss();
    if (id == null || !followMap) return;
    final workspace = ref.read(workspaceProvider(studySetId).notifier);
    final content = workspace.content;
    if (content.document(id) == null) return;
    final prefs = ref.read(sharedPreferencesProvider);
    final maps = content.maps.where((m) => m.generation?.sources.any((s) => s.documentId == id) ?? false).toList();
    if (maps.isEmpty) {
      if (!ref.read(settingsProvider).betaFeaturesEnabled) return;
      final seen = prefs.getStringList('$_key.seen') ?? [];
      if (!seen.contains(id)) {
        // Persist at presentation time: closing, acting, or switching away all
        // count, including when the learning set is reopened later.
        unawaited(prefs.setStringList('$_key.seen', [...seen, id]));
        state = DocumentMapNotice(documentId: id);
      }
      return;
    }
    if (!ref.read(settingsProvider).mapFollowDocument) return;
    final active = ref.read(workspaceProvider(studySetId)).activeMapId;
    final recent = [active, ...?prefs.getStringList('$_key.recent')];
    MindMap target = maps.first;
    // Explicit map selection records MRU; an associated map already in view
    // stays visible only when it is itself most recently used.
    final ordered = prefs.getStringList('$_key.recent') ?? recent;
    for (final mapId in ordered) {
      final match = maps.where((m) => m.id == mapId).firstOrNull;
      if (match != null) {
        target = match;
        break;
      }
    }
    if (target.id == active) return;
    await workspace.selectMap(target.id, forDocumentId: id);
    if (!ref.mounted || epoch != _epoch || ref.read(workspaceProvider(studySetId)).activeMapId != target.id) return;
    state = DocumentMapNotice(switchedMapId: target.id);
    _timer = Timer(MMMotion.hud, () {
      if (ref.mounted && epoch == _epoch) dismiss();
    });
  }
}
