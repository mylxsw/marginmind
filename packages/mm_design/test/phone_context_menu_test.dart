import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_design/mm_design.dart';

void main() {
  for (final portal in [false, true]) {
    for (final dark in [false, true]) {
      testWidgets('long phone context menu aligns, scrolls and selects (portal: $portal, dark: $dark)', (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
        addTearDown(tester.view.reset);
        late BuildContext context;
        var invoked = false;
        final content = Builder(
          builder: (c) {
            context = c;
            return const Scaffold();
          },
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? MMTheme.dark() : MMTheme.light(),
            builder: (_, child) => MMInput(touchPlatform: true, phone: true, child: child!),
            home: portal ? MMContextMenuHost(child: content) : content,
          ),
        );
        final entries = <MMMenuEntry>[
          const MMMenuHeader('问助手'),
          MMMenuItem('扩展想法', () {}, icon: MMIcons.expand),
          MMMenuItem('解释这张卡片', () {}, icon: MMIcons.info, shortcut: 'Ctrl+Shift+E'),
          const MMMenuDivider(),
          MMMenuItem('重命名', () {}, shortcut: 'F2'),
          MMMenuItem('模型', () {}, detail: '本地模型'),
          const MMMenuItem('不可用', null, disabledReason: '需要选择节点'),
          for (var i = 0; i < 12; i++) MMMenuItem('操作 $i', () {}, icon: MMIcons.tag),
          const MMMenuDivider(),
          MMMenuItem(
            '移除节点',
            () {
              invoked = true;
            },
            destructive: true,
            icon: MMIcons.trash,
          ),
        ];
        showMMMenu(context, position: const Offset(100, 200), entries: entries);
        await tester.pumpAndSettle();
        final sheet = find.byKey(const ValueKey('mm-bottom-sheet'));
        final frame = tester.getRect(sheet);
        expect(frame.top, greaterThan(400));
        expect(frame.bottom, lessThanOrEqualTo(810));
        expect(find.text('Ctrl+Shift+E'), findsNothing);
        expect(find.text('F2'), findsNothing);
        expect(find.text('本地模型'), findsOneWidget);
        final left = tester.getRect(find.text('扩展想法')).left;
        expect(tester.getRect(find.text('解释这张卡片')).left, left);
        expect(tester.getRect(find.text('重命名')).left, left);
        expect(find.text('Cancel').hitTestable(), findsOneWidget);
        await tester.tap(find.text('不可用'));
        await tester.pumpAndSettle();
        expect(sheet, findsOneWidget);
        // Expanding keeps every menu action available, then rotation still fits.
        await tester.drag(find.byKey(const ValueKey('mm-bottom-sheet-handle')), const Offset(0, -420));
        await tester.pumpAndSettle();
        expect(tester.getRect(sheet).height, greaterThan(frame.height));
        tester.view.physicalSize = const Size(844, 390);
        tester.view.padding = const FakeViewPadding(left: 44, right: 44, bottom: 21);
        await tester.pumpAndSettle();
        expect(tester.getRect(sheet).left, greaterThanOrEqualTo(44));
        expect(find.text('Cancel').hitTestable(), findsOneWidget);
        final scroll = find.descendant(
          of: find.byKey(const ValueKey('mm-action-sheet-scroll')),
          matching: find.byType(Scrollable),
        );
        await tester.scrollUntilVisible(find.text('移除节点'), 200, scrollable: scroll);
        await tester.tap(find.text('移除节点'));
        await tester.pumpAndSettle();
        expect(invoked, isTrue);
        expect(sheet, findsNothing);
        expect(tester.takeException(), isNull);
      }, variant: TargetPlatformVariant({TargetPlatform.iOS, TargetPlatform.android}));
    }
  }
}
