import 'package:mm_core/mm_core.dart';

/// A right sidebar displays content; its entry points live elsewhere.
enum RightPanel { assistant, details, reference, tags }

enum WorkspaceTabKind { documentMap, note, vocabulary, review, statistics }

class WorkspaceTab {
  const WorkspaceTab(this.kind, {this.noteId});
  static const documents = WorkspaceTab(WorkspaceTabKind.documentMap);
  static const vocabulary = WorkspaceTab(WorkspaceTabKind.vocabulary);
  static const review = WorkspaceTab(WorkspaceTabKind.review);
  static const statistics = WorkspaceTab(WorkspaceTabKind.statistics);
  final WorkspaceTabKind kind;
  final String? noteId;
  String get id => kind == WorkspaceTabKind.note ? 'note:$noteId' : kind.name;
}

enum WorkspaceReferenceKind { document, map, note, vocabulary, card }

/// A reference has its own navigation/reader state, never the main subject's.
class WorkspaceReference {
  const WorkspaceReference.document(this.id, {this.anchor, this.studySetId}) : kind = WorkspaceReferenceKind.document;
  const WorkspaceReference.map(this.id, {this.anchor, this.studySetId}) : kind = WorkspaceReferenceKind.map;
  const WorkspaceReference.note(this.id, {this.studySetId}) : kind = WorkspaceReferenceKind.note, anchor = null;
  const WorkspaceReference.card(this.id, {this.studySetId, this.anchor}) : kind = WorkspaceReferenceKind.card;
  const WorkspaceReference.vocabulary(this.id)
    : kind = WorkspaceReferenceKind.vocabulary,
      anchor = null,
      studySetId = null;
  final WorkspaceReferenceKind kind;
  final String id;
  final String? studySetId;
  final SourceAnchor? anchor;
}

class WorkspaceTabContext {
  const WorkspaceTabContext({this.panel, this.reference, this.detailCardId, this.referenceAssistant = false});
  final RightPanel? panel;
  final WorkspaceReference? reference;
  final String? detailCardId;
  final bool referenceAssistant;
}

/// Window-local tabs and their owned references. Never written into study data.
class WorkspaceTabs {
  const WorkspaceTabs({
    this.open = const [WorkspaceTab.documents],
    this.activeId = 'documentMap',
    this.contexts = const {},
  });
  final List<WorkspaceTab> open;
  final String? activeId;
  final Map<String, WorkspaceTabContext> contexts;
  WorkspaceTab? get active => open.where((tab) => tab.id == activeId).firstOrNull;
  WorkspaceTabContext get current => contexts[activeId] ?? const WorkspaceTabContext();

  WorkspaceTabs activate(WorkspaceTab tab) => WorkspaceTabs(
    open: List.unmodifiable(open.any((item) => item.id == tab.id) ? open : [...open, tab]),
    activeId: tab.id,
    contexts: contexts,
  );

  WorkspaceTabs update(WorkspaceTabContext context, {String? tabId}) => WorkspaceTabs(
    open: open,
    activeId: activeId,
    contexts: Map.unmodifiable({...contexts, ?(tabId ?? activeId): context}),
  );

  WorkspaceTabs reorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= open.length || newIndex < 0 || newIndex >= open.length || oldIndex == newIndex) {
      return this;
    }
    final next = [...open];
    next.insert(newIndex, next.removeAt(oldIndex));
    return WorkspaceTabs(open: List.unmodifiable(next), activeId: activeId, contexts: contexts);
  }

  WorkspaceTabs close(String id) {
    final index = open.indexWhere((tab) => tab.id == id);
    if (index < 0) return this;
    final next = open.where((tab) => tab.id != id).toList();
    return WorkspaceTabs(
      open: List.unmodifiable(next),
      activeId: activeId != id
          ? activeId
          : next.isEmpty
          ? null
          : next[index.clamp(0, next.length - 1)].id,
      contexts: Map.unmodifiable({...contexts}..remove(id)),
    );
  }

  WorkspaceTabs clearSubjectReferences() {
    final context = contexts[WorkspaceTab.documents.id];
    final panel = context?.referenceAssistant == true ? null : context?.panel;
    return update(
      WorkspaceTabContext(panel: panel == RightPanel.assistant || panel == RightPanel.tags ? panel : null),
      tabId: WorkspaceTab.documents.id,
    );
  }
}
