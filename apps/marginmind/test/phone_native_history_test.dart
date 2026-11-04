import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/workspace/widgets/phone_native_more_sheet.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/features/workspace/workspace_screen.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';
import 'workspace_tabs_test.dart' show openTabs;

void main() {
  testWidgets('native more exposes observed redo availability and dispatches through safe history', (tester) async {
    final container = await openTabs(tester, size: const Size(393, 852), touch: true);
    final owner = container.read(workspaceProvider('demo-1').notifier);
    const channel = MethodChannel('marginmind/presentation');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    MMNativePresentation.available = true;
    addTearDown(() {
      MMNativePresentation.available = false;
      messenger.setMockMethodCallHandler(channel, null);
    });
    var enabled = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'actions');
      final content = call.arguments as Map;
      final rows = (content['groups'] as List).expand((group) => group as List).cast<Map>();
      final redo = rows.singleWhere((row) => row['id'] == 'redo');
      expect(redo['title'], 'Redo');
      expect(redo['enabled'], enabled);
      return enabled ? 'redo' : null;
    });
    Future<void> open() => showPhoneNativeMoreSheet(tester.element(find.byType(WorkspaceScreen)), studySetId: 'demo-1');
    await open();
    final card = await owner.addTopic('Native history');
    await owner.undo();
    await tester.pumpAndSettle();
    expect(owner.content.card(card.id), isNull);
    enabled = true;
    await open();
    await tester.pumpAndSettle();
    expect(owner.content.card(card.id)?.toJson(), card.toJson());
    enabled = false;
    await open();
    expect(tester.takeException(), isNull);
    await settleHud(tester);
  });
}
