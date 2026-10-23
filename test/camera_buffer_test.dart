import 'dart:convert';
import 'dart:io';
import 'package:campus_app/map/campus_geography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final text = File('assets/campus/boundary.geojson').readAsStringSync();
  test('southern camera buffer does not expand playable geography', () {
    final g = CampusGeography.fromGeoJson(text);
    expect((g.south - g.cameraSouth) * 111320, closeTo(450, .001));
    expect(g.cameraNorth, g.north);
    final southTarget = CampusPoint(g.center.longitude, g.cameraSouth);
    expect(g.clampCameraCenter(southTarget).latitude, g.cameraSouth);
    expect(g.contains(southTarget), isFalse);
    expect(g.signedEdgeDistance(southTarget), lessThan(0));
  });
  test(
    'editable directional buffers use consistent native and programmatic bounds',
    () {
      final j = jsonDecode(text);
      j['features'][0]['properties']['camera_buffer_meters'] = {
        'south': 300,
        'east': 60,
      };
      final g = CampusGeography.fromGeoJson(jsonEncode(j));
      expect((g.south - g.cameraSouth) * 111320, closeTo(300, .001));
      expect(g.cameraEast, greaterThan(g.east));
      expect(
        g.clampCameraCenter(const CampusPoint(180, -90)).latitude,
        g.cameraSouth,
      );
      j['features'][0]['properties']['camera_buffer_meters'] = {'south': -1};
      expect(
        () => CampusGeography.fromGeoJson(jsonEncode(j)),
        throwsFormatException,
      );
    },
  );
}
