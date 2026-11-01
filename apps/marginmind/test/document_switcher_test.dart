import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';

import 'helpers.dart';

void main() {
  testWidgets('More keeps document management after removing the title row', (tester) async {
    final container = await pumpApp(tester);
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    await openReaderDocumentMenu(tester);
    expect(find.text('学习的底层逻辑'), findsWidgets);
    expect(find.text('Import Document…'), findsOneWidget);
    await tester.tap(find.text('论文：检索练习效应').last);
    await tester.pumpAndSettle();
    expect(container.read(workspaceProvider('demo-1')).activeDocumentId, 'c2');
    await openReaderDocumentMenu(tester);
    await tester.tap(find.text('Close Current Document'));
    await tester.pumpAndSettle();
    expect(container.read(workspaceProvider('demo-1')).activeDocumentId, 'c1');
    expect(tester.takeException(), isNull);
  });
}
