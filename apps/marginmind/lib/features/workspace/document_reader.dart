import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';

/// Composition ports for GUL-576. A book must never be passed to PDFium while
/// its Flutter reader is unavailable.
typedef DocumentReaderBuilder = Widget Function(
  BuildContext context,
  WidgetRef ref,
  String studySetId,
  Document document,
);
final documentReaderBuilderProvider = Provider<DocumentReaderBuilder?>((ref) => null);
typedef ReadingSettingsHandler = void Function(BuildContext context, WidgetRef ref, String studySetId);
final readingSettingsHandlerProvider = Provider<ReadingSettingsHandler?>((ref) => null);
