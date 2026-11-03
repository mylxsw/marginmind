import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../tokens/modal.dart';

/// iPhone presentation only. Business state stays in the original Dart isolate.
/// iPad, Android, desktop and test hosts retain their existing presentations.
abstract final class MMNativePresentation {
  static const _channel = MethodChannel('marginmind/presentation');
  static bool available = false;
  static int _sequence = 0;
  static final _actions = <String, Future<Map<String, Object?>> Function(String)>{};
  static final _previews = <String, Future<Uint8List?> Function(String)>{};
  static final _validators = <String, FutureOr<String?> Function(Map<String, String>)>{};

  static Future<void> initialize() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'validate' && call.method != 'preview' && call.method != 'action') {
        throw MissingPluginException();
      }
      final args = Map<String, dynamic>.from(call.arguments as Map);
      if (call.method == 'action') return await _actions[args['id']]?.call(args['action'] as String);
      if (call.method == 'preview') return await _previews[args['id']]?.call(args['row'] as String);
      final validate = _validators[args['id']];
      if (validate == null) return 'This form has closed.';
      return await validate(Map<String, String>.from(args['values'] as Map));
    });
    try {
      available = await _channel.invokeMethod<bool>('available') ?? false;
    } on MissingPluginException {
      available = false;
    }
  }

  /// Native UIKit form, medium/large detents, system keyboard and dirty guard.
  /// Validation completes before dismissal, so bad input never loses its draft.
  static Future<Map<String, String>?> form({
    required String title,
    required String cancel,
    required String submit,
    required String discard,
    required String keepEditing,
    required String discardTitle,
    required List<MMNativeField> fields,
    String? message,
    bool? dark,
    FutureOr<String?> Function(Map<String, String>)? validate,
  }) async {
    final id = '${++_sequence}';
    _validators[id] = validate ?? (_) => null;
    try {
      final values = await _channel.invokeMapMethod<String, String>('form', {
        'modalStyle': MMModalStyle.nativeConfiguration,
        'id': id,
        'title': title,
        'cancel': cancel,
        'submit': submit,
        'discard': discard,
        'keepEditing': keepEditing,
        'discardTitle': discardTitle,
        'message': ?message,
        'dark': ?dark,
        'fields': fields.map((field) => field.toMap()).toList(),
      });
      return values;
    } finally {
      _validators.remove(id);
    }
  }

  static Future<Map<String, String>?> list({
    required String title,
    required String close,
    required String manage,
    required List<MMNativeListSection> sections,
    required String selectedSection,
    required bool dark,
    required String empty,
    Future<Uint8List?> Function(String)? preview,
  }) async {
    final id = '${++_sequence}';
    if (preview != null) _previews[id] = preview;
    try {
      return await _channel.invokeMapMethod<String, String>('list', {
        'modalStyle': MMModalStyle.nativeConfiguration,
        'id': id,
        'title': title,
        'close': close,
        'manage': manage,
        'selectedSection': selectedSection,
        'dark': dark,
        'empty': empty,
        'sections': sections.map((section) => section.toMap()).toList(),
      });
    } finally {
      _previews.remove(id);
    }
  }

  /// System medium/large action panel. Inline actions return refreshed content;
  /// navigation actions are returned only after UIKit has finished dismissing.
  static Future<String?> actions({
    required Map<String, Object?> content,
    required Future<Map<String, Object?>> Function(String) onAction,
  }) async {
    final id = '${++_sequence}';
    _actions[id] = onAction;
    try {
      return await _channel.invokeMethod<String>('actions', {
        'id': id,
        ...content,
        'modalStyle': MMModalStyle.nativeConfiguration,
      });
    } finally {
      _actions.remove(id);
    }
  }

  static Future<int?> pickColor({required int value, required bool dark}) =>
      _channel.invokeMethod<int>('color', {'value': value, 'dark': dark});

  static Future<String?> confirm({
    required String title,
    String? message,
    bool? dark,
    required String cancel,
    required List<MMNativeAction> actions,
  }) => _channel.invokeMethod<String>('confirm', {
    'modalStyle': MMModalStyle.nativeConfiguration,
    'title': title,
    'message': ?message,
    'dark': ?dark,
    'cancel': cancel,
    'actions': actions.map((action) => action.toMap()).toList(),
  });
}

class MMNativeField {
  const MMNativeField({
    required this.id,
    required this.label,
    this.value = '',
    this.placeholder,
    this.keyboard = 'text',
  });
  final String id;
  final String label;
  final String value;
  final String? placeholder;
  final String keyboard;

  Map<String, Object?> toMap() => {
    'id': id,
    'label': label,
    'value': value,
    'placeholder': ?placeholder,
    'keyboard': keyboard,
  };
}

class MMNativeAction {
  const MMNativeAction(this.id, this.label, {this.destructive = false});
  final String id;
  final String label;
  final bool destructive;
  Map<String, Object> toMap() => {'id': id, 'label': label, 'destructive': destructive};
}

class MMNativeListSection {
  const MMNativeListSection(this.id, this.title, this.rows, {this.empty});
  final String id, title;
  final String? empty;
  final List<MMNativeListRow> rows;
  Map<String, Object> toMap() => {
    'id': id,
    'title': title,
    'rows': rows.map((row) => row.toMap()).toList(),
    'empty': ?empty,
  };
}

class MMNativeListRow {
  const MMNativeListRow(
    this.id,
    this.title, {
    this.subtitle,
    this.depth = 0,
    this.selected = false,
    this.preview = false,
    this.enabled = true,
  });
  final String id, title;
  final String? subtitle;
  final int depth;
  final bool selected, preview, enabled;
  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'subtitle': ?subtitle,
    'depth': depth,
    'selected': selected,
    'preview': preview,
    'enabled': enabled,
  };
}
