import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_app/map/campus_geography.dart';
import 'package:campus_app/map/campus_location.dart';
import 'package:campus_app/player/cowboy_travel.dart';
import 'package:campus_app/games/spot_proximity.dart';

void main() {
  final g = CampusGeography.fromGeoJson(
    File('assets/campus/boundary.geojson').readAsStringSync(),
  );
  final start = DateTime.utc(2026, 10, 23);
  const point = CampusPoint(-98.16946621, 26.30304392);
  test(
    'quick stream reconnect retains recent display and duplicate protection',
    () {
      final location = CampusLocationPolicy(g)
        ..accept(CampusFix(point, 5, start), start);
      final marker = location.marker;
      expect(marker, isNotNull);
      location.resume(start.add(const Duration(seconds: 2)));
      expect(location.marker, same(marker));
      expect(location.state, CampusGpsState.onCampus);
      location.accept(
        CampusFix(g.center, 5, start),
        start.add(const Duration(seconds: 3)),
      );
      expect(location.marker, same(marker));
      location.expire(start.add(const Duration(seconds: 22)));
      expect(location.marker, isNull);
      expect(location.state, CampusGpsState.stale);
    },
  );
  test(
    'long absence waits for a new fix and never resurrects stale marker',
    () {
      final location = CampusLocationPolicy(g)
        ..accept(CampusFix(point, 5, start), start);
      location.resume(start.add(const Duration(seconds: 22)));
      expect(location.marker, isNull);
      expect(location.state, CampusGpsState.waiting);
    },
  );
  test('display retention does not retain proximity entitlement', () {
    final fix = CampusFix(point, 5, start);
    final location = CampusLocationPolicy(g)..accept(fix, start);
    final proximity = SpotProximity(const [])
      ..accept(fix, onCampus: true, now: start);
    proximity.unavailable();
    location.resume(start.add(const Duration(seconds: 2)));
    proximity.accept(
      fix,
      onCampus: true,
      now: start.add(const Duration(seconds: 2)),
    );
    expect(location.marker, isNotNull);
    expect(proximity.currentFix, isNull);
    expect(proximity.state, SpotState.unavailable);
  });
  test(
    'background pause freezes cosmetic motion without clearing position',
    () {
      final travel = CowboyTravel()
        ..accept(point, start, accuracy: 5, walking: false);
      travel.accept(
        CampusPoint(point.longitude + .00003, point.latitude),
        start.add(const Duration(seconds: 1)),
        accuracy: 5,
        walking: true,
      );
      final displayed = travel.position;
      expect(travel.moving, isTrue);
      travel.pause();
      expect(travel.position, same(displayed));
      expect(travel.moving, isFalse);
      expect(
        travel.accept(
          point,
          start.add(const Duration(seconds: 1)),
          accuracy: 5,
          walking: true,
        ),
        isFalse,
      );
    },
  );
}
