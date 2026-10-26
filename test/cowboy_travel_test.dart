import 'dart:async';
import 'package:campus_app/player/cowboy_motion.dart';
import 'package:campus_app/player/cowboy_playback.dart';
import 'package:campus_app/player/cowboy_travel.dart';
import 'package:campus_app/player/latest_projection.dart';
import 'package:campus_app/map/campus_geography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final epoch = DateTime.utc(2026, 1, 1);
  test(
    'SIMULATED replay of observed 4.3 m/s route: east, north, capped walk',
    () {
      final motion = CowboyMotion();
      for (var t = 0; t <= 4; t++) {
        final now = epoch.add(Duration(seconds: t));
        motion.accept(
          longitude: t * 4.3 / 111320,
          latitude: 0,
          accuracy: 5,
          timestamp: now,
          now: now,
          onCampus: true,
          measuredSpeed: 4.3,
          speedAccuracy: 0.5,
        );
      }
      expect(motion.walking, isTrue);
      expect(motion.heading, closeTo(90, 0.1));
      expect(motion.playbackRate, 1.35);
      final now = epoch.add(const Duration(seconds: 5));
      motion.accept(
        longitude: 4 * 4.3 / 111320,
        latitude: 4.3 / 111320,
        accuracy: 5,
        timestamp: now,
        now: now,
        onCampus: true,
        measuredSpeed: 4.3,
        speedAccuracy: 0.5,
      );
      expect(motion.heading, closeTo(0, 0.1));
      expect(motion.walking, isTrue);
    },
  );
  test(
    'SIMULATED cadence: 12–20m accuracy no longer expires walk evidence',
    () {
      for (final accuracy in [12.0, 20.0]) {
        final m = CowboyMotion();
        for (var t = 0; t <= 16; t++) {
          final now = epoch.add(Duration(seconds: t));
          m.expire(now); // The previous bug requires expiry between arrivals.
          m.accept(
            longitude: 0,
            latitude: t * 1.2 / 111320,
            accuracy: accuracy,
            timestamp: now,
            now: now,
            onCampus: true,
          );
          if (t >= 8) {
            expect(m.walking, isTrue, reason: 'accuracy $accuracy, sample $t');
          }
        }
        for (var t = 17; t <= 20; t++) {
          final now = epoch.add(Duration(seconds: t));
          m.accept(
            longitude: 0,
            latitude: 16 * 1.2 / 111320,
            accuracy: accuracy,
            timestamp: now,
            now: now,
            onCampus: true,
          );
        }
        expect(m.walking, isFalse);
      }
    },
  );
  test(
    'SIMULATED display: continuous retarget, bounded lag and no prediction',
    () {
      final travel = CowboyTravel();
      travel.accept(
        const CampusPoint(0, 0),
        epoch,
        accuracy: 12,
        walking: false,
      );
      final target = CampusPoint(0, 1.2 / 111320);
      travel.accept(
        target,
        epoch.add(const Duration(seconds: 1)),
        accuracy: 12,
        walking: true,
      );
      var last = travel.position!;
      for (var f = 0; f < 15; f++) {
        travel.advance(1 / 60);
        expect(
          CampusGeography.distance(last, travel.position!),
          lessThan(0.13),
        );
        last = travel.position!;
      }
      final current = travel.position!;
      final next = CampusPoint(0, 2.4 / 111320);
      travel.accept(
        next,
        epoch.add(const Duration(milliseconds: 1250)),
        accuracy: 12,
        walking: true,
      );
      expect(travel.position, same(current));
      for (var f = 0; f < 40; f++) {
        travel.advance(1 / 60);
      }
      expect(CampusGeography.distance(travel.position!, next), lessThan(0.01));
      for (var f = 0; f < 600; f++) {
        travel.advance(1 / 60);
      }
      expect(
        travel.position,
        same(next),
      ); // Never extrapolates a last velocity.
      expect(
        travel.accept(
          const CampusPoint(0, 0),
          epoch,
          accuracy: 3,
          walking: true,
        ),
        isFalse,
      );
      travel.clear();
      expect(travel.position, isNull);
    },
  );
  test('loop survives long frames and facing has a switching margin', () {
    final loop = CowboyPlayback(), facing = CowboyFacing();
    loop.advance(.3, walking: true, rate: 1);
    expect(loop.phase, closeTo(.225, 1e-9));
    expect(loop.frame, 2);
    final phase = loop.phase;
    expect(facing.direction(0, 0), 0);
    expect(facing.direction(23, 0), 0);
    expect(facing.direction(22, 0), 0);
    expect(facing.direction(30, 0), 1);
    expect(facing.direction(20, 0), 1);
    expect(facing.direction(15, 0), 0);
    expect(facing.pitch(45), 2);
    expect(facing.pitch(39), 2);
    expect(loop.phase, phase);
    loop.advance(0, walking: false, rate: 1);
    expect(loop.frame, 12);
    loop.dispose();
  });
  test(
    'late projection discarded, coalesced queue reads latest only',
    () async {
      var target = 1, reads = 0;
      final completions = <Completer<int?>>[],
          applied = <int?>[],
          inputs = <int>[];
      final projector = LatestProjection<int>(
        read: () {
          reads++;
          inputs.add(target);
          final c = Completer<int?>();
          completions.add(c);
          return c.future;
        },
        apply: applied.add,
      );
      final done = projector.request();
      target = 2;
      unawaited(projector.request(invalidate: true));
      target = 3;
      unawaited(projector.request());
      expect(reads, 1);
      completions[0].complete(1);
      await Future<void>.delayed(Duration.zero);
      expect(applied, isEmpty);
      expect(inputs, [1, 3]);
      completions[1].complete(3);
      await done;
      expect(applied, [3]);
      final pending = projector.request();
      projector.dispose();
      completions[2].complete(3);
      await pending;
      expect(applied, [3]);
    },
  );
}
