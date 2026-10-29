import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';

import '../../app/providers.dart';
import 'workspace_controller.dart';

class ReaderMarginState {
  const ReaderMarginState({
    this.openDocuments = const {},
    this.draft,
    this.popup = const {},
    this.hovered,
    this.deleted = 0,
    this.errors = 0,
  });
  final Set<String> openDocuments, popup;
  final MarginNote? draft;
  final String? hovered;
  final int deleted, errors;
}

final readerMarginProvider = NotifierProvider.autoDispose.family<ReaderMarginSession, ReaderMarginState, String>(
  ReaderMarginSession.new,
);

class ReaderMarginSession extends Notifier<ReaderMarginState> {
  ReaderMarginSession(this.studySetId);
  final String studySetId;
  Future<bool>? _saving;
  WorkspaceController get _workspace => ref.read(workspaceProvider(studySetId).notifier);

  @override
  ReaderMarginState build() {
    ref.listen(workspaceProvider(studySetId).select((s) => s.activeDocumentId), (before, after) {
      if (before != after) finish();
    });
    return const ReaderMarginState();
  }

  void _set({
    Set<String>? open,
    MarginNote? draft,
    bool clearDraft = false,
    Set<String>? popup,
    String? hovered,
    bool clearHover = false,
    int? deleted,
    int? errors,
  }) {
    state = ReaderMarginState(
      openDocuments: open ?? state.openDocuments,
      draft: clearDraft ? null : draft ?? state.draft,
      popup: popup ?? state.popup,
      hovered: clearHover ? null : hovered ?? state.hovered,
      deleted: deleted ?? state.deleted,
      errors: errors ?? state.errors,
    );
  }

  void toggle(String documentId) {
    final open = {...state.openDocuments};
    if (!open.remove(documentId)) open.add(documentId);
    _set(open: open, popup: {});
  }

  void expand(String documentId) => _set(open: {...state.openDocuments, documentId}, popup: {});
  void hover(String? id) => _set(hovered: id, clearHover: id == null);
  void show(Iterable<MarginNote> notes) => _set(popup: notes.map((n) => n.id).toSet());
  Future<void> close() async {
    if (await finish() && ref.mounted) _set(popup: {});
  }

  List<MarginNote> notes(String documentId) => [
    for (final note in _workspace.content.marginNotes)
      if (note.documentId == documentId && note.id != state.draft?.id) note,
    if (state.draft?.documentId == documentId) state.draft!,
  ];

  Future<void> start(
    String documentId, {
    List<AnnotationPage>? pages,
    List<TextAnchor> textAnchors = const [],
    String quote = '',
    int? page,
    double? lineY,
    int? colorIndex,
    MarginNote? existing,
  }) async {
    if (existing?.id == state.draft?.id && existing != null) return;
    if (!await finish() || !ref.mounted) return;
    final editor = ref.read(editorProvider);
    final anchor = textAnchors.isNotEmpty
        ? (anchor: AnnotationAnchor(textAnchors: textAnchors, quote: quote), lineY: null)
        : pages == null
        ? (anchor: null, lineY: lineY)
        : marginAnchor(pages, quote);
    final candidate =
        existing ??
        MarginNote(
          id: editor.newId(),
          documentId: documentId,
          page: textAnchors.isNotEmpty ? null : page ?? pages!.first.page,
          anchor: anchor.anchor,
          lineY: anchor.lineY,
          text: '',
          colorIndex: colorIndex ?? ref.read(workspaceProvider(studySetId)).color.index,
          createdAt: editor.now(),
          updatedAt: editor.now(),
        );
    // Geometry is the identity of a text anchor; highlight lifetime is independent.
    final note =
        existing ??
        _workspace.content.marginNotes
            .where(
              (n) =>
                  n.documentId == documentId &&
                  (textAnchors.isNotEmpty || n.page == candidate.page) &&
                  n.lineY == candidate.lineY &&
                  jsonEncode(n.anchor?.toJson()) == jsonEncode(candidate.anchor?.toJson()),
            )
            .firstOrNull ??
        candidate;
    _workspace.dismissPending();
    _set(
      open: existing != null ? state.openDocuments : {...state.openDocuments, documentId},
      draft: note,
      popup: {note.id},
    );
  }

  void text(String value) {
    if (state.draft case final draft?) _set(draft: draft.copyWith(text: value));
  }

  Future<bool> finish() {
    if (_saving != null) return _saving!;
    final draft = state.draft;
    if (draft == null) return Future.value(true);
    return _saving = _finish(draft).whenComplete(() => _saving = null);
  }

  Future<bool> _finish(MarginNote draft) async {
    final original = _workspace.content.marginNotes.where((n) => n.id == draft.id).firstOrNull;
    try {
      if (draft.text.trim().isNotEmpty || original != null) {
        // Saving without a change must not create an undo step or stale linked title.
        if (original == null || original.text != draft.text.trim() || original.colorIndex != draft.colorIndex) {
          await _workspace.saveMarginNote(draft.copyWith(updatedAt: ref.read(editorProvider).now()));
        }
      }
      if (ref.mounted && state.draft?.id == draft.id) {
        final latest = state.draft!;
        if (latest.text != draft.text || latest.colorIndex != draft.colorIndex) return await _finish(latest);
        _set(clearDraft: true, deleted: state.deleted + (original != null && draft.text.trim().isEmpty ? 1 : 0));
      }
      return true;
    } catch (_) {
      if (ref.mounted) _set(errors: state.errors + 1);
      return false;
    }
  }

  Future<void> recolor(MarginNote note, int colorIndex) async {
    try {
      if (state.draft?.id == note.id) {
        _set(draft: state.draft!.copyWith(colorIndex: colorIndex));
      } else {
        await _workspace.saveMarginNote(note.copyWith(colorIndex: colorIndex));
      }
    } catch (_) {
      if (ref.mounted) _set(errors: state.errors + 1);
    }
  }

  Future<void> delete(MarginNote note) async {
    if (_saving != null && !await _saving!) return;
    try {
      final saved = _workspace.content.marginNotes.any((n) => n.id == note.id);
      if (saved) await _workspace.deleteMarginNote(note.id);
      if (!ref.mounted) return;
      if (state.draft?.id == note.id) _set(clearDraft: true);
      if (saved) _set(deleted: state.deleted + 1);
    } catch (_) {
      if (ref.mounted) _set(errors: state.errors + 1);
    }
  }
}
