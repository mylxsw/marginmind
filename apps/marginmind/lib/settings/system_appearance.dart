import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_platform/mm_platform.dart';

import '../app/providers.dart';

/// Live system accent color and accessibility options (macOS).
class SystemAppearanceController extends Notifier<SystemAppearance> {
  @override
  SystemAppearance build() {
    final source = ref.watch(systemAppearanceSourceProvider);
    final sub = source.changes.listen((value) => state = value);
    ref.onDispose(sub.cancel);
    unawaited(
      source.read().then((value) {
        if (ref.mounted) state = value;
      }),
    );
    return const SystemAppearance();
  }
}

final systemAppearanceProvider = NotifierProvider<SystemAppearanceController, SystemAppearance>(
  SystemAppearanceController.new,
);
