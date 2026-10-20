import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:campus_app/map/campus_geography.dart';
import 'package:campus_app/player/cowboy_motion.dart';
import 'package:campus_app/player/cowboy_sprite.dart';
import 'package:campus_app/player/cowboy_travel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'SIMULATED route: start, steady walk between fixes, turn, stop, stale; persistent runtime frames',
    (tester) async {
      final motion = CowboyMotion(), travel = CowboyTravel();
      final placement = ValueNotifier<CowboyPlacement?>(
        const CowboyPlacement(Offset(195, 420), 0, 55, 17.5),
      );
      final boundary = GlobalKey();
      var backgroundBuilds = 0;
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: boundary,
            child: Stack(
              children: [
                Builder(
                  builder: (_) {
                    backgroundBuilds++;
                    return const ColoredBox(
                      color: Color(0xffe8eee7),
                      child: SizedBox.expand(),
                    );
                  },
                ),
                CowboySprite(
                  key: const ValueKey('persistent'),
                  motion: motion,
                  placement: placement,
                ),
              ],
            ),
          ),
        ),
      );
      final finder = find.byKey(const ValueKey('cowboy-runtime-frame'));
      for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(finder, findsOneWidget);
      final state = tester.state(find.byType(CowboySprite));
      CowboyFramePainter painter() =>
          tester.widget<CustomPaint>(finder).painter! as CowboyFramePainter;
      final epoch = DateTime.utc(2026, 1, 1),
          frames = <int>[],
          captures = <Map<String, Object>>[];
      var maxStep = 0.0;
      CampusPoint? last;
      for (var second = 0; second <= 13; second++) {
        final now = epoch.add(Duration(seconds: second));
        final east = second <= 6 ? second * 1.2 : 7.2;
        final north = second <= 6
            ? 0.0
            : (second <= 10 ? (second - 6) * 1.2 : 4.8);
        final point = CampusPoint(
          -98.174 + east / 99800,
          26.306 + north / 111320,
        );
        final before = painter().playback.phase;
        motion.expire(now);
        motion.accept(
          longitude: point.longitude,
          latitude: point.latitude,
          accuracy: 12,
          timestamp: now,
          now: now,
          onCampus: true,
        );
        travel.accept(point, now, accuracy: 12, walking: motion.walking);
        placement.value = CowboyPlacement(const Offset(195, 420), 0, 55, 17.5);
        await tester.pump();
        expect(
          painter().playback.phase,
          closeTo(before, 1e-10),
          reason: 'GPS/direction must not reset the cycle',
        );
        if (second >= 5 && second <= 10) expect(motion.walking, isTrue);
        if (second >= 12) expect(motion.walking, isFalse);
        for (var f = 0; f < 60; f++) {
          travel.advance(1 / 60);
          if (last != null) {
            final step = CampusGeography.distance(last, travel.position!);
            if (step > maxStep) maxStep = step;
          }
          last = travel.position;
          // Projection fixture only. Native Mapbox is deliberately not instantiated.
          final cameraPan = (second == 8 || second == 13) && f > 15
              ? 18.0
              : 0.0;
          final accepted = travel.target, heading = motion.heading;
          placement.value = CowboyPlacement(
            Offset(195 + cameraPan, 420),
            cameraPan,
            55,
            17.5,
          );
          expect(travel.target, same(accepted));
          expect(motion.heading, heading);
          if (second >= 12) expect(motion.walking, isFalse);
          await tester.pump(const Duration(microseconds: 16667));
          if (second == 5 && [6, 24, 42].contains(f)) {
            frames.add(painter().frame);
            final name = 'runtime-walk-${captures.length}.png';
            final frame = painter().frame;
            await tester.runAsync(() async {
              final image =
                  await (boundary.currentContext!.findRenderObject()!
                          as RenderRepaintBoundary)
                      .toImage();
              final bytes = (await image.toByteData(
                format: ui.ImageByteFormat.png,
              ))!.buffer.asUint8List();
              await Directory('tmp/avatar-repair').create(recursive: true);
              await File('tmp/avatar-repair/$name').writeAsBytes(bytes);
              image.dispose();
            });
            captures.add({
              'file': name,
              'frame': frame,
              'synthetic_seconds': second + f / 60,
            });
          }
        }
      }
      expect(
        frames.toSet().length,
        3,
        reason: 'different leg poses must render without another GPS arrival',
      );
      expect(maxStep, lessThan(0.2));
      expect(
        backgroundBuilds,
        1,
        reason: 'player animation/projection must not rebuild map/background',
      );
      expect(tester.state(find.byType(CowboySprite)), same(state));
      expect(painter().frame, 12);
      final idlePhase = painter().playback.phase;
      await tester.pump(const Duration(milliseconds: 300));
      expect(painter().playback.phase, idlePhase);
      motion.accept(
        longitude: 0,
        latitude: 0,
        accuracy: 12,
        timestamp: epoch,
        now: epoch.add(const Duration(seconds: 40)),
        onCampus: true,
      );
      travel.clear();
      placement.value = null;
      await tester.pump();
      expect(motion.walking, isFalse);
      expect(finder, findsNothing);
      expect(tester.state(find.byType(CowboySprite)), same(state));
      await tester.runAsync(() async {
        await File('tmp/avatar-repair/runtime-route.json').writeAsString(
          jsonEncode({
            'SIMULATED_GPS_ONLY': true,
            'cadence_seconds': 1,
            'accuracy_m': 12,
            'frames': captures,
            'max_display_step_m': maxStep,
            'background_builds': backgroundBuilds,
            'native_Mapbox': false,
          }),
        );
      });
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      placement.dispose();
    },
  );
}
