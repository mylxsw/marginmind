import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/shared/card_image.dart';
import 'package:marginmind/shared/l10n.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';

class ImageRepository extends InMemoryStudySetContentRepository implements ReferencedResourceRepository {
  ImageRepository() : super({'demo-1': demoContent()});
  final changes = StreamController<ReferencedResource>.broadcast();
  int listeners = 0, resolutions = 0;
  @override
  Stream<ReferencedResource> watchReferencedResource(String set, String path) {
    late StreamController<ReferencedResource> out;
    StreamSubscription<ReferencedResource>? subscription;
    out = StreamController(
      onListen: () {
        listeners++;
        subscription = changes.stream.listen(out.add, onError: out.addError);
      },
      onCancel: () {
        listeners--;
        return subscription?.cancel();
      },
    );
    return out.stream;
  }
}

void main() {
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg==',
  );
  Future<void> host(WidgetTester tester, ImageRepository repo, {bool phone = false}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: await testOverrides(content: repo),
        child: MaterialApp(
          theme: MMTheme.light(),
          builder: (context, child) => MMInput(touchPlatform: phone, phone: phone, child: child!),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: CardImageScope(
              studySetId: 'demo-1',
              resolve: (_) {
                repo.resolutions++;
                return '/must-not-reopen.png';
              },
              child: Builder(
                builder: (context) => Column(
                  children: [
                    const SizedBox(width: 120, height: 100, child: CardImage('images/picture.png')),
                    TextButton(
                      onPressed: () => showCardImagePreview(context, 'images/picture.png'),
                      child: const Text('Preview'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('image waits, renders verified bytes, and removes stale decodes from an open preview', (tester) async {
    final repo = ImageRepository();
    await host(tester, repo);
    expect(find.byType(Image), findsNothing);
    repo.changes.add(ReferencedResource(DocumentResourceAvailability.missing));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Download incomplete'), findsOneWidget);
    repo.changes.add(ReferencedResource(DocumentResourceAvailability.ready, png));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNWidgets(2));
    expect(repo.listeners, 1);
    repo.changes.add(ReferencedResource(DocumentResourceAvailability.changed));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    expect(
      find.byWidgetPredicate((w) => w is Tooltip && (w.message?.contains('File differs') ?? false)),
      findsNWidgets(2),
    );
    repo.changes.addError(StateError('read failed'));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    expect(repo.resolutions, 0);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pump();
    expect(repo.listeners, 0);
    await repo.changes.close();
  });

  testWidgets('phone preview keeps the resource guard and closes without retaining its subscription', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = ImageRepository();
    await host(tester, repo, phone: true);
    repo.changes.add(ReferencedResource(DocumentResourceAvailability.ready, png));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNWidgets(2));
    repo.changes.add(ReferencedResource(DocumentResourceAvailability.missing));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    await tester.tap(find.byType(MMModalCloseButton));
    await tester.pumpAndSettle();
    expect(repo.listeners, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(repo.listeners, 0);
    await repo.changes.close();
  });

  testWidgets('undecodable verified bytes keep the placeholder instead of reopening a file', (tester) async {
    final repo = ImageRepository();
    await host(tester, repo);
    repo.changes.add(ReferencedResource(DocumentResourceAvailability.ready, [1, 2, 3]));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(repo.resolutions, 0);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await repo.changes.close();
  });
}
