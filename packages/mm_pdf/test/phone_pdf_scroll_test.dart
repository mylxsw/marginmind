import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:pdfrx/pdfrx.dart';

import 'support/pdf_backend.dart';

void main() {
  setUp(() => installTestPdfBackend(pageCount: 60));
  final allMeasurements = <Map<String, Object>>[];
  tearDownAll(() {
    final output = Platform.environment['MM_SCROLL_EVIDENCE'];
    if (output != null) File(output).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(allMeasurements));
  });
  for (final device in [
    (size: const Size(393, 852), profile: MMPdfScrollProfile.phone, frameUs: 16667),
    (size: const Size(852, 393), profile: MMPdfScrollProfile.touch, frameUs: 16667),
    (size: const Size(834, 1194), profile: MMPdfScrollProfile.touch, frameUs: 16667),
    (size: const Size(1194, 834), profile: MMPdfScrollProfile.touch, frameUs: 8333),
    (size: const Size(393, 1024), profile: MMPdfScrollProfile.touch, frameUs: 16667),
  ]) {
    testWidgets('${device.size} pan travels farther, stops at edges, isolates wheel/scale and can be interrupted', (
      tester,
    ) async {
      tester.view.physicalSize = device.size;
      final origin = device.size.center(Offset.zero);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final measurements = <Map<String, Object>>[];
      var tracker = VelocityTracker.withKind(PointerDeviceKind.touch);
      var releaseVelocity = 0.0;
      final wheelDistances = <double>[];
      Future<MMPdfViewController> open(MMPdfScrollProfile? profile) async {
        final controller = MMPdfViewController();
        await tester.pumpWidget(
          MaterialApp(
            home: Listener(
              onPointerDown: (event) {
                tracker = VelocityTracker.withKind(event.kind)..addPosition(event.timeStamp, event.localPosition);
              },
              onPointerMove: (event) => tracker.addPosition(event.timeStamp, event.localPosition),
              onPointerUp: (_) => releaseVelocity = tracker.getVelocity().pixelsPerSecond.dy,
              child: MMPdfView(
                key: UniqueKey(),
                filePath: 'phone-fling.pdf',
                controller: controller,
                scrollProfile: profile,
                pageSpacing: 0,
              ),
            ),
          ),
        );
        for (var i = 0; i < 100 && !controller.isReady; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pump();
        }
        expect(controller.isReady, isTrue);
        await tester.pumpAndSettle();
        return controller;
      }

      Future<void> jump(Future<void> move) async {
        await tester.pump();
        await tester.pumpAndSettle();
        await move;
      }

      for (final profile in [null, device.profile]) {
        final controller = await open(profile);
        final pdf = tester.widget<PdfViewer>(find.byType(PdfViewer)).controller!;
        expect(pdf.params.scrollPhysics, profile == null ? isNull : isA<MMPhoneScrollPhysics>());
        expect(pdf.params.scrollPhysicsScale, profile == null ? isNull : isA<BouncingScrollPhysics>());
        // Once the pan recognizer is active, dragging stays glued to the finger.
        await jump(controller.jumpToPage(30));
        await tester.pumpAndSettle();
        final drag = await tester.startGesture(origin);
        await drag.moveBy(const Offset(0, -40));
        await tester.pump(const Duration(milliseconds: 16));
        final dragStart = controller.scrollPosition!.offset;
        await drag.moveBy(const Offset(0, -80));
        await tester.pump(const Duration(milliseconds: 16));
        expect(controller.scrollPosition!.offset - dragStart, closeTo(80, .1));
        await drag.cancel();
        await tester.pumpAndSettle();
        for (final speed in [300.0, 1500.0, 5000.0]) {
          for (final direction in [-1, 1]) {
            await jump(controller.jumpToPage(30));
            await tester.pumpAndSettle();
            final before = controller.scrollPosition!.offset;
            await tester.flingFrom(origin, Offset(0, -direction * 180), speed);
            final release = controller.scrollPosition!.offset;
            final frames = <double>[];
            for (var i = 0; i < (8000000 / device.frameUs).ceil(); i++) {
              await tester.pump(Duration(microseconds: device.frameUs));
              frames.add(controller.scrollPosition!.offset);
            }
            measurements.add({
              'profile': profile?.name ?? 'legacy',
              'speed': speed,
              'releaseVelocity': releaseVelocity,
              'zoom': controller.zoom,
              'frameIntervalUs': device.frameUs,
              'width': device.size.width,
              'height': device.size.height,
              'direction': direction,
              'start': before,
              'release': release,
              'distance': (frames.last - before).abs(),
              'inertia': (frames.last - release).abs(),
              'frames': frames,
            });
            expect(frames.every((value) => value.isFinite), isTrue);
            expect((frames.last - frames[frames.length - 2]).abs(), lessThan(.1));
          }
        }
        await jump(controller.jumpToPage(30));
        final wheelStart = controller.scrollPosition!.offset;
        await tester.sendEventToBinding(PointerScrollEvent(position: origin, scrollDelta: Offset(0, 60)));
        await tester.pumpAndSettle();
        wheelDistances.add((controller.scrollPosition!.offset - wheelStart).abs());
        if (profile != null) {
          // Another touch stops inertia; wheel movement is never velocity amplified.
          await jump(controller.jumpToPage(30));
          await tester.pumpAndSettle();
          await tester.flingFrom(origin, const Offset(0, -180), 1500);
          await tester.pump(const Duration(milliseconds: 100));
          final gesture = await tester.startGesture(origin);
          await tester.pump(const Duration(milliseconds: 16));
          final stopped = controller.scrollPosition!.offset;
          await tester.pump(const Duration(milliseconds: 200));
          expect(controller.scrollPosition!.offset, closeTo(stopped, .1));
          await gesture.up();
          await tester.pumpAndSettle();
          // Pinch uses the plain scale physics; its released transform is stable.
          final zoom = controller.zoom;
          final first = await tester.startGesture(origin - const Offset(75, 0), pointer: 11);
          final second = await tester.startGesture(origin + const Offset(75, 0), pointer: 12);
          for (var step = 0; step < 10; step++) {
            await first.moveBy(const Offset(-4, 0));
            await second.moveBy(const Offset(4, 0));
            await tester.pump(const Duration(milliseconds: 16));
          }
          await first.up();
          await second.up();
          await tester.pumpAndSettle();
          expect(controller.zoom, greaterThan(zoom));
          final pinchedZoom = controller.zoom;
          await tester.pump(const Duration(milliseconds: 300));
          expect(controller.zoom, closeTo(pinchedZoom, .001));
          for (final direction in [-1, 1]) {
            await tester.flingFrom(origin, Offset(direction * 150, 0), 5000);
            await tester.pumpAndSettle();
            final clamped = pdf.makeMatrixInSafeRange(pdf.value, forceClamp: true);
            expect(pdf.value.getTranslation().x, closeTo(clamped.getTranslation().x, 1));
          }
          for (final end in [false, true]) {
            if (end) {
              await jump(controller.lastPage());
            } else {
              await jump(controller.firstPage());
            }
            await tester.pumpAndSettle();
            final edge = controller.scrollPosition!.offset;
            await tester.flingFrom(origin, Offset(0, end ? -250 : 250), 5000);
            await tester.pumpAndSettle();
            expect(controller.scrollPosition!.offset, closeTo(edge, 1));
          }
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 200));
        controller.dispose();
      }
      expect(wheelDistances[1], closeTo(wheelDistances[0], .1));
      for (var i = 0; i < 6; i++) {
        expect(measurements[i + 6]['inertia'] as double, greaterThan((measurements[i]['inertia'] as double) * 2));
      }
      allMeasurements.addAll(measurements);
      expect(tester.takeException(), isNull);
    });
  }
}
