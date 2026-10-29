// Production reader and real PDFium; only the model is an offline test double.
// flutter run -d macos -t example/translation_acceptance.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/assistant/assistant_settings.dart';
import 'package:marginmind/features/workspace/reader_compare.dart';
import 'package:marginmind/features/workspace/reader_translation.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:mm_platform/mm_platform.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AcceptanceTranslator implements ParagraphTranslator {
  @override
  Future<ParagraphTranslation> translate(
    TranslationParagraph p,
    String lang,
    CancellationToken cancel,
    int maxTokens,
  ) async {
    await cancel.bind(Future<void>.delayed(const Duration(seconds: 2)));
    const translations = {
      'Learning and Memory': '学习与记忆',
      'How learning happens': '学习如何发生',
      'Learning connects new ideas to prior knowledge.': '学习把新观点与已有知识联系起来。',
      'Explaining a concept reveals gaps in understanding.': '解释一个概念，可以发现理解中的空白。',
      'Active recall helps us discover what is missing.': '主动回忆帮助我们发现遗漏的知识。',
      'Try to describe the idea in your own words.': '试着用自己的话描述这个观点。',
      'Long-term memory and practice': '长期记忆与练习',
      'Spread practice over several days instead of one.': '将练习分散在几天内进行。',
      'Each attempt to recall strengthens the memory.': '每一次努力回想，都在加强记忆。',
      'Make highlights, excerpts, and notes as you read.': '阅读时可以划线、摘录，并记下想法。',
      'Retrieval practice': '检索练习',
      'Close the book and summarize the main ideas.': '合上书本，概括主要观点。',
      'Return to the text to check what you could not recall.': '想不起来的地方，回到原文核对。',
      'Compare the original with a translation to clarify terms.': '对照原文与译文，澄清概念。',
      'Transfer and application': '迁移与应用',
      'Apply knowledge to a situation you have not seen before.': '把知识应用于未曾遇到的新情境。',
      'Find an example and a counterexample for a claim.': '为一个观点寻找例子和反例。',
      'Organize the relationships between ideas in a mind map.': '在脑图中整理观点之间的联系。',
      'Spaced repetition': '间隔重复',
      'Schedule the next review so memory grows over time.': '安排下一次回顾，让记忆在时间中巩固。',
      'Allow the learning plan to change with feedback.': '根据反馈调整学习计划。',
      'Reflection': '反思',
      'Which ideas have changed your understanding?': '哪些观点改变了你的理解？',
      'Which questions deserve further study?': '哪些问题值得继续研究？',
      'Write those questions in the margin and return later.': '把问题记在页边，稍后再回来。',
    };
    return ParagraphTranslation(translations[p.text] ?? p.text, tokens: 30);
  }

  @override
  void close() {}
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DesktopWindow.initialize(
    title: 'MarginMind · Translation acceptance',
    minimumSize: const Size(1100, 800),
    initialSize: const Size(1600, 1000),
  );
  await MMPdfEngine.initialize();
  final data = await rootBundle.load('assets/sample/compare-source.pdf');
  final file = File('${Directory.systemTemp.path}/marginmind-translation-source.pdf');
  await file.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
  final now = DateTime.now();
  const id = 'translation-acceptance';
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({'settings.language': 'zh'});
  final prefs = await SharedPreferences.getInstance();
  const model = AssistantModel(
    provider: AssistantProvider.ollama,
    model: 'acceptance',
    endpoint: 'http://localhost:11434',
    localEnabled: true,
  );
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      assistantDefaultModelProvider.overrideWithValue(model),
      assistantCredentialStateProvider.overrideWith((ref) async => AssistantCredentialState.ready),
      paragraphTranslatorProvider.overrideWithValue((_) async => AcceptanceTranslator()),
      studySetRepositoryProvider.overrideWithValue(
        InMemoryStudySetRepository(
          sets: [
            StudySet(id: id, title: '阅读增强 · 逐段对照', colorIndex: 0, createdAt: now, lastOpenedAt: now, documentCount: 1),
          ],
        ),
      ),
      contentRepositoryProvider.overrideWithValue(
        InMemoryStudySetContentRepository({
          id: StudySetContent.empty.copyWith(
            documents: [
              Document(
                id: 'english',
                title: 'Learning and memory.pdf',
                fileName: file.path,
                pageCount: 3,
                importedAt: now,
              ),
            ],
          ),
        }),
      ),
    ],
  );
  container.read(navigationProvider.notifier).openStudySet(id);
  runApp(UncontrolledProviderScope(container: container, child: const MarginMindApp()));
  await container.read(contentProvider(id).future);
  container.read(workspaceProvider(id).notifier).openDocument('english');
  container.read(workspaceProvider(id).notifier).setLayout(MMSplitMode.primary);
  await container.read(readerCompareProvider(id).notifier).openAi('zh', readerWidth: 1600);
  container.listen(readerTranslationProvider(id), (previous, next) {
    if (next.complete) debugPrint('NATIVE_TRANSLATION_SAVED paragraphs=${next.done} pid=$pid');
    if (next.failed) debugPrint('NATIVE_TRANSLATION_FAILED paragraphs=${next.done}');
  });
  debugPrint('NATIVE_TRANSLATION_ENTERED pid=$pid');
}
