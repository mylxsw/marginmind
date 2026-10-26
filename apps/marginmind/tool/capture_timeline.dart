// Attach to `flutter run --vmservice-out-file=...` and retain its timeline.
import 'dart:convert';
import 'dart:io';

import 'package:vm_service/vm_service_io.dart';

Future<void> main(List<String> args) async {
  final info = File(args[0]);
  for (var i = 0; i < 180 && !info.existsSync(); i++) {
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  final uri = Uri.parse(info.readAsStringSync().trim());
  final address = uri.scheme == 'ws' ? uri : uri.replace(scheme: 'ws', path: '${uri.path}ws');
  final service = await vmServiceConnectUri(address.toString());
  await service.setVMTimelineFlags(['Dart', 'Embedder', 'GC']);
  try {
    while (true) {
      final timeline = await service.getVMTimeline();
      File(args[1]).writeAsStringSync(jsonEncode(timeline.toJson()));
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  } catch (_) {
    // The workload closes its process after emitting its report.
  } finally {
    await service.dispose();
  }
}
