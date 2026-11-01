import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/assistant/assistant_settings.dart';
import 'package:marginmind/features/workspace/reader_translation.dart';
import 'package:marginmind/features/workspace/widgets/annotation_color_button.dart';
import 'package:marginmind/features/workspace/widgets/reader_annotation_tools.dart';
import 'package:marginmind/features/workspace/widgets/selection_toolbar.dart';
import 'package:marginmind/features/workspace/widgets/selection_translation.dart';
import 'package:marginmind/features/workspace/widgets/vocabulary_add_button.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/settings/app_settings.dart';
import 'package:marginmind/settings/settings_window.dart';
import 'package:marginmind/shared/assistant_icon.dart';
import 'package:marginmind/shared/l10n.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';

import 'assistant_quick_actions_test.dart' show screenshot;
import 'helpers.dart';
import 'reader_translation_test.dart' show model;
import 'selection_toolbar_test.dart' show selection;

class SelectionTestTranslator implements ParagraphTranslator {
  final pending = Completer<ParagraphTranslation>();
  String? language, source, sourceCode;
  CancellationToken? cancel;
  bool closed = false;
  @override
  Future<ParagraphTranslation> translate(
    TranslationParagraph p,
    String lang,
    CancellationToken token,
    int maxTokens, {
    String? sourceLanguage,
  }) {
    language = lang;
    source = p.text;
    sourceCode = sourceLanguage;
    cancel = token;
    return pending.future;
  }

  @override
  void close() => closed = true;
}

void main() {
  setUpAll(() async {
    if (Platform.environment['MM_SCREENSHOTS'] == null) return;
    final data = ByteData.sublistView(
      File(Platform.environment['MM_FONT'] ?? '/System/Library/Fonts/Supplemental/Arial Unicode.ttf').readAsBytesSync(),
    );
    for (final family in [
      '.AppleSystemUIFont',
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
      'Roboto',
      'PingFang SC',
      'Songti SC',
    ]) {
      await (FontLoader(family)..addFont(Future.value(data))).load();
    }
    final pub = Platform.environment['PUB_CACHE'] ?? '${Platform.environment['HOME']}/.pub-cache';
    final iconDir = Directory('$pub/hosted/pub.dev')
        .listSync()
        .whereType<Directory>()
        .lastWhere((d) => d.path.contains('cupertino_icons-'));
    await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
          Future.value(ByteData.sublistView(File('${iconDir.path}/assets/CupertinoIcons.ttf').readAsBytesSync())),
        ))
        .load();
    await (FontLoader(
      'packages/lucide_icons_flutter/Lucide',
    )..addFont(rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'))).load();
  });
  for (final dark in [false, true]) {
    testWidgets('palette, translation and preserved selection in ${dark ? 'dark' : 'light'}', (tester) async {
      final translator = SelectionTestTranslator();
      final container = await pumpApp(
        tester,
        prefs: {'settings.appearance': dark ? 'dark' : 'light', 'settings.language': 'zh'},
        overrides: [
          assistantDefaultModelProvider.overrideWithValue(model),
          paragraphTranslatorProvider.overrideWithValue((_) async => translator),
        ],
      );
      container.read(navigationProvider.notifier).openStudySet('demo-1');
      await tester.pumpAndSettle();
      final controller = container.read(workspaceProvider('demo-1').notifier);
      await screenshot(tester, 'reader-brush-${dark ? 'dark' : 'light'}', target: find.byType(ReaderAnnotationTools));
      await controller.onSelectionCommitted('c1', selection);
      await tester.pumpAndSettle();
      final toolbar = find.byType(SelectionToolbar);
      final icons = tester
          .widgetList<MMToolbarButton>(find.descendant(of: toolbar, matching: find.byType(MMToolbarButton)))
          .map((b) => b.icon)
          .toList();
      expect(icons, [
        MMIcons.highlight,
        MMIcons.underline,
        MMIcons.copy,
        MMIcons.quoteBubble,
        MMIcons.network,
        MMIcons.translate,
        // The assistant button draws the app's AssistantIcon instead of a glyph.
        null,
      ]);
      expect(
        find.descendant(of: find.byKey(const ValueKey('selection-assistant')), matching: find.byType(AssistantIcon)),
        findsOneWidget,
      );
      await screenshot(tester, 'selection-toolbar-${dark ? 'dark' : 'light'}', target: toolbar);
      await tester.tap(find.descendant(of: toolbar, matching: find.byType(AnnotationColorButton)));
      await tester.pumpAndSettle();
      final palette = find.byKey(const ValueKey('annotation-color-palette'));
      expect(palette, findsOneWidget);
      expect(find.byType(MMFloatingToolbar), findsNWidgets(2));
      expect(tester.getRect(palette).top, greaterThan(tester.getRect(toolbar).bottom));
      await screenshot(tester, 'selection-palette-${dark ? 'dark' : 'light'}', target: palette);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(container.read(workspaceProvider('demo-1')).pending, isA<PendingSelection>());
      await tester.tap(find.byKey(const ValueKey('selection-translate')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(SelectionTranslation), findsOneWidget);
      expect(translator.language, 'zh');
      expect(translator.source, selection.text);
      translator.pending.complete(const ParagraphTranslation('选中的一段文字'));
      await tester.pumpAndSettle();
      expect(find.text('选中的一段文字'), findsOneWidget);
      final popup = find.byKey(const ValueKey('selection-translation-result'));
      final copy = find.byKey(const ValueKey('selection-translation-copy'));
      final header = find.byKey(const ValueKey('selection-translation-header'));
      final scroll = find.byKey(const ValueKey('selection-translation-scroll'));
      expect(find.descendant(of: header, matching: find.byIcon(MMIcons.copy)), findsNothing);
      expect(find.text('复制译文'), findsOneWidget);
      expect(tester.getRect(copy).top, greaterThan(tester.getRect(scroll).bottom));
      expect(tester.getRect(copy).left, closeTo(tester.getRect(popup).left + 14, .1));
      await screenshot(tester, 'selection-translation-${dark ? 'dark' : 'light'}', target: popup);
      String? copied;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
          return null;
        },
      );
      await tester.tap(find.byTooltip('复制译文'));
      await tester.pump();
      expect(copied, '选中的一段文字');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(container.read(workspaceProvider('demo-1')).pending, isA<PendingSelection>());
      expect(translator.closed, isTrue);
      await settleHud(tester);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });
  }

  testWidgets('closing in flight cancels and closes the translation request', (tester) async {
    final translator = SelectionTestTranslator();
    final container = await pumpApp(
      tester,
      overrides: [
        assistantDefaultModelProvider.overrideWithValue(model),
        paragraphTranslatorProvider.overrideWithValue((_) async => translator),
      ],
    );
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    await container.read(workspaceProvider('demo-1').notifier).onSelectionCommitted('c1', selection);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('selection-translate')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(translator.cancel, isNotNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(translator.cancel!.isCancelled, isTrue);
    expect(translator.closed, isTrue);
    translator.pending.complete(const ParagraphTranslation('late response'));
    await tester.pumpAndSettle();
    expect(find.text('late response'), findsNothing);
  });

  testWidgets('fixed direction is used and a failed request can retry', (tester) async {
    final translators = [SelectionTestTranslator(), SelectionTestTranslator()];
    var calls = 0;
    final container = await pumpApp(
      tester,
      prefs: {'settings.selectionTranslationDirection': 'chineseToEnglish'},
      overrides: [
        assistantDefaultModelProvider.overrideWithValue(model),
        paragraphTranslatorProvider.overrideWithValue((_) async => translators[calls++]),
      ],
    );
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    await container.read(workspaceProvider('demo-1').notifier).onSelectionCommitted('c1', selection);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('selection-translate')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(translators.first.language, 'en');
    translators.first.pending.completeError(StateError('fixture failure'));
    await tester.pumpAndSettle();
    expect(find.text('Translation failed. Check your model settings or connection and retry.'), findsOneWidget);
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-close')));
    await tester.pump();
    translators.last.pending.complete(const ParagraphTranslation('Complete translation'));
    await tester.pumpAndSettle();
    expect(find.text('Complete translation'), findsOneWidget);
  });

  testWidgets('unconfigured model offers setup and settings persist direction', (tester) async {
    final container = await pumpApp(tester, overrides: [assistantDefaultModelProvider.overrideWithValue(null)]);
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    await container.read(workspaceProvider('demo-1').notifier).onSelectionCommitted('c1', selection);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('selection-translate')));
    await tester.pumpAndSettle();
    expect(find.text('No model configured'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(SelectionToolbar));
    unawaited(showSettings(context, tab: SettingsTab.reading));
    await tester.pumpAndSettle();
    await screenshot(tester, 'selection-translation-settings', target: find.byKey(const ValueKey('settings-window')));
    await tester.tap(find.byKey(const ValueKey('settings-selection-translation')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chinese → English').last);
    await tester.pumpAndSettle();
    expect(
      container.read(settingsProvider).selectionTranslationDirection,
      SelectionTranslationDirection.chineseToEnglish,
    );
  });

  testWidgets('offline cloud translation makes no request', (tester) async {
    var calls = 0;
    final container = await pumpApp(
      tester,
      prefs: {'assistant.online.demo-1': false},
      overrides: [
        assistantDefaultModelProvider.overrideWithValue(
          const AssistantModel(
            provider: AssistantProvider.compatible,
            model: 'fixture',
            endpoint: 'https://example.invalid/v1',
          ),
        ),
        paragraphTranslatorProvider.overrideWithValue((_) async {
          calls++;
          return SelectionTestTranslator();
        }),
      ],
    );
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    await container.read(workspaceProvider('demo-1').notifier).onSelectionCommitted('c1', selection);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('selection-translate')));
    await tester.pumpAndSettle();
    expect(find.text('Online access is off'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('an existing Chinese highlight translates its quote without editing the document', (tester) async {
    final translator = SelectionTestTranslator();
    translator.pending.complete(const ParagraphTranslation('This is the forgetting curve.'));
    final container = await pumpApp(
      tester,
      overrides: [
        assistantDefaultModelProvider.overrideWithValue(model),
        paragraphTranslatorProvider.overrideWithValue((_) async => translator),
      ],
    );
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final controller = container.read(workspaceProvider('demo-1').notifier);
    final before = controller.content;
    final annotation = before.annotations.last;
    controller.tapHighlight(annotation.id, selection.viewportRect!);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('selection-translate')));
    await tester.pumpAndSettle();
    expect(translator.language, 'en');
    expect(translator.source, annotation.quote);
    expect(find.text('This is the forgetting curve.'), findsOneWidget);
    expect(controller.content, same(before));
  });

  testWidgets('inline language changes cancel older requests and discard late results', (tester) async {
    final translators = List.generate(4, (_) => SelectionTestTranslator());
    var calls = 0;
    final container = await pumpApp(
      tester,
      overrides: [
        assistantDefaultModelProvider.overrideWithValue(model),
        paragraphTranslatorProvider.overrideWithValue((_) async => translators[calls++]),
      ],
    );
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    await container.read(workspaceProvider('demo-1').notifier).onSelectionCommitted('c1', selection);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('selection-translate')));
    await tester.pump(const Duration(milliseconds: 200));

    Future<void> pick(String key, String language) async {
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text(language).last);
      await tester.pump(const Duration(milliseconds: 200));
    }

    await pick('translation-target-language', 'Japanese');
    expect(translators[0].cancel!.isCancelled, isTrue);
    expect(translators[1].language, 'ja');
    await pick('translation-source-language', 'English');
    expect(translators[1].cancel!.isCancelled, isTrue);
    expect(translators[2].sourceCode, 'en');
    await pick('translation-target-language', 'French');
    expect(translators[2].cancel!.isCancelled, isTrue);
    expect(translators[3].language, 'fr');
    expect(translators[3].sourceCode, 'en');
    translators[0].pending.complete(const ParagraphTranslation('old Chinese'));
    translators[1].pending.complete(const ParagraphTranslation('old Japanese'));
    translators[2].pending.completeError(StateError('old request failure'));
    translators[3].pending.complete(const ParagraphTranslation('Texte français'));
    await tester.pumpAndSettle();
    expect(find.text('Texte français'), findsOneWidget);
    expect(find.text('old Chinese'), findsNothing);
    expect(find.text('old Japanese'), findsNothing);
    expect(find.text('Translation failed. Check your model settings or connection and retry.'), findsNothing);
    expect(translators.every((t) => t.closed), isTrue);
    expect(container.read(settingsProvider).selectionTranslationDirection, SelectionTranslationDirection.automatic);
  });

  for (final appearance in ['light', 'dark']) {
    testWidgets('swap uses the previous translation as source in $appearance', (tester) async {
      final translators = [SelectionTestTranslator(), SelectionTestTranslator()];
      var calls = 0;
      final container = await pumpApp(
        tester,
        prefs: {
          'settings.appearance': appearance,
          'settings.language': 'zh',
          'settings.selectionTranslationDirection': 'chineseToEnglish',
        },
        overrides: [
          assistantDefaultModelProvider.overrideWithValue(model),
          paragraphTranslatorProvider.overrideWithValue((_) async => translators[calls++]),
        ],
      );
      container.read(navigationProvider.notifier).openStudySet('demo-1');
      await tester.pumpAndSettle();
      final controller = container.read(workspaceProvider('demo-1').notifier);
      final before = controller.content;
      final annotation = before.annotations.last;
      controller.tapHighlight(annotation.id, selection.viewportRect!);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('selection-translate')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(translators[0].sourceCode, 'zh');
      translators[0].pending.complete(const ParagraphTranslation('This curve is called the forgetting curve.'));
      await tester.pumpAndSettle();
      final popup = find.byKey(const ValueKey('selection-translation-result'));
      await screenshot(tester, 'language-controls-$appearance', target: popup);
      await tester.tap(find.byKey(const ValueKey('translation-swap-languages')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(translators[1].source, 'This curve is called the forgetting curve.');
      expect(translators[1].sourceCode, 'en');
      expect(translators[1].language, 'zh');
      translators[1].pending.complete(const ParagraphTranslation('这条曲线被称为遗忘曲线。'));
      await tester.pumpAndSettle();
      expect(find.text('这条曲线被称为遗忘曲线。'), findsOneWidget);
      expect(controller.content, same(before));
      await screenshot(tester, 'swapped-languages-$appearance', target: popup);
      await tester.tap(find.byKey(const ValueKey('translation-target-language')));
      await tester.pumpAndSettle();
      final l = tester.element(find.byType(SelectionTranslation)).l10n;
      expect(find.text(l.translationJapanese), findsOneWidget);
      expect(find.text(l.translationFrench), findsOneWidget);
      await screenshot(
        tester,
        'language-menu-$appearance',
        target: find.ancestor(of: find.text(l.translationJapanese), matching: find.byType(MMGlass)).first,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  }

  testWidgets('same explicit languages show a correction prompt without a model call', (tester) async {
    final translator = SelectionTestTranslator();
    var calls = 0;
    final container = await pumpApp(
      tester,
      prefs: {'settings.selectionTranslationDirection': 'englishToChinese'},
      overrides: [
        assistantDefaultModelProvider.overrideWithValue(model),
        paragraphTranslatorProvider.overrideWithValue((_) async {
          calls++;
          return translator;
        }),
      ],
    );
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    await container.read(workspaceProvider('demo-1').notifier).onSelectionCommitted('c1', selection);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('selection-translate')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byKey(const ValueKey('translation-target-language')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();
    expect(find.text('Choose different source and target languages.'), findsOneWidget);
    expect(calls, 1);
    expect(translator.cancel!.isCancelled, isTrue);
    translator.pending.complete(const ParagraphTranslation('late'));
    await tester.pumpAndSettle();
    expect(find.text('late'), findsNothing);
  });

  testWidgets('a superseded credential lookup closes its connection without starting a stale translation', (
    tester,
  ) async {
    final factory = Completer<ParagraphTranslator>();
    final stale = SelectionTestTranslator(), current = SelectionTestTranslator();
    var calls = 0;
    final container = await pumpApp(
      tester,
      size: const Size(800, 600),
      overrides: [
        assistantDefaultModelProvider.overrideWithValue(model),
        paragraphTranslatorProvider.overrideWithValue((_) => calls++ == 0 ? factory.future : Future.value(current)),
      ],
    );
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    await container.read(workspaceProvider('demo-1').notifier).onSelectionCommitted('c1', selection);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('selection-translate')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byKey(const ValueKey('translation-target-language')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Traditional Chinese').last);
    await tester.pump(const Duration(milliseconds: 200));
    expect(current.language, 'zh-Hant');
    current.pending.complete(const ParagraphTranslation('選中的一段文字'));
    await tester.pumpAndSettle();
    factory.complete(stale);
    await tester.pumpAndSettle();
    expect(stale.closed, isTrue);
    expect(stale.source, isNull);
    expect(find.text('選中的一段文字'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'Language controls fit a narrow reader');
  });

  for (final scenario in ['dark', 'light', 'narrow-long']) {
    testWidgets('copy footer matches approved layout and stays reachable in $scenario', (tester) async {
      const source =
          '对 Scrum 的需求由社会、经济和政治的快速变化驱动，而变化又是由技术进步的巨大速度所驱动的。'
          '你肯定听说过英特尔公司创始人戈登·摩尔提出的摩尔定律……';
      const translation =
          'The demand for Scrum is driven by rapid social, economic, and political change, '
          'which in turn is driven by the enormous speed of technological progress. '
          'You have surely heard of Moore’s Law, first formulated by Intel co-founder Gordon Moore in 1965. '
          'His paper predicted that the number of transistors on a chip would double every year, '
          'while the price of the added computing power would be correspondingly halved.';
      final long = scenario == 'narrow-long';
      final answer = long ? List.filled(40, translation).join('\n\n') : translation;
      final translator = SelectionTestTranslator();
      final container = await pumpApp(
        tester,
        size: long ? const Size(800, 600) : const Size(1280, 820),
        prefs: {
          'settings.language': 'zh',
          'settings.appearance': scenario == 'light' ? 'light' : 'dark',
          'settings.selectionTranslationDirection': 'chineseToEnglish',
        },
        overrides: [
          assistantDefaultModelProvider.overrideWithValue(model),
          paragraphTranslatorProvider.overrideWithValue((_) async => translator),
        ],
      );
      container.read(navigationProvider.notifier).openStudySet('demo-1');
      await tester.pumpAndSettle();
      await container
          .read(workspaceProvider('demo-1').notifier)
          .onSelectionCommitted(
            'c1',
            MMPdfSelection(
              page: selection.page,
              rects: selection.rects,
              text: source,
              viewportRect: selection.viewportRect,
            ),
          );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('selection-translate')));
      await tester.pump(const Duration(milliseconds: 200));
      final copy = find.byKey(const ValueKey('selection-translation-copy'));
      expect(copy, findsNothing, reason: 'There is no empty action row while translating');
      translator.pending.complete(ParagraphTranslation(answer));
      await tester.pumpAndSettle();
      final popup = find.byKey(const ValueKey('selection-translation-result'));
      final scroll = find.byKey(const ValueKey('selection-translation-scroll'));
      final copyBounds = tester.getRect(copy);
      final favoriteBounds = tester.getRect(find.byType(VocabularyAddButton));
      expect(copyBounds.top, greaterThan(tester.getRect(scroll).bottom));
      expect(copyBounds.center.dy, closeTo(favoriteBounds.center.dy, .1));
      expect(favoriteBounds.bottom, closeTo(tester.getRect(popup).bottom - 14, .1));
      expect(copyBounds.left, closeTo(tester.getRect(popup).left + 14, .1));
      if (long) {
        final position = tester
            .state<ScrollableState>(find.descendant(of: scroll, matching: find.byType(Scrollable)).first)
            .position;
        expect(position.maxScrollExtent, greaterThan(1000));
        await tester.drag(scroll, const Offset(0, -300));
        await tester.pumpAndSettle();
        expect(position.pixels, greaterThan(0));
        expect(tester.getRect(copy), copyBounds, reason: 'Scrolling never hides the copy action');
      }
      expect(tester.takeException(), isNull);
      await screenshot(tester, 'copy-footer-$scenario', target: popup);
      String? copied;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
          return null;
        },
      );
      await tester.tap(copy);
      await tester.pump();
      expect(copied, answer, reason: 'Copy includes the full answer, including text outside the viewport');
      await settleHud(tester);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  }
}
