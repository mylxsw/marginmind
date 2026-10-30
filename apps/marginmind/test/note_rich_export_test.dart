import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/study_notes/note_docx.dart';
import 'package:marginmind/features/study_notes/note_export_sheet.dart';
import 'package:marginmind/features/study_notes/note_pdf.dart';
import 'package:marginmind/features/study_notes/note_share_card.dart';
import 'package:marginmind/features/study_notes/note_share_sheet.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import 'study_notes_ui_test.dart' show noteFixture;
import 'helpers.dart' show settleHud;

NoteRichDocument document({NoteCitationStyle citations = NoteCitationStyle.footnote}) {
  final c = noteFixture();
  return NoteRichDocument.resolve(c, c.studyNotes.single, options: NoteExportOptions(citations: citations));
}

Widget host(Widget child, {bool dark = false}) => MaterialApp(
  theme: dark ? MMTheme.dark() : MMTheme.light(),
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);
Future<void> sheet(WidgetTester tester, Widget child, {Size size = const Size(1000, 800)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    host(
      Builder(
        builder: (context) => MMButton(
          label: 'Open',
          onPressed: () => showMMSheet<void>(context: context, width: 900, builder: (_) => child),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    if (Platform.environment['WRITE_NOTE_EVIDENCE'] != '1') return;
    final bytes = ByteData.sublistView(File('/System/Library/Fonts/Supplemental/Arial Unicode.ttf').readAsBytesSync());
    for (final family in [
      '.AppleSystemUIFont',
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
      'Roboto',
      'PingFang SC',
    ]) {
      await (FontLoader(family)..addFont(Future.value(bytes))).load();
    }
    await (FontLoader('Songti SC')..addFont(
          Future.value(ByteData.sublistView(File('/System/Library/Fonts/Supplemental/Songti.ttc').readAsBytesSync())),
        ))
        .load();
    await (FontLoader(
      'packages/lucide_icons_flutter/Lucide',
    )..addFont(rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'))).load();
  });
  test('DOCX XML goldens and zip roundtrip contain native footnote relationship', () {
    for (final style in NoteCitationStyle.values) {
      final doc = document(citations: style);
      final parts = NoteDocx.parts(doc);
      for (final entry in parts.entries) {
        final path = 'test/goldens/note_docx_${style.name}_${entry.key.replaceAll('/', '_')}';
        final file = File(path);
        file.parent.createSync(recursive: true);
        if (Platform.environment['UPDATE_GOLDENS'] == '1') file.writeAsStringSync(entry.value);
        expect(entry.value, file.readAsStringSync());
      }
      final archive = ZipDecoder().decodeBytes(NoteDocx.encode(doc));
      expect(archive.files.length, parts.length);
      expect(utf8.decode(archive.findFile('word/document.xml')!.content), parts['word/document.xml']);
      expect(parts['word/document.xml'], contains('w:pStyle w:val="Quote"'));
      expect(parts['word/document.xml'], contains('w:shd'));
      expect(parts['word/document.xml']!.contains('w:footnoteReference'), style == NoteCitationStyle.footnote);
    }
  });
  test('DOCX XML escapes and strips invalid controls, preserves newlines', () {
    final xml = NoteDocx.parts(
      NoteRichDocument('<&"', [const NoteParagraph(NoteParagraphKind.quote, 'A\x00<&"\nB')], NoteCitationStyle.none),
    )['word/document.xml']!;
    expect(xml, contains('A&lt;&amp;&quot;'));
    expect(xml, contains('<w:br/>'));
    expect(xml, isNot(contains('\x00')));
  });
  testWidgets('A4 PDF paginates long quotes with color, header, footer and bottom footnotes', (tester) async {
    final doc = NoteRichDocument('Title', [
      const NoteParagraph(NoteParagraphKind.title, 'Title'),
      NoteParagraph(
        NoteParagraphKind.quote,
        List.filled(300, 'A long quote line with text.').join('\n'),
        citation: 'Book p.1',
        colorIndex: 5,
      ),
      const NoteParagraph(NoteParagraphKind.own, 'Private annotation'),
    ], NoteCitationStyle.footnote);
    final scene = NotePdf.scene(doc);
    expect(scene['width'], 595.28);
    expect(scene['height'], 841.89);
    final pages = scene['pages'] as List<List<Map<String, Object?>>>;
    expect(pages.length, greaterThan(3));
    for (final (i, page) in pages.indexed) {
      expect(page.where((c) => c['text'] == 'Title'), isNotEmpty);
      expect(page.where((c) => c['text'] == '${i + 1}' && c['y'] == NotePdf.height - 30), hasLength(1));
      for (final command in page.where((c) => c['type'] == 'text')) {
        expect(command['y'] as double, lessThan(NotePdf.height - 20));
      }
    }
    expect(pages.first.any((c) => c['text'] == '[1] Book p.1'), isTrue);
    expect(pages.first.any((c) => c['serif'] == true && c['fontSize'] == 11.0), isTrue);
    expect(pages.expand((p) => p).any((c) => c['color'] == 0xffaf52de), isTrue);
  });
  testWidgets('PDF keeps a section heading with its first content line', (tester) async {
    final doc = NoteRichDocument('Title', [
      for (var i = 0; i < 24; i++) const NoteParagraph(NoteParagraphKind.text, 'Body'),
      const NoteParagraph(NoteParagraphKind.heading, 'Section'),
      const NoteParagraph(NoteParagraphKind.quote, 'Final excerpt'),
    ], NoteCitationStyle.none);
    final pages = NotePdf.scene(doc)['pages'] as List<List<Map<String, Object?>>>;
    final headingPage = pages.indexWhere((p) => p.any((c) => c['text'] == 'Section'));
    final quotePage = pages.indexWhere((p) => p.any((c) => c['text'] == 'Final excerpt'));
    expect(headingPage, quotePage);
  });
  test('share scopes cap excerpts and omit notes for unselected quotes', () {
    final original = noteFixture().studyNotes.single;
    final n = original.copyWith(
      sections: [
        NoteSection(
          id: 's',
          title: 'S',
          blocks: [
            for (var i = 0; i < 6; i++) ...[
              QuoteBlock(id: 'q$i', annotationId: 'a$i'),
              OwnBlock(id: 'o$i', sourceId: 'm$i', source: OwnSource.marginNote),
            ],
            const TextBlock(id: 'summary', text: 'AI', kind: TextKind.summary),
          ],
        ),
      ],
    );
    for (final (scope, count) in [
      (NoteShareScope.quote, 1),
      (NoteShareScope.section, 4),
      (NoteShareScope.summary, 2),
    ]) {
      final selected = selectSharedNote(n, scope, 0, 3).sections.single.blocks;
      expect(selected.whereType<QuoteBlock>(), hasLength(count));
      expect(selected.whereType<OwnBlock>(), hasLength(count));
      if (scope == NoteShareScope.quote) {
        expect(selected.whereType<QuoteBlock>().single.annotationId, 'a3');
        expect(selected.whereType<OwnBlock>().single.sourceId, 'm3');
      }
    }
    expect(selectSharedNote(n.copyWith(sections: []), NoteShareScope.quote, 99, 0).sections, isEmpty);
  });
  for (final theme in MMShareCardTheme.values) {
    testWidgets('share ${theme.name} widget golden and 2x PNG', (tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        host(
          Center(
            child: RepaintBoundary(
              key: key,
              child: NoteShareCard(
                document: NoteRichDocument.resolve(
                  noteFixture(),
                  noteFixture().studyNotes.single,
                  options: const NoteExportOptions(context: false, questions: false, sources: false),
                ),
                theme: theme,
                scope: NoteShareScope.section,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (Platform.environment['WRITE_NOTE_EVIDENCE'] != '1') {
        await expectLater(find.byKey(key), matchesGoldenFile('goldens/note_share_${theme.name}.png'));
      }
      final png = await tester.runAsync(
        () => captureNoteCard(key.currentContext!.findRenderObject()! as RenderRepaintBoundary),
      );
      expect(png!.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      final header = ByteData.sublistView(png);
      expect(header.getUint32(16), 660);
      if (Platform.environment['WRITE_NOTE_EVIDENCE'] == '1') {
        await tester.runAsync(() async {
          final dir = Directory('../../docs/evidence/gul-592')..createSync(recursive: true);
          File('${dir.path}/share-${theme.name}.png').writeAsBytesSync(png);
          File('${dir.path}/note.docx').writeAsBytesSync(NoteDocx.encode(document()));
          File('${dir.path}/pdf-scene.json').writeAsStringSync(jsonEncode(NotePdf.scene(document())));
        });
      }
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('share settings and empty state work in narrow dark sheet', (tester) async {
    final c = noteFixture();
    await sheet(
      tester,
      NoteShareSheet(content: c, note: c.studyNotes.single),
      size: const Size(620, 800),
    );
    await tester.tap(find.byKey(const ValueKey('share-quote')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('share-night')));
    await tester.tap(find.byKey(const ValueKey('share-night')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('share-own')));
    await tester.pumpAndSettle();
    expect(find.text('My original note'), findsNothing);
    expect(tester.widget<NoteShareCard>(find.byType(NoteShareCard)).theme, MMShareCardTheme.night);
    expect(tester.takeException(), isNull);
  });
  testWidgets('oversized cards fail before allocating a raster image', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(host(RepaintBoundary(key: key, child: const SizedBox(width: 330, height: 9000))));
    await tester.pumpAndSettle();
    await expectLater(
      captureNoteCard(key.currentContext!.findRenderObject()! as RenderRepaintBoundary),
      throwsStateError,
    );
  });
  testWidgets('image export handles cancellation, failure and retry; copy uses PNG bytes', (tester) async {
    final c = noteFixture();
    var saves = 0, copies = 0;
    await sheet(
      tester,
      NoteShareSheet(
        content: c,
        note: c.studyNotes.single,
        capture: (_) async => Uint8List.fromList([137, 80, 78, 71]),
        save: (name, bytes) async {
          expect(name, 'note.png');
          saves++;
          if (saves == 1) return false;
          if (saves == 2) throw StateError('Full');
          return true;
        },
        copy: (bytes) async {
          copies++;
          expect(bytes, [137, 80, 78, 71]);
        },
      ),
    );
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('存储图片…'));
      await tester.pumpAndSettle();
      if (i == 1) expect(find.text('导出失败，请重试。'), findsOneWidget);
    }
    expect(saves, 3);
    await tester.tap(find.text('拷贝图片'));
    await tester.pumpAndSettle();
    expect(copies, 1);
    await settleHud(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  testWidgets('empty share and AI privacy switch never render hidden content', (tester) async {
    final c = noteFixture();
    final n = c.studyNotes.single.copyWith(
      sections: [
        NoteSection(
          id: 's',
          title: 'S',
          blocks: [
            ...c.studyNotes.single.sections.single.blocks,
            const TextBlock(id: 'ai', text: 'PRIVATE AI', kind: TextKind.summary),
          ],
        ),
      ],
    );
    await sheet(tester, NoteShareSheet(content: c, note: n));
    expect(find.text('AI · PRIVATE AI'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('share-ai')));
    await tester.pumpAndSettle();
    expect(find.text('AI · PRIVATE AI'), findsNothing);
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await sheet(
      tester,
      NoteShareSheet(
        content: c,
        note: n.copyWith(sections: []),
      ),
    );
    expect(find.text('没有摘录'), findsWidgets);
    expect(tester.widget<MMButton>(find.widgetWithText(MMButton, '分享…')).onPressed, isNull);
  });
  testWidgets('PDF export passes exact paginated preview to native encoder', (tester) async {
    const channel = MethodChannel('marginmind/map_export');
    Map? scene;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      scene = call.arguments as Map;
      return Uint8List.fromList([37, 80, 68, 70]);
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
    );
    final c = noteFixture();
    String? remembered;
    await sheet(
      tester,
      NoteExportSheet(
        content: c,
        note: c.studyNotes.single,
        initialTarget: 'pdf',
        rememberTarget: (target) async {
          remembered = target;
        },
        save: (name, bytes, assets) async {
          expect(name, endsWith('.pdf'));
          expect(bytes, [37, 80, 68, 70]);
          return true;
        },
      ),
    );
    await tester.tap(find.byKey(const ValueKey('citation-footnote')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('note-export-save')));
    await tester.pumpAndSettle();
    expect(scene!['pages'], isNotEmpty);
    expect(remembered, 'pdf');
    await settleHud(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  testWidgets('Word save and rich clipboard carry selected options; failure can retry', (tester) async {
    final c = noteFixture();
    final calls = <MethodCall>[];
    const channel = MethodChannel('marginmind/map_clipboard');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
    );
    String? savedName;
    await sheet(
      tester,
      NoteExportSheet(
        content: c,
        note: c.studyNotes.single,
        save: (name, bytes, assets) async {
          savedName = name;
          expect(assets, isEmpty);
          expect(ZipDecoder().decodeBytes(bytes).findFile('word/document.xml'), isNotNull);
          return false;
        },
      ),
    );
    await tester.tap(find.byKey(const ValueKey('export-docx')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('note-export-save')));
    await tester.pumpAndSettle();
    expect(savedName, endsWith('.docx'));
    await tester.tap(find.byKey(const ValueKey('export-rich')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('note-export-save')));
    await tester.pumpAndSettle();
    expect(calls.single.method, 'writeRichText');
    expect((calls.single.arguments as Map)['html'], contains('<blockquote'));
    expect((calls.single.arguments as Map)['text'], isNot(contains('<blockquote')));
    await settleHud(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
