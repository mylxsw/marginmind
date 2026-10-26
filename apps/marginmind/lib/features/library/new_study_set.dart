import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/l10n.dart';
import '../../shared/pdf_picker.dart';
import '../workspace/widgets/notices.dart';
import 'library_controller.dart';

/// ⌘N: pick PDFs first, then the study set is created straight away, named
/// after the first document (rename it later) and opened. Cancelling the
/// panel creates nothing.
Future<void> newStudySetFromPdfs(BuildContext context, WidgetRef ref) async {
  final files = await ref.read(pdfPickerProvider)(context.l10n.pdfFiles);
  if (files.isEmpty || !context.mounted) return;
  final notice = await ref.read(libraryViewProvider.notifier).createFromFiles(files);
  if (context.mounted) showNotice(context, notice, rootTitle: '');
}
