import 'dart:io';

import 'package:campus_app/map/campus_geography.dart';
import 'package:campus_app/map/campus_location.dart';
import 'package:campus_app/player/cowboy_motion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // SYNTHETIC GPS ONLY: arbitrary deterministic positions, no recorded person.
  final epoch = DateTime.utc(2026, 1, 1);
  CowboyMotion route() => CowboyMotion();
  void fix(
    CowboyMotion motion,
    int second,
    double east,
    double north, {
    double accuracy = 3,
    bool inside = true,
  }) {
    final time = epoch.add(Duration(seconds: second));
    motion.accept(
      longitude: east / 111320,
      latitude: north / 111320,
      accuracy: accuracy,
      timestamp: time,
      now: time,
      onCampus: inside,
    );
  }

  test(
    'SIMULATED campus GPS: real boundary hides exit and stale positions',
    () {
      final geography = CampusGeography.fromGeoJson(
        File('assets/campus/boundary.geojson').readAsStringSync(),
      );
      final location = CampusLocationPolicy(geography);
      final motion = route();
      void accept(int second, CampusPoint point) {
        final now = epoch.add(Duration(seconds: second));
        location.accept(CampusFix(point, 3, now), now);
        motion.accept(
          longitude: point.longitude,
          latitude: point.latitude,
          accuracy: 3,
          timestamp: now,
          now: now,
          onCampus:
              location.state == CampusGpsState.onCampus &&
              location.marker != null,
        );
      }

      for (var i = 0; i < 3; i++) {
        accept(i * 2, CampusPoint(-98.174, 26.306 + i * 2.6 / 111320));
      }
      expect(location.marker, isNotNull);
      expect(motion.walking, isTrue);
      accept(6, const CampusPoint(-98.174, 26.34));
      expect(location.state, CampusGpsState.outside);
      expect(location.marker, isNull);
      expect(motion.walking, isFalse);
      accept(8, const CampusPoint(-98.174, 26.306));
      location.expire(epoch.add(const Duration(seconds: 40)));
      motion.expire(epoch.add(const Duration(seconds: 40)));
      expect(location.marker, isNull);
      expect(location.state, CampusGpsState.stale);
      expect(motion.walking, isFalse);
    },
  );

  test('SIMULATED GPS: walk, stop, turn, exit; no camera input', () {
    final m = route();
    fix(m, 0, 0, 0);
    fix(m, 2, 0, 2.6);
    expect(m.walking, isFalse);
    fix(m, 4, 0, 5.2);
    expect(m.walking, isTrue);
    expect(m.heading, closeTo(0, 0.01));
    expect(m.playbackRate, inInclusiveRange(0.65, 1.6));
    m.expire(epoch.add(const Duration(seconds: 9)));
    expect(m.walking, isFalse);
    fix(m, 10, 5.2, 5.2);
    fix(m, 12, 7.8, 5.2);
    expect(m.walking, isTrue);
    expect(m.heading, closeTo(90, 0.01));
    fix(m, 14, 10.4, 5.2, inside: false);
    expect(m.walking, isFalse);
  });

  test(
    'SIMULATED GPS: no first fix times out; restart requires fresh evidence',
    () {
      final location = CampusLocationPolicy(
        CampusGeography.fromGeoJson(
          File('assets/campus/boundary.geojson').readAsStringSync(),
        ),
      );
      location.begin(epoch);
      expect(location.marker, isNull);
      location.expire(epoch.add(const Duration(seconds: 21)));
      expect(location.state, CampusGpsState.unavailable);
      location.begin(epoch.add(const Duration(seconds: 22)));
      expect(location.state, CampusGpsState.waiting);
      expect(location.marker, isNull);
    },
  );

  test('SIMULATED GPS: stationary jitter and poor accuracy stay idle', () {
    final m = route();
    for (var i = 0; i < 30; i++) {
      fix(m, i, i.isEven ? 0.3 : -0.3, i.isEven ? 0.2 : -0.2, accuracy: 8);
      expect(m.walking, isFalse);
    }
    fix(m, 31, 10, 0, accuracy: 35);
    expect(m.walking, isFalse);
  });

  test(
    'SIMULATED GPS: teleports, duplicate, future and stale fixes do not walk',
    () {
      final m = route();
      fix(m, 0, 0, 0);
      fix(m, 1, 100, 0);
      expect(m.walking, isFalse);
      fix(m, 1, 101, 0);
      expect(m.walking, isFalse);
      m.accept(
        longitude: 0,
        latitude: 0,
        accuracy: 3,
        timestamp: epoch,
        now: epoch.add(const Duration(seconds: 30)),
        onCampus: true,
      );
      expect(m.walking, isFalse);
      m.accept(
        longitude: 0,
        latitude: 0,
        accuracy: 3,
        timestamp: epoch.add(const Duration(seconds: 90)),
        now: epoch,
        onCampus: true,
      );
      expect(m.walking, isFalse);
    },
  );

  test('SIMULATED GPS: alternating jumps cannot build a walking streak', () {
    final m = route();
    for (var i = 0; i < 12; i++) {
      fix(m, i * 2, i.isEven ? 0 : 3, 0);
      expect(m.walking, isFalse);
    }
  });
}
