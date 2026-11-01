import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';
import 'package:mm_core/mm_core.dart';

/// Content links in an embedded destination belong to its main workspace tab.
class WorkspaceContentHost extends InheritedWidget {
  const WorkspaceContentHost({super.key, required this.openSource, required super.child});
  final Future<bool> Function(String studySetId, SourceAnchor anchor) openSource;
  static WorkspaceContentHost? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WorkspaceContentHost>();
  @override
  bool updateShouldNotify(WorkspaceContentHost oldWidget) => openSource != oldWidget.openSource;
}

/// Menus and keyboard commands follow the focused content surface.
class WorkspaceCommandTarget extends InheritedWidget {
  const WorkspaceCommandTarget({
    super.key,
    required this.container,
    required this.studySetId,
    required this.isMounted,
    required super.child,
  });
  final ProviderContainer container;
  final bool Function() isMounted;
  final String studySetId;
  static WorkspaceCommandTarget? focused() =>
      FocusManager.instance.primaryFocus?.context?.getInheritedWidgetOfExactType<WorkspaceCommandTarget>();
  @override
  bool updateShouldNotify(WorkspaceCommandTarget oldWidget) =>
      container != oldWidget.container || studySetId != oldWidget.studySetId;
}

/// Reference editors can finish saves after a window-local assistant scope
/// closes. Their backend parent is the study-set's original container.
class WorkspaceDataScope extends InheritedWidget {
  const WorkspaceDataScope({super.key, required this.container, required super.child});
  final ProviderContainer container;
  static ProviderContainer? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WorkspaceDataScope>()?.container;
  @override
  bool updateShouldNotify(WorkspaceDataScope oldWidget) => container != oldWidget.container;
}
