import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_platform/mm_platform.dart';

import '../features/workspace/workspace_controller.dart';
import '../shared/l10n.dart';
import 'navigation.dart';
import 'providers.dart';

final windowTitleSinkProvider = Provider<Future<void> Function(String)>((ref) => DesktopWindow.setTitle);

String workspaceWindowTitle(String document, String studySet, String app) =>
    {document.trim(), studySet.trim(), app.trim()}.where((part) => part.isNotEmpty).join(' — ');

/// Serializes writes and coalesces intermediate titles while a write is in
/// flight. A slow old document cannot overwrite the next document's title.
class WindowTitleQueue {
  WindowTitleQueue(this.write);
  final Future<void> Function(String) write;
  String? _wanted, _written;
  bool _running = false, _disposed = false;
  void set(String title) {
    _wanted = title;
    if (!_running && !_disposed) _drain();
  }

  Future<void> _drain() async {
    _running = true;
    try {
      while (!_disposed && _written != _wanted) {
        final title = _wanted!;
        try {
          await write(title);
        } catch (error, stack) {
          FlutterError.reportError(FlutterErrorDetails(exception: error, stack: stack, library: 'window title'));
        }
        _written = title;
      }
    } finally {
      _running = false;
    }
  }

  void dispose() {
    _disposed = true;
  }
}

class WindowTitleBinding extends ConsumerStatefulWidget {
  const WindowTitleBinding({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<WindowTitleBinding> createState() => _WindowTitleBindingState();
}

class _WindowTitleBindingState extends ConsumerState<WindowTitleBinding> {
  late final _queue = WindowTitleQueue(ref.read(windowTitleSinkProvider));
  @override
  void dispose() {
    _queue.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final route = ref.watch(navigationProvider);
    String title;
    if (route is WorkspaceRoute) {
      final id = ref.watch(workspaceProvider(route.studySetId).select((s) => s.activeDocumentId));
      final content = ref.watch(workspaceContentProvider(route.studySetId));
      final name = ref.watch(studySetProvider(route.studySetId).select((s) => s?.title)) ?? '';
      title = workspaceWindowTitle(id == null ? '' : content?.document(id)?.title ?? '', name, l.appName);
    } else {
      final page = switch (route) {
        ReviewRoute() => l.review,
        StatsRoute() => l.statistics,
        GalleryRoute() => l.galleryTitle,
        VocabularyRoute() => l.vocabularyTitle,
        _ => l.libraryTitleAll,
      };
      title = workspaceWindowTitle('', page, l.appName);
    }
    _queue.set(title);
    return Title(
      title: title,
      color: Theme.of(context).colorScheme.surface,
      child: Semantics(label: title, container: true, child: widget.child),
    );
  }
}
