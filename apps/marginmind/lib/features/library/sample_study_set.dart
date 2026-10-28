import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_pdf/mm_pdf.dart';

import '../../app/providers.dart';
import '../../shared/temporary_document.dart';
import '../../shared/l10n.dart';

/// Bundled sample (original text, see assets/sample/README.md).
const sampleAsset = 'assets/sample/sample.pdf';

/// Creates the sample study set: the bundled chapter plus three empty
/// topics to excerpt into. Returns the new study set id.
Future<String> createSampleStudySet(WidgetRef ref, AppLocalizations l) async {
  final bytes = await rootBundle.load(sampleAsset);
  final path = await temporaryDocument(bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
  try {
    final set = await ref.read(studySetRepositoryProvider).create(NewStudySet(title: l.sampleSetTitle, colorIndex: 2));
    final repo = ref.read(contentRepositoryProvider);
    final editor = ref.read(editorProvider);
    final stored = await repo.importFile(set.id, path);
    final info = await MMPdfEngine.inspect(path);
    await repo.update(set.id, (c) {
      var next = editor.addDocument(c, title: l.sampleDocTitle, fileName: stored, pageCount: info.pageCount).$1;
      for (final topic in [l.sampleTopic1, l.sampleTopic2, l.sampleTopic3]) {
        next = editor.addTopic(next, title: topic).$1;
      }
      return next;
    });
    return set.id;
  } finally {
    releaseTemporaryDocument(path);
  }
}
