import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:campus_app/player/cowboy_motion.dart';
import 'package:campus_app/player/cowboy_sprite.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'exported cowboy plays, stands still, and faces camera-relative heading without input',
    (tester) async {
      final motion = CowboyMotion();
      final boundaryKey = GlobalKey();
      double bearing = 0;
      Widget scene() => MaterialApp(
        home: RepaintBoundary(
          key: boundaryKey,
          child: ColoredBox(
            color: const Color(0xffe8eee7),
            child: Stack(
              children: [
                CowboySprite(
                  motion: motion,
                  ground: const Offset(195, 400),
                  bearing: bearing,
                  pitch: 45,
                  zoom: 17.5,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(scene());
      for (
        var i = 0;
        i < 100 &&
            find
                .byKey(const ValueKey('cowboy-runtime-frame'))
                .evaluate()
                .isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(
        find.byKey(const ValueKey('cowboy-runtime-frame')),
        findsOneWidget,
      );
      Future<Uint8List> pixels({String? save}) async {
        return (await tester.runAsync(() async {
          final image =
              await (boundaryKey.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!.buffer.asUint8List();
          if (save != null) {
            final png = (await image.toByteData(
              format: ui.ImageByteFormat.png,
            ))!.buffer.asUint8List();
            await Directory('tmp/avatar').create(recursive: true);
            await File('tmp/avatar/$save.png').writeAsBytes(png);
          }
          image.dispose();
          return bytes;
        }))!;
      }

      final idle = await pixels(save: 'flutter-idle');
      await tester.pump(const Duration(milliseconds: 180));
      expect(await pixels(), orderedEquals(idle));
      // Explicitly SIMULATED GPS, no services or device interaction.
      final epoch = DateTime.utc(2026, 1, 1);
      for (var i = 0; i < 3; i++) {
        final now = epoch.add(Duration(seconds: 2 * i));
        motion.accept(
          longitude: 0,
          latitude: i * 2.6 / 111320,
          accuracy: 3,
          timestamp: now,
          now: now,
          onCampus: true,
        );
      }
      expect(motion.walking, isTrue);
      await tester.pump(const Duration(milliseconds: 120));
      final walk = await pixels(save: 'flutter-walk');
      expect(walk, isNot(orderedEquals(idle)));
      await tester.pump(const Duration(milliseconds: 150));
      expect(await pixels(), isNot(orderedEquals(walk)));
      motion.stop();
      await tester.pumpWidget(scene());
      await tester.pump();
      final stop = await pixels();
      await tester.pump(const Duration(milliseconds: 150));
      expect(await pixels(), orderedEquals(stop));
      bearing = 90;
      await tester.pumpWidget(scene());
      await tester.pump();
      expect(motion.walking, isFalse);
      expect(motion.heading, 0);
      expect(await pixels(save: 'flutter-rotated'), isNot(orderedEquals(stop)));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
