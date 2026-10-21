import 'dart:io';
import 'dart:ui' as ui;
import 'package:campus_app/widgets/campus_creature.dart';
import 'package:campus_app/map/campus_creatures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';

void main() {
  testWidgets('mobile dragon keeps its animated alpha frames', (tester) async {
    await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(
        File(
          'assets/animations/campus-creatures/dragon.webp',
        ).readAsBytesSync(),
      );
      expect(codec.frameCount, 150);
      expect(codec.repetitionCount, -1);
      final first = await codec.getNextFrame();
      expect(first.image.width, 540);
      expect(first.image.height, 380);
      final a = (await first.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      expect(a.getUint8(3), 0);
      first.image.dispose();
      var elapsed = first.duration;
      for (var i = 1; i < 30; i++) {
        final frame = await codec.getNextFrame();
        elapsed += frame.duration;
        frame.image.dispose();
      }
      expect(elapsed.inMilliseconds, closeTo(1000, 2));
      final next = await codec.getNextFrame();
      final b = (await next.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      expect(
        b.buffer.asUint8List(),
        isNot(orderedEquals(a.buffer.asUint8List())),
      );
      next.image.dispose();
      codec.dispose();
    });
  });

  testWidgets('roof decorations pass gestures and honor reduced motion', (
    tester,
  ) async {
    var taps = 0;
    final dragon = CampusCreatureLandmark.all.first;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => taps++,
                  child: const ColoredBox(color: Colors.green),
                ),
              ),
              Positioned.fill(
                child: CampusBuildingCreatures(
                  placements: [
                    CampusCreaturePlacement(
                      dragon,
                      const Offset(200, 300),
                      180,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    expect(
      (tester.widget<Image>(find.byType(Image)).image as AssetImage).assetName,
      dragon.poster,
    );
    await tester.tapAt(const Offset(200, 280));
    expect(taps, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('floral animation decodes, plays and passes map input', (
    tester,
  ) async {
    final composition = await LottieComposition.fromBytes(
      File('assets/animations/campus-creatures/floral.json').readAsBytesSync(),
    );
    expect(composition.duration.inMilliseconds, greaterThan(5000));
    tester.view.physicalSize = const Size(432, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var taps = 0;
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(
            key: key,
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => taps++,
                    child: const ColoredBox(color: Color(0xffc9ddd3)),
                  ),
                ),
                const CampusCreature(
                  asset: 'assets/animations/campus-creatures/floral.json',
                  position: Offset(216, 500),
                  width: 220,
                  height: 220,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.tapAt(const Offset(216, 450));
    expect(taps, 1);
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    Future<List<int>> capture(String name) async {
      final image = (await tester.runAsync(
        () => boundary.toImage(pixelRatio: 1),
      ))!;
      final bytes = (await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.png),
      ))!;
      final result = bytes.buffer.asUint8List();
      await tester.runAsync(() async {
        Directory('tmp/landmark-review').createSync(recursive: true);
        File('tmp/landmark-review/$name.png').writeAsBytesSync(result);
      });
      image.dispose();
      return result;
    }

    final first = await capture('floral-first');
    await tester.pump(const Duration(milliseconds: 1000));
    final second = await capture('floral-second');
    expect(second, isNot(orderedEquals(first)));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
