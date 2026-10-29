import 'package:flutter/material.dart';

import 'dart:async' show Completer;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/document_commands.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/workspace/widgets/reader_sidebar.dart';
import 'package:marginmind/features/workspace/web_conversion.dart';
import 'package:marginmind/features/workspace/web_document.dart';
import 'package:marginmind/features/workspace/workspace_browser.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/features/workspace/widgets/browser_pane.dart';
import 'package:marginmind/features/workspace/widgets/web_source.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import 'helpers.dart';

BrowserDocumentCapture page() => BrowserDocumentCapture(
  url: Uri.parse('https://example.com/article'),
  title: 'Article',
  capturedAt: DateTime.utc(2026, 10, 29),
  html: '<h1>Heading</h1><p><strong>body</strong> text</p>',
  snapshot: '<p>snapshot</p>',
  resources: {},
);

void main() {
  Future<void> ready(BrowserSession session) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      MethodChannel('marginmind/browser/${session.id}'),
      (_) async => null,
    );
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      'marginmind/browser/${session.id}',
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('event', {'kind': 'loaded', 'navigationId': 1, 'url': session.url.toString()}),
      ),
      (_) {},
    );
    await session.stop();
  }

  for (final size in [const Size(900, 700), const Size(390, 780)]) {
    testWidgets('conversion sheet previews formats, saves edited title and cancels at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final converter = WebDocumentConverter(
        inspectPdf: (_) async => (pageCount: 1, pages: <TranslationPage>[], preview: null),
      );
      final requested = <WebCaptureMode>[];
      PreparedWebDocument? saved;
      await tester.pumpWidget(
        MaterialApp(
          theme: MMTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: Builder(
              builder: (context) => MMButton(
                label: 'Convert',
                onPressed: () async {
                  saved = await showMMSheet<PreparedWebDocument>(
                    context: context,
                    width: MMSizes.webConversionSheetWidth,
                    builder: (_) => WebConversionSheet(
                      prepare: (mode) async {
                        requested.add(mode);
                        if (mode == WebCaptureMode.original) throw StateError('print failed');
                        return converter.prepare(page(), id: 'web', title: 'Article', mode: mode);
                      },
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Convert'));
      await tester.pumpAndSettle();
      expect(find.text('Convert to Document'), findsOneWidget);
      expect(requested, [WebCaptureMode.readable]);
      final title = find.byType(TextField);
      expect(tester.widget<TextField>(title).controller!.text, 'Article');
      await tester.enterText(title, '');
      await tester.pump();
      expect(tester.widget<MMButton>(find.widgetWithText(MMButton, 'Save')).onPressed, isNull);
      await tester.enterText(title, 'Edited');
      await tester.tap(find.text('PDF'));
      await tester.pumpAndSettle();
      expect(find.text('Couldn’t Save'), findsOneWidget);
      await tester.tap(find.text('Try Again'));
      await tester.pumpAndSettle();
      expect(requested.where((m) => m == WebCaptureMode.original).length, 2);
      await tester.tap(find.text('Markdown'));
      await tester.pumpAndSettle();
      expect(find.textContaining('# Heading'), findsOneWidget);
      await tester.tap(find.widgetWithText(MMButton, 'Save'));
      await tester.pumpAndSettle();
      expect(saved!.package.document.title, 'Edited');
      expect(saved!.package.document.origin!.mode, WebCaptureMode.markdown);
      await tester.tap(find.text('Convert'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets('workspace conversion commits, opens document, recaptures and retains a failed browser', (tester) async {
    var fail = false, count = 0;
    String? openedUrl;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('marginmind/external_link'),
      (call) async {
        openedUrl = (call.arguments as Map)['url'] as String;
        return true;
      },
    );
    final container = await pumpApp(
      tester,
      overrides: [
        canAddWebPageProvider.overrideWithValue(true),
        webCaptureProvider.overrideWithValue((session, generation, mode, cancelled) async {
          if (fail) throw StateError('capture failed');
          count++;
          return BrowserDocumentCapture(
            url: session.url,
            title: 'Article',
            capturedAt: DateTime.utc(2026, 10, 29, 0, 0, count),
            html: count == 1 ? '<p>before target after</p>' : '<p>new before target after</p>',
            snapshot: '<p>snapshot $count</p>',
            resources: {},
          );
        }),
      ],
    );
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final owner = container.read(workspaceBrowserProvider('demo-1').notifier);
    owner.open(Uri.parse('https://example.com/article'));
    await tester.pump();
    var session = container.read(workspaceBrowserProvider('demo-1')).session!;
    await ready(session);
    var context = tester.element(find.byType(BrowserPane));
    final first = container.read(browserConverterProvider)!(context, 'demo-1', session);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MMButton, 'Save'));
    await tester.pumpAndSettle();
    await first;
    final controller = container.read(workspaceProvider('demo-1').notifier);
    final document = controller.content.documents.last;
    expect(document.origin!.url, 'https://example.com/article');
    expect(controller.state.activeDocumentId, document.id);
    expect(container.read(workspaceBrowserProvider('demo-1')).session, isNull);
    expect(find.byType(WebSourceAttribution), findsNothing);
    await tester.tap(find.byKey(const ValueKey('reader-documents')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open Original Page'));
    await tester.pumpAndSettle();
    expect(openedUrl, document.origin!.url);
    await container
        .read(contentRepositoryProvider)
        .update(
          'demo-1',
          (content) => content.copyWith(
            annotations: [
              ...content.annotations,
              Annotation(
                id: 'missing',
                documentId: document.id,
                textAnchors: [TextAnchor('main', 0, 7, 'removed', revision: document.revision!)],
                quote: 'removed',
                colorIndex: 0,
                createdAt: DateTime.utc(2026),
              ),
            ],
          ),
        );
    await tester.tap(find.byKey(const ValueKey('reader-documents')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Needs Review'), findsNothing);
    await tester.tap(find.text('Refetch Page'));
    await tester.pump();
    expect(container.read(workspaceBrowserProvider('demo-1')).replacingDocumentId, document.id);
    await tester.pump();
    session = container.read(workspaceBrowserProvider('demo-1')).session!;
    await ready(session);
    context = tester.element(find.byType(BrowserPane));
    final update = container.read(browserConverterProvider)!(context, 'demo-1', session);
    await tester.pumpAndSettle();
    await update;
    expect(find.text('Convert to Document'), findsNothing);
    final updated = controller.content.document(document.id)!;
    expect(updated.revision, isNot(document.revision));
    expect(controller.content.documents.where((d) => d.origin != null).length, 1);
    expect(find.text('1 highlight needs review'), findsOneWidget);
    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    expect(controller.state.readerPanelMode, ReaderPanelMode.annotations);
    expect(find.byType(ReaderSidebar), findsOneWidget);
    expect(find.text('Needs Review (1)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('annotation-missing')));
    await tester.pumpAndSettle();
    final reveal = controller.state.reveal!.textAnchors.single;
    expect(reveal.chapterId, 'main');
    expect(reveal.start, 0);
    expect(reveal.end, 0);
    expect(reveal.revision, updated.revision);
    expect(find.text('Can’t find the original text'), findsOneWidget);
    await tester.longPress(find.byKey(const ValueKey('annotation-missing')));
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(controller.content.annotation('missing'), isNull);
    fail = true;
    owner.open(Uri.parse(updated.origin!.url), documentId: updated.id);
    await tester.pump();
    session = container.read(workspaceBrowserProvider('demo-1')).session!;
    await ready(session);
    context = tester.element(find.byType(BrowserPane));
    final failed = container.read(browserConverterProvider)!(context, 'demo-1', session);
    await tester.pumpAndSettle();
    await failed;
    expect(container.read(workspaceBrowserProvider('demo-1')).session, same(session));
    expect(controller.content.document(document.id)!.revision, updated.revision);
    owner.close();
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('narrow PDF source links only the domain and leaves the date inert', (tester) async {
    var opens = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('marginmind/external_link'),
      (_) async {
        opens++;
        return true;
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: MMTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 60,
              child: WebSourceAttribution(
                document: Document(
                  id: 'pdf',
                  title: 'Article',
                  fileName: 'article.pdf',
                  pageCount: 1,
                  importedAt: DateTime.utc(2026),
                  origin: DocumentOrigin(
                    url: 'https://example.com/article',
                    capturedAt: DateTime.utc(2026, 10, 29),
                    mode: WebCaptureMode.original,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.textContaining(' · '));
    await tester.pump();
    expect(opens, 0);
    await tester.tap(find.text('example.com'));
    await tester.pump();
    expect(opens, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('fast format switches share one capture; navigation invalidates the prepared document', (tester) async {
    final pending = Completer<BrowserDocumentCapture>();
    var captures = 0;
    final container = await pumpApp(
      tester,
      overrides: [
        webCaptureProvider.overrideWithValue((_, _, _, _) {
          captures++;
          return pending.future;
        }),
      ],
    );
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final owner = container.read(workspaceBrowserProvider('demo-1').notifier);
    owner.open(Uri.parse('https://example.com/article'));
    await tester.pump();
    final session = container.read(workspaceBrowserProvider('demo-1')).session!;
    await ready(session);
    final context = tester.element(find.byType(BrowserPane));
    final flow = container.read(browserConverterProvider)!(context, 'demo-1', session);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Markdown'));
    await tester.pump();
    expect(captures, 1);
    pending.complete(page());
    await tester.pumpAndSettle();
    expect(find.textContaining('# Heading'), findsOneWidget);
    final count = container.read(workspaceProvider('demo-1').notifier).content.documents.length;
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      'marginmind/browser/${session.id}',
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('event', {'kind': 'start', 'navigationId': 2, 'url': 'https://example.com/new'}),
      ),
      (_) {},
    );
    await tester.tap(find.widgetWithText(MMButton, 'Save'));
    await tester.pump(const Duration(seconds: 1));
    await flow;
    expect(container.read(workspaceProvider('demo-1').notifier).content.documents.length, count);
    owner.close();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
