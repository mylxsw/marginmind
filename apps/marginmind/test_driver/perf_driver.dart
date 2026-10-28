import 'package:integration_test/integration_test_driver.dart';

/// Writes each `watchPerformance` report of an integration test run by
/// `flutter drive` to `build/<reportKey>.timeline_summary.json`.
Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    if (data == null) return;
    for (final entry in data.entries) {
      await writeResponseData(entry.value as Map<String, dynamic>, testOutputFilename: entry.key);
    }
  },
);
