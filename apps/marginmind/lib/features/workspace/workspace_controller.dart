import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../app/providers.dart';

enum MapViewMode { map, outline }

enum AnnotationTool { select, highlight, area, pen, text }

/// A document inside the open study set. Placeholder model until the
/// document and annotation tables land in mm_core / mm_data.
class WorkspaceDocument {
  const WorkspaceDocument({required this.id, required this.title, required this.pageCount, required this.currentPage});

  final String id;
  final String title;
  final int pageCount;
  final int currentPage;
}

class WorkspaceState {
  const WorkspaceState({
    required this.studySet,
    required this.documents,
    this.sidebarVisible = true,
    this.layout = MMSplitMode.split,
    this.splitFraction = 0.5,
    this.mapView = MapViewMode.map,
    this.tool = AnnotationTool.highlight,
    this.color = MMAnnotationColor.yellow,
    this.syncToMap = true,
    this.openDocumentIds = const [],
    this.activeDocumentId,
    this.sidebarQuery = '',
  });

  final StudySet? studySet;
  final List<WorkspaceDocument> documents;
  final bool sidebarVisible;
  final MMSplitMode layout;
  final double splitFraction;
  final MapViewMode mapView;
  final AnnotationTool tool;
  final MMAnnotationColor color;

  /// Whether a new highlight also creates a card in the mind map.
  final bool syncToMap;
  final List<String> openDocumentIds;
  final String? activeDocumentId;
  final String sidebarQuery;

  WorkspaceDocument? get activeDocument => documents.where((d) => d.id == activeDocumentId).firstOrNull;

  List<WorkspaceDocument> get openDocuments => [
    for (final id in openDocumentIds) ...documents.where((d) => d.id == id),
  ];

  WorkspaceState copyWith({
    bool? sidebarVisible,
    MMSplitMode? layout,
    double? splitFraction,
    MapViewMode? mapView,
    AnnotationTool? tool,
    MMAnnotationColor? color,
    bool? syncToMap,
    List<String>? openDocumentIds,
    String? activeDocumentId,
    bool clearActive = false,
    String? sidebarQuery,
  }) {
    return WorkspaceState(
      studySet: studySet,
      documents: documents,
      sidebarVisible: sidebarVisible ?? this.sidebarVisible,
      layout: layout ?? this.layout,
      splitFraction: splitFraction ?? this.splitFraction,
      mapView: mapView ?? this.mapView,
      tool: tool ?? this.tool,
      color: color ?? this.color,
      syncToMap: syncToMap ?? this.syncToMap,
      openDocumentIds: openDocumentIds ?? this.openDocumentIds,
      activeDocumentId: clearActive ? null : (activeDocumentId ?? this.activeDocumentId),
      sidebarQuery: sidebarQuery ?? this.sidebarQuery,
    );
  }
}

/// Panel state of one study set window: sidebar, layout (source / split /
/// map), divider position, open document tabs, tool and color.
class WorkspaceController extends Notifier<WorkspaceState> {
  WorkspaceController(this.studySetId);

  final String studySetId;

  @override
  WorkspaceState build() {
    final sets = ref.read(studySetsProvider).value ?? const <StudySet>[];
    final set = sets.where((s) => s.id == studySetId).firstOrNull;
    final docs = demoDocuments(set);
    return WorkspaceState(
      studySet: set,
      documents: docs,
      openDocumentIds: [for (final d in docs.take(2)) d.id],
      activeDocumentId: docs.firstOrNull?.id,
    );
  }

  void toggleSidebar() => state = state.copyWith(sidebarVisible: !state.sidebarVisible);

  void setLayout(MMSplitMode layout) => state = state.copyWith(layout: layout);

  void setSplitFraction(double value) => state = state.copyWith(splitFraction: value.clamp(0.1, 0.9));

  void setMapView(MapViewMode view) => state = state.copyWith(mapView: view);

  void setTool(AnnotationTool tool) => state = state.copyWith(tool: tool);

  void setColor(MMAnnotationColor color) => state = state.copyWith(color: color, tool: AnnotationTool.highlight);

  void toggleSyncToMap() => state = state.copyWith(syncToMap: !state.syncToMap);

  void setSidebarQuery(String query) => state = state.copyWith(sidebarQuery: query);

  /// Opens (or focuses) a document tab. In map-only layout the source pane
  /// comes back, since the user asked to see a document.
  void openDocument(String id) {
    final open = state.openDocumentIds.contains(id) ? state.openDocumentIds : [...state.openDocumentIds, id];
    state = state.copyWith(
      openDocumentIds: open,
      activeDocumentId: id,
      layout: state.layout == MMSplitMode.secondary ? MMSplitMode.split : null,
    );
  }

  void closeDocument(String id) {
    final open = [...state.openDocumentIds]..remove(id);
    final wasActive = state.activeDocumentId == id;
    state = state.copyWith(
      openDocumentIds: open,
      activeDocumentId: wasActive ? open.lastOrNull : null,
      clearActive: wasActive && open.isEmpty,
    );
  }

  /// Sample documents so the panels have something to show before import
  /// exists.
  static List<WorkspaceDocument> demoDocuments(StudySet? set) {
    if (set == null || set.documentCount == 0) return const [];
    const extra = ['论文：检索练习效应', '课程讲义', '阅读笔记', '参考资料'];
    final first = set.lastPosition;
    return [
      WorkspaceDocument(
        id: '${set.id}-doc-1',
        title: first?.documentTitle ?? set.title,
        pageCount: 164,
        currentPage: first?.page ?? 1,
      ),
      for (var i = 1; i < set.documentCount; i++)
        WorkspaceDocument(
          id: '${set.id}-doc-${i + 1}',
          title: i <= extra.length ? extra[i - 1] : '${extra.last} $i',
          pageCount: 12 + i * 8,
          currentPage: 1,
        ),
    ];
  }
}

final workspaceProvider = NotifierProvider.family<WorkspaceController, WorkspaceState, String>(WorkspaceController.new);
