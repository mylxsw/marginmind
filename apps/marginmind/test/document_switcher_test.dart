import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/workspace/widgets/document_switcher.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';

void main() {
  testWidgets('Aa document submenu preserves IDs, import and close actions', (tester) async {
    final container = await pumpApp(tester);
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final finder = find.byType(DocumentSwitcher);
    final widget = tester.widget<DocumentSwitcher>(finder);
    final element = tester.element(finder);
    final entries = widget.menuEntries(element, element as WidgetRef).whereType<MMMenuItem>().toList();
    final l = AppLocalizations.of(element);
    expect(entries.where((entry) => entry.checked == true).single.label, '学习的底层逻辑');
    expect(entries.any((entry) => entry.label == l.importDocument && entry.onSelected != null), isTrue);
    entries.singleWhere((entry) => entry.label == '论文：检索练习效应').onSelected!();
    await tester.pumpAndSettle();
    expect(container.read(workspaceProvider('demo-1')).activeDocumentId, 'c2');
    final next = tester.widget<DocumentSwitcher>(finder);
    final nextElement = tester.element(finder);
    next
        .menuEntries(nextElement, nextElement as WidgetRef)
        .whereType<MMMenuItem>()
        .singleWhere((entry) => entry.label == l.closeCurrentDocument)
        .onSelected!();
    await tester.pumpAndSettle();
    expect(container.read(workspaceProvider('demo-1')).activeDocumentId, 'c1');
    expect(tester.takeException(), isNull);
  });
}
