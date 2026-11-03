import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_design/mm_design.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const codec = StandardMethodCodec();
  const channel = MethodChannel('marginmind/presentation');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() {
    MMNativePresentation.available = false;
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  Future<Object?> incoming(String method, Map<String, Object> args) {
    final completed = Completer<Object?>();
    messenger.handlePlatformMessage(channel.name, codec.encodeMethodCall(MethodCall(method, args)), (data) {
      try {
        completed.complete(codec.decodeEnvelope(data!));
      } catch (error, stack) {
        completed.completeError(error, stack);
      }
    });
    return completed.future;
  }

  test('native forms validate before closing and release their session callbacks', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    String? session;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'available') return true;
      final args = (call.arguments as Map).cast<String, dynamic>();
      expect(args['modalStyle'], MMModalStyle.nativeConfiguration);
      session = args['id'] as String;
      expect(
        await incoming('validate', {
          'id': session!,
          'values': {'url': 'bad'},
        }),
        'Invalid address',
      );
      expect(
        await incoming('validate', {
          'id': session!,
          'values': {'url': 'https://example.com'},
        }),
        isNull,
      );
      return {'url': 'https://example.com'};
    });
    await MMNativePresentation.initialize();
    expect(MMNativePresentation.available, isTrue);
    final values = await MMNativePresentation.form(
      title: 'Web',
      cancel: 'Cancel',
      submit: 'Open',
      discard: 'Discard',
      keepEditing: 'Keep editing',
      discardTitle: 'Discard changes?',
      fields: const [MMNativeField(id: 'url', label: 'Address', keyboard: 'url')],
      validate: (values) => values['url']!.startsWith('https://') ? null : 'Invalid address',
    );
    expect(values, {'url': 'https://example.com'});
    expect(
      await incoming('validate', {
        'id': session!,
        'values': {'url': 'bad'},
      }),
      'This form has closed.',
    );
  });

  test('native inline actions refresh content and release callbacks on dismissal', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    String? session;
    var selected = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'available') return true;
      expect(call.method, 'actions');
      expect((call.arguments as Map)['modalStyle'], MMModalStyle.nativeConfiguration);
      session = (call.arguments as Map)['id'] as String;
      expect(await incoming('action', {'id': session!, 'action': 'toggle'}), {'selected': true});
      expect(await incoming('action', {'id': session!, 'action': 'toggle'}), {'selected': false});
      return 'outline';
    });
    await MMNativePresentation.initialize();
    expect(
      await MMNativePresentation.actions(
        content: {'title': 'Reader'},
        onAction: (action) async {
          expect(action, 'toggle');
          selected = !selected;
          return {'selected': selected};
        },
      ),
      'outline',
    );
    expect(await incoming('action', {'id': session!, 'action': 'toggle'}), isNull);
    expect(selected, isFalse);
  });

  testWidgets('phone sheet drag respects the live PopScope guard', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final canClose = ValueNotifier(false);
    addTearDown(canClose.dispose);
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        theme: MMTheme.light(),
        builder: (_, child) => MMInput(touchPlatform: true, phone: true, child: child!),
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox.expand();
          },
        ),
      ),
    );
    final result = showMMSheet<void>(
      context: context,
      builder: (_) => ValueListenableBuilder(
        valueListenable: canClose,
        builder: (_, allow, _) => PopScope(
          canPop: allow,
          child: const MMSheet(title: 'Draft', child: Text('Keep this content')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final frame = find.byType(MMSheet);
    await tester.fling(find.byKey(const ValueKey('mm-bottom-sheet-handle')), const Offset(0, 600), 1600);
    await tester.pumpAndSettle();
    expect(frame, findsOneWidget);
    canClose.value = true;
    await tester.pumpAndSettle();
    await tester.fling(find.byKey(const ValueKey('mm-bottom-sheet-handle')), const Offset(0, 600), 1600);
    await tester.pumpAndSettle();
    expect(frame, findsNothing);
    await result;
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant({TargetPlatform.iOS, TargetPlatform.android}));
}
