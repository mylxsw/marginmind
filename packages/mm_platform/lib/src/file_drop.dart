import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/widgets.dart';

import 'capabilities.dart';
import 'document_files.dart';

/// Keeps the desktop plugin and its objects behind a platform-owned widget.
class MMFileDropTarget extends StatelessWidget {
  const MMFileDropTarget({super.key, required this.onDrop, required this.onHover, required this.child});
  final ValueChanged<List<MMDocumentFile>> onDrop;
  final ValueChanged<bool> onHover;
  final Widget child;
  @override
  Widget build(BuildContext context) => !MMPlatformCapabilities.current.desktopDrop
      ? child
      : DropTarget(
          enable: ModalRoute.of(context)?.isCurrent ?? true,
          onDragEntered: (_) => onHover(true),
          onDragExited: (_) => onHover(false),
          onDragDone: (details) {
            onHover(false);
            onDrop([for (final f in details.files) (path: f.path, name: f.name)]);
          },
          child: child,
        );
}
