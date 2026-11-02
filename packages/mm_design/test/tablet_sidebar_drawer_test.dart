import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_design/mm_design.dart';

void main() {
  for (final size in [const Size(820, 1180), const Size(1180, 820)]) {
    for (final builder in [false, true]) {
      testWidgets('tablet drawer fills edges with safe controls ($size, builder: $builder)', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        var dismissed = false;
        const sidebar = MMSidebar(
          topTrailing: SizedBox(key: ValueKey('top-control'), width: 44, height: 44),
          footer: SizedBox(key: ValueKey('footer'), height: 44),
          children: [],
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: MMTheme.light(),
            home: MediaQuery(
              data: MediaQueryData(size: size, padding: const EdgeInsets.only(top: 24, bottom: 20)),
              child: MMInput(
                touchPlatform: true,
                phone: false,
                child: builder
                    ? MMWindowScaffold.contentBuilder(
                        sidebarOverlay: true,
                        sidebar: sidebar,
                        onSidebarDismiss: () => dismissed = true,
                        contentBuilder: (_, _) => const SizedBox.expand(),
                      )
                    : MMWindowScaffold(
                        sidebarOverlay: true,
                        sidebar: sidebar,
                        onSidebarDismiss: () => dismissed = true,
                        toolbar: const SizedBox(),
                        body: const SizedBox.expand(),
                      ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final surface = find.descendant(of: find.byType(MMSidebar), matching: find.byType(ClipRRect)).first;
        expect(tester.getRect(surface), Rect.fromLTWH(0, 0, MMSizes.sidebarWidth, size.height));
        expect(tester.widget<ClipRRect>(surface).borderRadius, BorderRadius.zero);
        expect(tester.getRect(find.byKey(const ValueKey('top-control'))).top, greaterThanOrEqualTo(24));
        expect(tester.getRect(find.byKey(const ValueKey('footer'))).bottom, lessThanOrEqualTo(size.height - 20));
        await tester.tapAt(Offset(size.width - 20, size.height / 2));
        expect(dismissed, isTrue);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
