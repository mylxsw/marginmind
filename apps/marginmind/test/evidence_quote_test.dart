import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/research/widgets/research_widgets.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:mm_design/mm_design.dart';

void main() {
  Future<void> pump(WidgetTester tester, String quote, {VoidCallback? onOpen}) => tester.pumpWidget(
    MaterialApp(
      theme: MMTheme.light(),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(
        body: SizedBox(
          width: 320,
          child: EvidenceQuote(quote: quote, caption: 'From source 1', onOpen: onOpen),
        ),
      ),
    ),
  );

  Text quoteText(WidgetTester tester, String quote) => tester.widget<Text>(find.text(quote));

  testWidgets('a long quote shows four lines and expands on request', (tester) async {
    final long = List.filled(40, 'With the globalization and impact of the Internet.').join(' ');
    var opened = 0;
    await pump(tester, long, onOpen: () => opened++);
    expect(quoteText(tester, long).maxLines, EvidenceQuote.maxLines);
    expect(find.text('From source 1'), findsOneWidget);
    await tester.tap(find.text('Expand'));
    await tester.pump();
    expect(quoteText(tester, long).maxLines, isNull);
    await tester.tap(find.text('Collapse'));
    await tester.pump();
    expect(quoteText(tester, long).maxLines, EvidenceQuote.maxLines);
    // The text itself opens the source at the quoted paragraph.
    await tester.tap(find.text(long));
    await tester.pump(kDoubleTapTimeout);
    expect(opened, 1);
  });

  testWidgets('a short quote has nothing to expand', (tester) async {
    await pump(tester, 'Spacing works.');
    expect(find.text('Expand'), findsNothing);
    expect(find.text('Spacing works.'), findsOneWidget);
  });
}
