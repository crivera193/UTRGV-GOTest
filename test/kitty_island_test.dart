import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:campus_app/widgets/kitty_island_cats.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';

void main() {
  testWidgets(
    'all actual Lottie files decode and animate without blocking input',
    (tester) async {
      for (final color in ['dark', 'orange', 'gray']) {
        final bytes = File(
          'assets/animations/kitty-island/cat-$color.json',
        ).readAsBytesSync();
        final composition = await LottieComposition.fromBytes(bytes);
        expect(composition.duration, const Duration(milliseconds: 1280));
        final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        expect(json['assets'], isEmpty);
      }
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
                  const Positioned.fill(
                    child: KittyIslandCats(
                      positions: [
                        Offset(95, 480),
                        Offset(216, 480),
                        Offset(337, 480),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(Lottie), findsNWidgets(3));
      await tester.tapAt(const Offset(216, 450));
      expect(taps, 1);
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final first = (await tester.runAsync(
        () => boundary.toImage(pixelRatio: 1),
      ))!;
      final firstBytes = (await tester.runAsync(
        () => first.toByteData(format: ui.ImageByteFormat.png),
      ))!;
      await tester.runAsync(() async {
        Directory('tmp/kitty-island').createSync(recursive: true);
        File(
          'tmp/kitty-island/cats-review.png',
        ).writeAsBytesSync(firstBytes.buffer.asUint8List());
      });
      await tester.pump(const Duration(milliseconds: 320));
      final second = (await tester.runAsync(
        () => boundary.toImage(pixelRatio: 1),
      ))!;
      final secondBytes = (await tester.runAsync(
        () => second.toByteData(format: ui.ImageByteFormat.png),
      ))!;
      expect(
        secondBytes.buffer.asUint8List(),
        isNot(orderedEquals(firstBytes.buffer.asUint8List())),
      );
      first.dispose();
      second.dispose();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
