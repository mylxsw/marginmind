import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// A command snapshot contains no renderer, context, or cached widget.
@immutable
class WorkspacePaneCommand {
  const WorkspacePaneCommand(this.invoke, {this.selected = false});
  final VoidCallback? invoke;
  final bool selected;
  bool get enabled => invoke != null;
}

@immutable
class WorkspacePaneCommands {
  WorkspacePaneCommands(this.documentKey, Map<String, WorkspacePaneCommand> commands)
    : commands = Map.unmodifiable(commands);
  final String? documentKey;
  final Map<String, WorkspacePaneCommand> commands;
  bool samePresentation(WorkspacePaneCommands other) =>
      documentKey == other.documentKey &&
      commands.length == other.commands.length &&
      commands.entries.every(
        (entry) =>
            other.commands[entry.key]?.enabled == entry.value.enabled &&
            other.commands[entry.key]?.selected == entry.value.selected,
      );
  void execute(String id) => commands[id]?.invoke?.call();
}

/// Window-local adapters. Identity-checked unbinding prevents an old pane
/// from detaching the replacement document's commands.
class WorkspacePaneChromeController extends ChangeNotifier {
  Object? _readerOwner, _mapOwner;
  WorkspacePaneCommands? _reader, _map;
  bool _scheduled = false, _disposed = false;
  WorkspacePaneCommands? get reader => _reader;
  WorkspacePaneCommands? get map => _map;

  void bindReader(Object owner, WorkspacePaneCommands commands) {
    final changed = _reader?.samePresentation(commands) != true || !identical(owner, _readerOwner);
    _readerOwner = owner;
    _reader = commands;
    if (changed) _changed();
  }

  void bindMap(Object owner, WorkspacePaneCommands commands) {
    final changed = _map?.samePresentation(commands) != true || !identical(owner, _mapOwner);
    _mapOwner = owner;
    _map = commands;
    if (changed) _changed();
  }

  void unbindReader(Object owner) {
    if (!identical(owner, _readerOwner)) return;
    _readerOwner = null;
    _reader = null;
    _changed();
  }

  void unbindMap(Object owner) {
    if (!identical(owner, _mapOwner)) return;
    _mapOwner = null;
    _map = null;
    _changed();
  }

  void _changed() {
    if (_disposed || _scheduled) return;
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      _scheduled = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _scheduled = false;
        if (!_disposed) notifyListeners();
      });
    } else {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _reader = null;
    _map = null;
    super.dispose();
  }
}

class WorkspacePaneChromeScope extends InheritedWidget {
  const WorkspacePaneChromeScope({super.key, required this.controller, required super.child});
  final WorkspacePaneChromeController controller;
  static WorkspacePaneChromeController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WorkspacePaneChromeScope>()?.controller;
  @override
  bool updateShouldNotify(WorkspacePaneChromeScope oldWidget) => controller != oldWidget.controller;
}
