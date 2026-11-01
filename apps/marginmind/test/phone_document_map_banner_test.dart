import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/features/workspace/workspace_screen.dart';
import 'package:marginmind/features/map_generation/widgets/document_map_banner.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';
import 'reader_crop_test.dart' show drain;

void main() {
  for (final width in [320.0, 393.0]) {
    for (final language in ['en', 'zh']) {
      for (final scale in [1.0, 1.5]) {
        testWidgets('phone map banner actions fit width=$width language=$language scale=$scale', (tester) async {
          final container = await pumpApp(
            tester,
            size: Size(width, 852),
            prefs: {'settings.language': language, 'settings.betaFeaturesEnabled': true},
            overrides: [touchPlatformProvider.overrideWithValue(true), phoneProvider.overrideWithValue(true)],
          );
          container.read(navigationProvider.notifier).openStudySet('demo-1');
          await drain(tester);
          final workspace = container.read(workspaceProvider('demo-1').notifier);
          workspace.openDocument('c2');
          workspace.setLayout(MMSplitMode.secondary);
          await drain(tester);
          final scope = ProviderScope.containerOf(tester.element(find.byType(DocumentMapBanner)));
          showDialog<void>(
            context: tester.element(find.byType(WorkspaceScreen)),
            builder: (context) => UncontrolledProviderScope(
              container: scope,
              child: Dialog(
                insetPadding: EdgeInsets.zero,
                child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
                  child: SizedBox(
                    width: width,
                    child: const DocumentMapBanner(studySetId: 'demo-1'),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final banner = tester.getRect(
            find.descendant(of: find.byType(Dialog), matching: find.byType(DocumentMapBanner)),
          );
          for (final key in ['document-map-generate', 'document-map-merge']) {
            final action = find.descendant(of: find.byType(Dialog), matching: find.byKey(ValueKey(key)));
            expect(action.hitTestable(), findsOneWidget);
            final bounds = tester.getRect(action);
            expect(bounds.left, greaterThanOrEqualTo(banner.left));
            expect(bounds.right, lessThanOrEqualTo(banner.right));
            expect(bounds.height, greaterThanOrEqualTo(MMSizes.touchTarget));
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await drain(tester);
        });
      }
    }
  }
}
