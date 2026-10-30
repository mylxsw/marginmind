import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';

import 'widgets/reflow_reader.dart';
import 'widgets/reading_settings.dart';

/// Workspace composition ports for source readers and their settings.
typedef DocumentReaderBuilder = Widget Function(
  BuildContext context,
  WidgetRef ref,
  String studySetId,
  Document document,
);
final documentReaderBuilderProvider = Provider<DocumentReaderBuilder?>(
  (ref) =>
      (context, ref, setId, document) =>
          ReflowReader(key: ValueKey((document.id, document.revision)), studySetId: setId, document: document),
);
typedef ReadingSettingsHandler = void Function(BuildContext context, WidgetRef ref, String studySetId);
final readingSettingsHandlerProvider = Provider<ReadingSettingsHandler?>((ref) => showReadingSettings);
