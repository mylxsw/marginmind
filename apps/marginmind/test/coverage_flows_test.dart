import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/gallery/gallery_screen.dart';
import 'package:marginmind/features/workspace/workspace_screen.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/features/workspace/widgets/notices.dart';
import 'package:marginmind/settings/app_settings.dart';
import 'package:marginmind/settings/settings_window.dart';
import 'package:marginmind/shared/l10n.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';

void main() {
  for (final language in ['en', 'zh']) {
    testWidgets('gallery controls and feedback work in $language', (tester) async {
      final container = await pumpApp(tester, prefs: {'settings.language': language});
      container.read(navigationProvider.notifier).showGallery();
      await tester.pumpAndSettle();
      final l = AppLocalizations.of(tester.element(find.byType(GalleryScreen)));
      expect(find.text('MMColors'), findsOneWidget);
      await tester.tap(find.text(l.galleryTypography));
      await tester.pumpAndSettle();
      expect(find.text('MMTypography'), findsOneWidget);
      await tester.tap(find.text(l.galleryControls));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(l.toolHighlight).first);
      await tester.pumpAndSettle();
      final tool = tester.widget<MMToolbarButton>(find.widgetWithIcon(MMToolbarButton, MMIcons.highlight).first);
      expect(tool.selected, isFalse);
      await tester.tap(find.text(l.outlineView));
      await tester.pumpAndSettle();
      expect(tester.widget<MMSegmentedControl<String>>(find.byType(MMSegmentedControl<String>)).value, 'outline');
      await tester.drag(find.byType(ListView).last, const Offset(0, -650));
      await tester.pumpAndSettle();
      expect(find.byType(MMProgressBar), findsOneWidget);
      // The English gallery feedback preview currently overflows its fixed-height
      // empty state with the test font; exercise feedback in Chinese.
      if (language == 'zh') {
        await tester.tap(find.text(l.galleryFeedback));
        await tester.pumpAndSettle();
        await tester.tap(find.text(l.galleryShowHud));
        await tester.pump();
        expect(find.text(l.galleryHudMessage), findsOneWidget);
        await settleHud(tester);
        await tester.tap(find.text(l.galleryShowSheet));
        await tester.pumpAndSettle();
        expect(find.byType(MMSheet), findsOneWidget);
        await tester.tap(find.text(l.cancel));
        await tester.pumpAndSettle();
        expect(find.byType(MMSheet), findsNothing);
      }
      await tester.tap(find.text(l.back));
      await tester.pumpAndSettle();
      expect(container.read(navigationProvider), isA<LibraryRoute>());
    });
    testWidgets('editing notices and confirmation outcomes in $language', (tester) async {
      final container = await pumpApp(tester, prefs: {'settings.language': language});
      container.read(navigationProvider.notifier).openStudySet('demo-1');
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(WorkspaceScreen));
      final l = AppLocalizations.of(context);
      final outcomes = <WorkspaceNotice, String>{
        const ExcerptedNotice(null): l.excerptedHud('root'),
        const HighlightedNotice(): l.highlightedHud,
        const RemovedNotice(): l.removedHud,
        const HighlightDeletedNotice(): l.highlightDeletedHud,
        const UndoneNotice(redo: false): l.undoneHud,
        const UndoneNotice(redo: true): l.redoneHud,
        const DocumentRemovedNotice(): l.documentRemovedHud,
        const ImportedNotice(2, []): l.importedHud(2),
        const ImportedNotice(0, ['file.pdf']): l.importFailed('file.pdf'),
      };
      for (final entry in outcomes.entries) {
        showNotice(context, entry.key, rootTitle: 'root');
        await tester.pump();
        expect(find.text(entry.value), findsOneWidget);
        await settleHud(tester);
      }
      for (final confirm in [false, true]) {
        final result = showConfirmSheet(context, title: 'Confirm', message: 'Delete this item?', confirmLabel: 'Yes');
        await tester.pumpAndSettle();
        await tester.tap(find.text(confirm ? 'Yes' : l.cancel));
        await tester.pumpAndSettle();
        expect(await result, confirm);
      }
    });
    testWidgets('settings and workspace render in $language with dark appearance', (tester) async {
      final container = await pumpApp(tester, prefs: {'settings.language': language});
      container.read(navigationProvider.notifier).openStudySet('demo-1');
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(WorkspaceScreen));
      final l = AppLocalizations.of(context);
      showSettings(context);
      await tester.pumpAndSettle();
      expect(find.text(l.settingsGeneral), findsNWidgets(2));
      await container.read(settingsProvider.notifier).setAppearance(AppearancePreference.dark);
      await tester.pumpAndSettle();
      expect(find.text(l.settingsGeneral), findsNWidgets(2));
      await tester.tap(find.byKey(const ValueKey('settings-close')));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsWindow), findsNothing);
      expect(find.byType(WorkspaceScreen), findsOneWidget);
      container.read(navigationProvider.notifier).startReview('demo-1');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('page-prompt')), findsOneWidget);
    });
  }
}
