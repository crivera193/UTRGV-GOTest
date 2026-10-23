import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_app/map/campus_geography.dart';
import 'package:campus_app/map/campus_location.dart';
import 'package:campus_app/map/campus_style.dart';
import 'package:campus_app/map/campus_presentation.dart';

void main() {
  final boundary = File('assets/campus/boundary.geojson').readAsStringSync();
  final data = File('assets/campus/features.geojson').readAsStringSync();
  final geography = CampusGeography.fromGeoJson(boundary);
  final now = DateTime.utc(2026, 10, 19, 12);
  const library = CampusPoint(-98.1740, 26.3067);

  test(
    'display extent includes main campus, residences and both athletic areas',
    () {
      for (final p in [
        library,
        const CampusPoint(-98.17775, 26.31023), // recreation
        const CampusPoint(-98.17885, 26.30917), // Village F
        const CampusPoint(-98.18316, 26.30882), // soccer / track
        const CampusPoint(-98.17574, 26.31233), // baseball
        const CampusPoint(-98.17481, 26.31356), // performance center area
        const CampusPoint(-98.1752, 26.3145), // northern practice grounds
        const CampusPoint(-98.1672, 26.3086), // east campus parking
      ]) {
        expect(geography.contains(p), isTrue, reason: '${p.coordinates}');
      }
      for (final p in [
        const CampusPoint(-98.165, 26.303), // downtown direction
        const CampusPoint(
          -98.178,
          26.312,
        ), // private apartments north of recreation
        const CampusPoint(-98.1826, 26.31064), // neighboring ESC building
        const CampusPoint(-97.5, 25.9), // Brownsville
      ]) {
        expect(geography.contains(p), isFalse);
      }
    },
  );

  test(
    'every exported footprint/path is clipped to campus within rounding tolerance',
    () {
      var checked = 0;
      void check(dynamic node) {
        if (node is List && node.isNotEmpty && node.first is num) {
          final p = CampusPoint(
            (node[0] as num).toDouble(),
            (node[1] as num).toDouble(),
          );
          expect(geography.signedEdgeDistance(p), greaterThanOrEqualTo(-0.02));
          checked++;
        } else if (node is List) {
          for (final child in node) {
            check(child);
          }
        }
      }

      for (final f in (jsonDecode(data)['features'] as List)) {
        check(f['geometry']['coordinates']);
      }
      expect(checked, greaterThan(5000));
    },
  );

  test('camera targets are constrained in every direction', () {
    for (final p in [
      const CampusPoint(-180, -90),
      const CampusPoint(180, 90),
      library,
    ]) {
      final clamped = geography.clampCameraCenter(p);
      expect(
        clamped.longitude,
        inInclusiveRange(geography.cameraWest, geography.cameraEast),
      );
      expect(
        clamped.latitude,
        inInclusiveRange(geography.cameraSouth, geography.cameraNorth),
      );
    }
  });

  test(
    'fresh on-campus GPS draws a marker; city GPS never substitutes a position',
    () {
      final policy = CampusLocationPolicy(geography);
      policy.accept(CampusFix(library, 5, now), now);
      expect(policy.state, CampusGpsState.onCampus);
      expect(policy.marker, isNotNull);
      policy.accept(
        CampusFix(
          const CampusPoint(-98.16, 26.3),
          5,
          now.add(const Duration(seconds: 1)),
        ),
        now.add(const Duration(seconds: 1)),
      );
      expect(policy.state, CampusGpsState.outside);
      expect(policy.marker, isNull);
    },
  );

  test('poor, stale, future and duplicate GPS fixes do not move player', () {
    final policy = CampusLocationPolicy(geography);
    policy.accept(CampusFix(library, 5, now), now);
    final marker = policy.marker;
    policy.accept(CampusFix(const CampusPoint(-98.1739, 26.3067), 5, now), now);
    expect(policy.marker, same(marker));
    policy.accept(
      CampusFix(library, 70, now.add(const Duration(seconds: 1))),
      now.add(const Duration(seconds: 1)),
    );
    expect(policy.state, CampusGpsState.inaccurate);
    expect(policy.marker, isNull);
    policy.accept(
      CampusFix(library, 5, now.add(const Duration(seconds: 2))),
      now.add(const Duration(seconds: 2)),
    );
    policy.expire(now.add(const Duration(seconds: 24)));
    expect(policy.state, CampusGpsState.stale);
    expect(policy.marker, isNull);
    policy.accept(
      CampusFix(library, 5, now.add(const Duration(minutes: 10))),
      now,
    );
    expect(policy.state, CampusGpsState.stale);
    policy.accept(
      CampusFix(library, 5, now.add(const Duration(seconds: 25))),
      now.add(const Duration(seconds: 25)),
    );
    expect(policy.state, CampusGpsState.onCampus);
  });

  test(
    'boundary uncertainty holds status and hides out-of-boundary points',
    () {
      final policy = CampusLocationPolicy(geography);
      policy.accept(CampusFix(library, 5, now), now);
      // East edge of the mapped campus near the southern entrance.
      final edge = geography.rings.first.first.first;
      policy.accept(
        CampusFix(edge, 20, now.add(const Duration(seconds: 1))),
        now.add(const Duration(seconds: 1)),
      );
      expect(
        policy.state,
        anyOf(CampusGpsState.onCampus, CampusGpsState.boundary),
      );
      if (policy.marker != null) {
        expect(geography.contains(policy.marker!), isTrue);
      }
      policy.clear(CampusGpsState.denied);
      expect(policy.marker, isNull);
    },
  );

  test(
    'stationary GPS noise does not invent movement and smoothing stays inside',
    () {
      final policy = CampusLocationPolicy(geography);
      policy.accept(CampusFix(library, 5, now), now);
      policy.accept(
        CampusFix(
          const CampusPoint(-98.173999, 26.306701),
          5,
          now.add(const Duration(seconds: 1)),
        ),
        now.add(const Duration(seconds: 1)),
      );
      expect(policy.marker!.longitude, library.longitude);
      final destination = const CampusPoint(-98.1739, 26.3067);
      policy.accept(
        CampusFix(destination, 5, now.add(const Duration(seconds: 2))),
        now.add(const Duration(seconds: 2)),
      );
      expect(policy.marker!.longitude, greaterThan(library.longitude));
      expect(policy.marker!.longitude, lessThan(destination.longitude));
      expect(geography.contains(policy.marker!), isTrue);
    },
  );

  test(
    'reconstructed style has no external map data or duplicate building layers',
    () {
      final first = CampusStyle.build(boundary, data);
      final reload = CampusStyle.build(boundary, data);
      expect(jsonEncode(first), jsonEncode(reload));
      expect(reload.containsKey('imports'), isFalse);
      expect(reload.containsKey('terrain'), isFalse);
      final sources = reload['sources'] as Map;
      expect(sources.length, 3);
      for (final source in sources.values) {
        expect(source['type'], 'geojson');
        expect(source['data'], isA<Map>());
        expect(source.containsKey('url'), isFalse);
        expect(source.containsKey('tiles'), isFalse);
      }
      final layers = reload['layers'] as List;
      expect(layers.map((l) => l['id']).toSet().length, layers.length);
      expect(layers.where((l) => l['id'] == 'campus-buildings').length, 1);
      // Route/ground meshes are sub-meter display surfaces, not more buildings.
      for (final layer in layers.where(
        (l) => l['type'] == 'fill-extrusion' && l['id'] != 'campus-buildings',
      )) {
        expect(layer['paint']['fill-extrusion-height'], lessThan(0.4));
      }
      expect(layers.first['paint']['background-color'], CampusStyle.background);
      expect(sources['player']['data']['features'], isEmpty);
    },
  );

  test(
    'reference presentation starts within academic core and leaves room ahead',
    () {
      expect(geography.contains(CampusPresentation.academicCore), isTrue);
      expect(CampusPresentation.explorationZoom, inInclusiveRange(16.5, 17.5));
      expect(CampusPresentation.pitch, inInclusiveRange(50, 60));
      expect(CampusPresentation.explorationTopPadding(700), greaterThan(100));
      expect(CampusPresentation.explorationTopPadding(300), lessThan(100));
    },
  );

  test('overview and GPS following retain the chosen exploration zoom', () {
    final camera = CampusCameraSession()..initialize(390);
    final initial = camera.explorationZoom;
    expect(initial, inInclusiveRange(16, 17.5));
    camera.rememberZoom(18.2);
    camera.viewCampus();
    camera.rememberZoom(14.1);
    expect(camera.explorationZoom, 18.2);
    camera.explore();
    expect(camera.explorationZoom, 18.2);
    camera.rememberZoom(17.8);
    expect(camera.explorationZoom, 17.8);
    camera.rememberZoom(double.nan);
    expect(camera.explorationZoom, 17.8);
    expect(
      CampusPresentation.zoomForViewport(844),
      greaterThan(CampusPresentation.zoomForViewport(390)),
    );
  });

  test('rendered polygons use canonical winding for native roof meshes', () {
    final style = CampusStyle.build(boundary, data);
    final sources = style['sources'] as Map;
    var polygons = 0;
    for (final source in sources.values) {
      for (final feature in source['data']['features']) {
        final geometry = feature['geometry'];
        if (geometry['type'] != 'Polygon') continue;
        final rings = geometry['coordinates'] as List;
        for (var r = 0; r < rings.length; r++) {
          final ring = rings[r] as List;
          var area = 0.0;
          final x = ring.first[0] as num, y = ring.first[1] as num;
          for (var i = 1; i < ring.length; i++) {
            area +=
                ((ring[i - 1][0] as num) - x) * ((ring[i][1] as num) - y) -
                ((ring[i][0] as num) - x) * ((ring[i - 1][1] as num) - y);
          }
          expect(r == 0 ? area : -area, greaterThan(0));
        }
        polygons++;
      }
    }
    expect(polygons, greaterThan(1000));
  });
}
