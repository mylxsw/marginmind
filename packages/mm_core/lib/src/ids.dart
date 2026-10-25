import 'dart:math';

final _random = Random.secure();

/// Random 16-byte hex id. Time-ordered ids (UUID v7) can replace this when
/// sync arrives; nothing depends on the format.
String newId() => List.generate(16, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
