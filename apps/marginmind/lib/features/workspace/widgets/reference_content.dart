import '../../assistant/widgets/assistant_panel.dart';
import '../../assistant/assistant_controller.dart';
import '../../assistant/assistant_scope.dart';

import 'dart:async';

import 'card_details.dart';

import '../../vocabulary/vocabulary_controller.dart';
import '../../vocabulary/vocabulary_screen.dart';
import '../workspace_content_host.dart';
import '../reader_crop.dart';
import '../reader_margin.dart';
import '../reader_translation.dart';
import '../workspace_browser.dart';
import '../reflow_session.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';

import '../../../app/providers.dart';
import '../../../shared/card_image.dart';
import '../../../shared/l10n.dart';
import '../../study_notes/note_view.dart';
import '../reader_compare.dart';
import '../workspace_controller.dart';
import '../workspace_pane_chrome_controller.dart';
import 'map_pane.dart';
import 'reader_pane.dart';
import 'workspace_toolbar.dart';
import 'right_panel.dart';

/// References share repository edits, not main navigation or PDF controllers.
class ReferenceContent extends ConsumerStatefulWidget {
  const ReferenceContent({
    super.key,
    required this.studySetId,
    required this.reference,
    this.ownerTitle = '',
    this.ownerTabId,
  });
  final String studySetId;
  final WorkspaceReference reference;
  final String ownerTitle;
  final String? ownerTabId;
  @override
  ConsumerState<ReferenceContent> createState() => _ReferenceContentState();
}

class _ReferenceContentState extends ConsumerState<ReferenceContent> {
  final _chrome = WorkspacePaneChromeController();
  ProviderContainer? _container;
  String get _setId => widget.reference.studySetId ?? widget.studySetId;
  @override
  void dispose() {
    final container = _container;
    if (container != null) {
      unawaited(container.read(workspaceProvider(_setId).notifier).flushEdits().whenComplete(container.dispose));
    }
    _chrome.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.reference.studySetId ?? widget.studySetId;
    final owner = ref.read(workspaceProvider(widget.studySetId).notifier);
    final showAssistant = ref.watch(
      workspaceProvider(widget.studySetId).select(
        (s) =>
            (widget.ownerTabId == null ? s.tabs.current : s.tabs.contexts[widget.ownerTabId])?.referenceAssistant ??
            false,
      ),
    );
    void close() {
      if (mounted &&
          identical(ref.read(workspaceProvider(widget.studySetId)).tabs.current.reference, widget.reference)) {
        owner.closePanel();
      }
    }

    void open(WorkspaceReference reference) {
      if (mounted &&
          identical(ref.read(workspaceProvider(widget.studySetId)).tabs.current.reference, widget.reference)) {
        owner.openReference(reference);
      }
    }

    final container = _container ??= ProviderContainer(
      parent: WorkspaceDataScope.maybeOf(context) ?? ProviderScope.containerOf(context, listen: false),
      overrides: [
        assistantUiProvider.overrideWith2(AssistantUiController.new),
        assistantDependenciesProvider.overrideWith((ref) => ref.watch(assistantDependenciesForProvider(id))),
        assistantControllerProvider.overrideWith(AssistantController.new),
        assistantBackgroundProvider.overrideWith(AssistantBackground.new),
        // Override the family itself: instance overrides can share a family
        // directory with the parent in Riverpod 3.4 and replace its notifier.
        workspaceProvider.overrideWith2(
          (setId) => setId == id
              ? _ReferenceWorkspace(
                  id,
                  widget.reference,
                  open,
                  close,
                  (panel, origin) {
                    if (!mounted ||
                        !identical(
                          ref.read(workspaceProvider(widget.studySetId)).tabs.current.reference,
                          widget.reference,
                        )) {
                      return;
                    }
                    if (panel == RightPanel.assistant) {
                      owner.openReferenceAssistant();
                    } else {
                      owner.openPanel(panel, origin: origin);
                    }
                  },
                  (tag) {
                    if (mounted &&
                        identical(
                          ref.read(workspaceProvider(widget.studySetId)).tabs.current.reference,
                          widget.reference,
                        )) {
                      owner.filterTag(tag);
                    }
                  },
                )
              : WorkspaceController(setId),
        ),
        workspaceContentProvider.overrideWith(createWorkspaceContent),
        readingPagesProvider.overrideWith2(ReadingPages.new),
        documentPdfProvider.overrideWith((ref, key) {
          final pdf = MMPdfViewController();
          ref.onDispose(pdf.dispose);
          return pdf;
        }),
        readerPdfProvider.overrideWith((ref, setId) {
          final documentId = ref.watch(workspaceProvider(setId).select((s) => s.activeDocumentId));
          return ref.watch(documentPdfProvider((setId, documentId)));
        }),
        readerCompareProvider.overrideWith2(ReaderCompareSession.new),
        readerCropProvider.overrideWith2(ReaderCropSession.new),
        readerDocumentCropProvider.overrideWith2((key) => ReaderCropSession(key.$1, documentId: key.$2)),
        readerMarginProvider.overrideWith2(ReaderMarginSession.new),
        readerTranslationProvider.overrideWith2(ReaderTranslationController.new),
        translationSourceInputProvider.overrideWith2(TranslationSourceInput.new),
        workspaceBrowserProvider.overrideWith2(WorkspaceBrowser.new),
        reflowSessionProvider.overrideWith(createReflowSession),
      ],
    );
    return UncontrolledProviderScope(
      container: container,
      child: WorkspacePaneChromeScope(
        controller: _chrome,
        child: WorkspaceToolbarScope(
          actions: const [],
          leading: null,
          ownsActions: false,
          ownsLeading: false,
          useGeometry: false,
          child: CardImageScope(
            resolve: (name) => ref.read(contentRepositoryProvider).resolveFile(id, name),
            child: WorkspaceContentHost(
              openSource: (sourceId, anchor) =>
                  mounted &&
                      identical(ref.read(workspaceProvider(widget.studySetId)).tabs.current.reference, widget.reference)
                  ? owner.openAnchorReference(anchor, sourceStudySetId: sourceId)
                  : Future.value(false),
              child: AssistantHost(
                studySetId: id,
                child: _ReferenceBody(
                  studySetId: id,
                  reference: widget.reference,
                  ownerTitle: widget.ownerTitle,
                  onClose: close,
                  showAssistant: showAssistant,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReferenceBody extends ConsumerStatefulWidget {
  const _ReferenceBody({
    required this.studySetId,
    required this.reference,
    required this.onClose,
    required this.ownerTitle,
    required this.showAssistant,
  });
  final String studySetId;
  final WorkspaceReference reference;
  final VoidCallback onClose;
  final String ownerTitle;
  @override
  ConsumerState<_ReferenceBody> createState() => _ReferenceBodyState();
  final bool showAssistant;
}

class _ReferenceBodyState extends ConsumerState<_ReferenceBody> {
  bool _initialized = false;
  bool _assistantOpened = false;
  @override
  Widget build(BuildContext context) {
    final studySetId = widget.studySetId;
    final reference = widget.reference;
    final ownerTitle = widget.ownerTitle;
    final onClose = widget.onClose;
    final content = ref.watch(workspaceContentProvider(studySetId));
    if (!_initialized && content != null) {
      _initialized = true;
      if (reference.kind == WorkspaceReferenceKind.map && reference.anchor?.target is CardTarget) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref.read(workspaceProvider(studySetId).notifier).revealAnchor(reference.anchor!, asReference: false);
          }
        });
      }
    }
    final missing =
        content != null &&
        switch (reference.kind) {
          WorkspaceReferenceKind.document => content.document(reference.id) == null,
          WorkspaceReferenceKind.map => content.map(reference.id) == null,
          WorkspaceReferenceKind.note => content.studyNote(reference.id) == null,
          WorkspaceReferenceKind.vocabulary => false,
          WorkspaceReferenceKind.card => content.card(reference.id) == null,
        };
    _assistantOpened |= widget.showAssistant;
    final body = Column(
      children: [
        if (reference.kind != WorkspaceReferenceKind.card)
          RightPanelHeader(icon: MMIcons.document, title: context.l10n.workspaceReferenceTitle, onClose: onClose),
        if (ownerTitle.isNotEmpty && reference.kind != WorkspaceReferenceKind.card)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: MMSpacing.l, vertical: MMSpacing.s),
              child: Text(
                context.l10n.workspaceReferenceFrom(ownerTitle),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.mmText.footnote.copyWith(color: context.mmColors.secondaryLabel),
              ),
            ),
          ),
        Expanded(
          child: missing
              ? Center(child: Text(context.l10n.assistantAnchorGone))
              : switch (reference.kind) {
                  WorkspaceReferenceKind.document => ReaderPane(studySetId: studySetId),
                  WorkspaceReferenceKind.map => MapPane(studySetId: studySetId),
                  WorkspaceReferenceKind.note => StudyNoteView(studySetId: studySetId, noteId: reference.id),
                  WorkspaceReferenceKind.card => CardDetails(studySetId: studySetId, ownerTitle: ownerTitle),
                  WorkspaceReferenceKind.vocabulary => _VocabularyReference(
                    studySetId: studySetId,
                    entryId: reference.id,
                  ),
                },
        ),
      ],
    );
    return WorkspaceCommandTarget(
      container: ProviderScope.containerOf(context, listen: false),
      studySetId: studySetId,
      isMounted: () => mounted,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Offstage(
            offstage: widget.showAssistant,
            child: TickerMode(
              enabled: !widget.showAssistant,
              child: ExcludeFocus(excluding: widget.showAssistant, child: body),
            ),
          ),
          if (_assistantOpened)
            Offstage(
              offstage: !widget.showAssistant,
              child: TickerMode(
                enabled: widget.showAssistant,
                child: ExcludeFocus(
                  excluding: !widget.showAssistant,
                  child: AssistantPanel(studySetId: studySetId),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReferenceWorkspace extends WorkspaceController {
  _ReferenceWorkspace(super.studySetId, this.target, this.onReference, this.onClose, this.onPanel, this.onTag);
  final void Function(RightPanel, PanelOrigin) onPanel;
  final ValueChanged<String?> onTag;
  @override
  void openPanel(RightPanel content, {PanelOrigin origin = PanelOrigin.toolbar}) => onPanel(content, origin);
  @override
  void filterTag(String? tag) => onTag(tag);
  final VoidCallback onClose;
  @override
  void closePanel() => onClose();
  @override
  void closeDocument(String id) {
    if (state.activeDocumentId == id) {
      onClose();
    } else {
      super.closeDocument(id);
    }
  }

  @override
  void showDetails([String? cardId]) {
    final id = cardId ?? state.selectedCardId;
    if (id == null || content.card(id) == null) return;
    openReference(
      WorkspaceReference.card(
        id,
        anchor: SourceAnchor(
          mapId: state.activeMapId,
          target: CardTarget(cardId: id),
        ),
      ),
    );
  }

  final WorkspaceReference target;
  final void Function(WorkspaceReference) onReference;
  @override
  bool get isReference => true;
  @override
  WorkspaceState build() {
    final initial = super.build();
    final anchor = target.anchor?.target;
    final reveal = switch (anchor) {
      PdfTarget(:final documentId, :final pages) when pages.isNotEmpty => RevealRequest(
        documentId,
        pages.first.page,
        pages.first.rects,
        1,
      ),
      TextTarget(:final documentId, :final textAnchors) => RevealRequest.text(documentId, textAnchors, 1),
      _ => null,
    };
    return initial.copyWith(
      layout: target.kind == WorkspaceReferenceKind.document
          ? MMSplitMode.primary
          : target.kind == WorkspaceReferenceKind.map || target.kind == WorkspaceReferenceKind.card
          ? MMSplitMode.secondary
          : initial.layout,
      activeDocumentId: target.kind == WorkspaceReferenceKind.document ? target.id : null,
      activeMapId: target.kind == WorkspaceReferenceKind.map ? target.id : target.anchor?.mapId,
      activeNoteId: target.kind == WorkspaceReferenceKind.note ? target.id : null,
      openDocumentIds: target.kind == WorkspaceReferenceKind.document ? [target.id] : null,
      selectedCardId: anchor is CardTarget
          ? anchor.cardId
          : target.kind == WorkspaceReferenceKind.card
          ? target.id
          : null,
      detailCardId: target.kind == WorkspaceReferenceKind.card ? target.id : null,
      locateCardTick: anchor is CardTarget ? 1 : 0,
      reveal: reveal,
    );
  }

  @override
  void openDocument(String id, {bool followMap = true}) {
    if (content.document(id) == null) return;
    state = state.copyWith(activeDocumentId: id, openDocumentIds: [id], clearPending: true, clearReveal: true);
  }

  @override
  Future<void> selectMap(String id, {String? forDocumentId, bool keepNote = false}) async {
    if (content.map(id) != null) state = state.copyWith(activeMapId: id, selectRoot: true, clearPending: true);
  }

  @override
  void openReference(WorkspaceReference reference) {
    onReference(switch (reference.kind) {
      WorkspaceReferenceKind.document => WorkspaceReference.document(
        reference.id,
        anchor: reference.anchor,
        studySetId: studySetId,
      ),
      WorkspaceReferenceKind.map => WorkspaceReference.map(
        reference.id,
        anchor: reference.anchor,
        studySetId: studySetId,
      ),
      WorkspaceReferenceKind.note => WorkspaceReference.note(reference.id, studySetId: studySetId),
      WorkspaceReferenceKind.vocabulary => reference,
      WorkspaceReferenceKind.card => WorkspaceReference.card(
        reference.id,
        anchor: reference.anchor,
        studySetId: studySetId,
      ),
    });
  }

  @override
  Future<bool> revealAnchor(SourceAnchor anchor, {bool asReference = true}) async {
    if (!asReference) return super.revealAnchor(anchor, asReference: false);
    final reference = switch (anchor.target) {
      PdfTarget(:final documentId) ||
      TextTarget(:final documentId) => WorkspaceReference.document(documentId, anchor: anchor, studySetId: studySetId),
      CardTarget() => WorkspaceReference.map(anchor.mapId ?? state.activeMapId, anchor: anchor, studySetId: studySetId),
    };
    openReference(reference);
    return true;
  }

  @override
  void openDocumentReference(String id, {SourceAnchor? anchor}) =>
      openReference(WorkspaceReference.document(id, anchor: anchor, studySetId: studySetId));
  @override
  void revealNoteAnnotation(String id) {
    final a = content.annotation(id);
    if (a == null || a.needsReview) return;
    unawaited(
      revealAnchor(
        SourceAnchor(
          target: a.isText
              ? TextTarget(documentId: a.documentId, textAnchors: a.textAnchors)
              : PdfTarget(
                  documentId: a.documentId,
                  pages: [AnnotationPage(page: a.page, rects: a.rects)],
                ),
        ),
      ),
    );
  }

  @override
  void revealNoteMargin(String id) {
    final note = content.marginNotes.where((n) => n.id == id).firstOrNull;
    if (note == null) return;
    unawaited(
      revealAnchor(
        SourceAnchor(
          target: note.anchor?.textAnchors.isNotEmpty == true
              ? TextTarget(documentId: note.documentId, textAnchors: note.anchor!.textAnchors)
              : PdfTarget(
                  documentId: note.documentId,
                  pages: [AnnotationPage(page: note.page, rects: const [])],
                ),
        ),
      ),
    );
  }

  @override
  Future<void> revealNoteCard(String id) async {
    final node = content.nodes.where((n) => n.cardId == id).firstOrNull;
    if (node != null) {
      await revealAnchor(
        SourceAnchor(
          mapId: node.mapId,
          target: CardTarget(cardId: id),
        ),
      );
    }
  }

  @override
  Future<void> openNoteMap(String id) async => openReference(WorkspaceReference.map(id, studySetId: studySetId));
  @override
  void revealMapSource(CardSource source) => openDocumentReference(
    source.documentId,
    anchor: SourceAnchor(
      target: PdfTarget(
        documentId: source.documentId,
        pages: [AnnotationPage(page: source.page, rects: const [])],
      ),
    ),
  );
  @override
  void revealSegment(String id, int index) {
    final card = content.card(id);
    if (card == null) return;
    final segments = content.segmentsOf(card);
    if (index >= 0 && index < segments.length) {
      if (segments[index].annotationId case final annotationId?) revealNoteAnnotation(annotationId);
    }
  }

  @override
  void revealCard(String id) {
    final card = content.card(id);
    if (card == null) return;
    if (card.source case final source?) {
      revealMapSource(source);
      return;
    }
    revealSegment(id, content.segmentsOf(card).indexWhere((s) => s.annotationId != null));
  }

  @override
  void openStudyNote(String id) {
    if (content.studyNote(id) != null) onReference(WorkspaceReference.note(id, studySetId: studySetId));
  }
}

class _VocabularyReference extends ConsumerWidget {
  const _VocabularyReference({required this.studySetId, required this.entryId});
  final String studySetId, entryId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vocabulary = ref.watch(vocabularyProvider);
    final entry = vocabulary.value?.entries.where((e) => e.id == entryId).firstOrNull;
    if (vocabulary.isLoading) return const Center(child: CircularProgressIndicator());
    if (entry == null) return Center(child: Text(context.l10n.vocabularyEmpty));
    return VocabularyDetail(entry: entry, studySetId: studySetId);
  }
}
