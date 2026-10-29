import '../../app/providers.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';

import '../../shared/l10n.dart';
import 'workspace_controller.dart';

class ReaderCropState {
  const ReaderCropState({this.automatic, this.draft, this.position, this.zoom = 1, this.busy = false});
  final DocumentCrop? automatic, draft;
  final PdfReadingPosition? position;
  final double zoom;
  final bool busy;
  bool get editing => draft != null;
}

final readerCropProvider = NotifierProvider.autoDispose.family<ReaderCropSession, ReaderCropState, String>(
  ReaderCropSession.new,
);

/// A draft stays in the reading session. Only Done writes one undoable edit.
class ReaderCropSession extends Notifier<ReaderCropState> {
  ReaderCropSession(this.studySetId);
  final String studySetId;
  String? _documentId;
  int _generation = 0;
  bool _committing = false;
  @override
  ReaderCropState build() {
    _documentId = ref.watch(workspaceProvider(studySetId).select((s) => s.activeDocumentId));
    _generation++;
    _committing = false;
    return const ReaderCropState();
  }

  WorkspaceController get _workspace => ref.read(workspaceProvider(studySetId).notifier);
  MMPdfViewController get _pdf => ref.read(readerPdfProvider(studySetId));
  Document? get document => _documentId == null ? null : _workspace.content.document(_documentId!);

  List<AnnotationPage> get anchors => [
    for (final n in _workspace.content.marginNotes.where((n) => n.documentId == _documentId))
      if (n.anchor != null)
        ...n.anchor!.pages
      else if (_pdf.pageSize(n.page) case final size?)
        AnnotationPage(page: n.page, rects: [PageRect(size.width / 2, n.lineY!, size.width / 2, n.lineY!)]),
  ];

  Future<void> prepare({bool refresh = false}) async {
    if (state.busy || document == null || !_pdf.isReady) return;
    if (!refresh && state.automatic != null) {
      // Readiness changed after a display-document reload; update menu state.
      state = ReaderCropState(
        automatic: state.automatic,
        draft: state.draft,
        position: state.position,
        zoom: state.zoom,
      );
      return;
    }
    final generation = _generation;
    final previous = state;
    state = ReaderCropState(
      automatic: previous.automatic,
      draft: previous.draft,
      position: previous.position,
      zoom: previous.zoom,
      busy: true,
    );
    try {
      final automatic = await _pdf.automaticCrop(anchors: anchors, refresh: refresh);
      if (!ref.mounted || generation != _generation) return;
      // Keep draft changes made while the background analysis was running.
      state = ReaderCropState(automatic: automatic, draft: state.draft, position: state.position, zoom: state.zoom);
    } catch (_) {
      if (ref.mounted && generation == _generation) {
        state = ReaderCropState(
          automatic: previous.automatic,
          draft: state.draft,
          position: state.position,
          zoom: state.zoom,
        );
      }
    }
  }

  bool get canToggle =>
      _pdf.isReady &&
      !state.editing &&
      !state.busy &&
      (document?.crop?.enabled == true || _hasCrop(document?.crop) || _hasCrop(state.automatic));
  bool _hasCrop(DocumentCrop? crop) =>
      crop != null && [crop.all, ?crop.odd, ...crop.pages.values].any((c) => c.left + c.right + c.top + c.bottom > 0);

  Future<bool?> toggle() async {
    final doc = document;
    if (doc == null || state.editing || state.busy || !_pdf.isReady) return null;
    final generation = _generation;
    state = ReaderCropState(automatic: state.automatic, busy: true);
    try {
      if (doc.crop?.enabled == true) {
        await _workspace.setDocumentCrop(doc.id, doc.crop!.copyWith(enabled: false));
        return false;
      }
      // Reuse the cached raster, but always expand for the latest user marks.
      final crop = doc.crop?.mode == CropMode.manual
          ? doc.crop!.copyWith(enabled: true)
          : await _pdf.automaticCrop(anchors: anchors);
      if (!ref.mounted || generation != _generation || crop == null || !_hasCrop(crop)) return null;
      for (var page = 1; page <= _pdf.pageCount; page++) {
        final size = _pdf.pageSize(page)!;
        crop.forPage(page).validateSize(size.width, size.height);
      }
      await _workspace.setDocumentCrop(doc.id, crop);
      return true;
    } finally {
      if (ref.mounted && generation == _generation) state = ReaderCropState(automatic: state.automatic);
    }
  }

  Future<void> adjust() async {
    final doc = document;
    if (doc == null || state.editing || state.busy || !_pdf.isReady) return;
    final position = _pdf.readingPosition;
    final zoom = _pdf.zoom;
    await _workspace.setTool(AnnotationTool.select);
    await _pdf.clearSelection();
    if (!ref.mounted || document?.id != doc.id) return;
    state = ReaderCropState(
      automatic: state.automatic,
      draft: doc.crop?.copyWith(enabled: true) ?? state.automatic ?? DocumentCrop(all: CropInsets()),
      position: position,
      zoom: zoom,
    );
  }

  void scope(CropScope scope) {
    final draft = state.draft;
    if (draft == null || draft.scope == scope) return;
    _draft(changeCropScope(draft, scope, _pdf.currentPage));
  }

  void change(int page, CropInsets insets) {
    if (state.draft == null) return;
    _draft(changeCropPage(state.draft!, page, insets));
  }

  void _draft(DocumentCrop crop) => state = ReaderCropState(
    automatic: state.automatic,
    draft: crop,
    position: state.position,
    zoom: state.zoom,
    busy: state.busy,
  );
  Future<void> automatic() async {
    await prepare(refresh: true);
    if (ref.mounted && state.editing && state.automatic != null) _draft(state.automatic!);
  }

  void none() => _draft(DocumentCrop(all: CropInsets()));
  void cancel() {
    if (!state.editing || _committing) return;
    _pdf.restoreZoomAfterCrop(state.zoom);
    _exit();
  }

  Future<void> complete() async {
    final doc = document, draft = state.draft;
    if (doc == null || draft == null || state.busy) return;
    for (var n = 1; n <= _pdf.pageCount; n++) {
      final size = _pdf.pageSize(n)!;
      draft.forPage(n).validateSize(size.width, size.height);
    }
    final enabled = [draft.all, ?draft.odd, ...draft.pages.values].any((c) => c.left + c.right + c.top + c.bottom > 0);
    final before = state;
    final generation = _generation;
    _committing = true;
    state = ReaderCropState(
      automatic: before.automatic,
      draft: draft,
      position: before.position,
      zoom: before.zoom,
      busy: true,
    );
    try {
      await _workspace.setDocumentCrop(doc.id, draft.copyWith(enabled: enabled));
      if (!ref.mounted || generation != _generation) return;
      _pdf.restoreZoomAfterCrop(before.zoom);
      _exit();
    } catch (_) {
      if (ref.mounted && generation == _generation) state = before;
      rethrow;
    } finally {
      if (ref.mounted && generation == _generation) _committing = false;
    }
  }

  void _exit() {
    final position = state.position;
    state = ReaderCropState(automatic: state.automatic);
    // PDF view restores this original position after leaving full-page layout.
    _pdf.restorePositionAfterCrop(position);
  }
}

Future<void> toggleReaderCrop(BuildContext context, WidgetRef ref, String studySetId) async {
  if (FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<EditableText>() != null) return;
  try {
    final enabled = await ref.read(readerCropProvider(studySetId).notifier).toggle();
    if (enabled == null || !context.mounted) return;
    MMHud.show(
      context,
      enabled ? context.l10n.croppedHud : context.l10n.uncroppedHud,
      action: (context.l10n.undo, () => ref.read(workspaceProvider(studySetId).notifier).undo()),
    );
  } catch (_) {
    if (context.mounted) MMHud.show(context, context.l10n.somethingWentWrong);
  }
}

Future<void> completeReaderCrop(BuildContext context, WidgetRef ref, String studySetId) async {
  try {
    await ref.read(readerCropProvider(studySetId).notifier).complete();
  } catch (_) {
    if (context.mounted) MMHud.show(context, context.l10n.somethingWentWrong);
  }
}
