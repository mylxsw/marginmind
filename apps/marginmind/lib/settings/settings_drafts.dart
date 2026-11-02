import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Owns only unsaved UI forms. No credentials or drafts are persisted here.
class SettingsDrafts extends ChangeNotifier {
  final _forms = <Object, ({bool Function() dirty, Future<bool> Function() save})>{};
  bool _disposed = false;
  bool get dirty => _forms.values.any((form) => form.dirty());
  void register(Object owner, {required bool Function() dirty, required Future<bool> Function() save}) {
    _forms[owner] = (dirty: dirty, save: save);
    changed();
  }

  void remove(Object owner) {
    _forms.remove(owner);
    changed();
  }

  void changed() {
    if (_disposed) return;
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) notifyListeners();
      });
    } else {
      notifyListeners();
    }
  }

  Future<bool> save() async {
    for (final form in _forms.values.toList()) {
      if (form.dirty() && !await form.save()) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class SettingsDraftScope extends InheritedWidget {
  const SettingsDraftScope({super.key, required this.drafts, required super.child});
  final SettingsDrafts drafts;
  static SettingsDrafts? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsDraftScope>()?.drafts;
  @override
  bool updateShouldNotify(SettingsDraftScope oldWidget) => drafts != oldWidget.drafts;
}
