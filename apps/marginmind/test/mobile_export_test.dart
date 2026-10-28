import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/workspace/widgets/map_export_sheet.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:marginmind/shared/pdf_drop.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('$platform exports text through native sharing and skips desktop drop', (tester) async {
      const channel = MethodChannel('marginmind/file_share');
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      MethodCall? call;
      messenger.setMockMethodCallHandler(channel, (value) async {
        call = value;
        return false;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await tester.pumpWidget(
        MaterialApp(
          theme: MMTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PdfDropTarget(
            label: 'Import',
            onDrop: (_) {},
            child: MapExportSheet(
              content: StudySetContent.empty,
              mapId: MindMap.defaultId,
              title: 'Notes',
              resolveImage: (_) => '',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('PNG'), findsNothing);
      expect(find.text('PDF'), findsNothing);
      expect(find.text('Markdown'), findsOneWidget);
      expect(find.text('OPML'), findsOneWidget);
      await tester.tap(find.text('Export…'));
      await tester.pumpAndSettle();
      expect(call!.method, 'share');
      expect((call!.arguments as Map)['name'], 'Notes.md');
      expect(find.byType(MapExportSheet), findsOneWidget);
      await tester.tap(find.text('OPML'));
      await tester.tap(find.text('Export…'));
      await tester.pumpAndSettle();
      expect((call!.arguments as Map)['name'], 'Notes.opml');
      messenger.setMockMethodCallHandler(channel, (_) async => throw PlatformException(code: 'share_failed'));
      await tester.tap(find.text('Export…'));
      await tester.pumpAndSettle();
      expect(find.byType(MapExportSheet), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant({platform}));
  }
}
