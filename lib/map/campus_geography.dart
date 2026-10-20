import 'dart:convert';
import 'dart:math' as math;

/// WGS84 throughout. Local meter conversion is used only for GPS uncertainty.
class CampusPoint {
  const CampusPoint(this.longitude, this.latitude);
  final double longitude;
  final double latitude;
  List<double> get coordinates => [longitude, latitude];
}

class CampusGeography {
  CampusGeography.fromGeoJson(String text) {
    final features =
        (jsonDecode(text) as Map<String, dynamic>)['features'] as List;
    for (final feature in features) {
      final geometry = feature['geometry'];
      final polygons = geometry['type'] == 'Polygon'
          ? [geometry['coordinates']]
          : geometry['coordinates'] as List;
      for (final polygon in polygons) {
        rings.add([
          for (final ring in polygon)
            [
              for (final p in ring)
                CampusPoint((p[0] as num).toDouble(), (p[1] as num).toDouble()),
            ],
        ]);
      }
    }
    final points = rings.expand((p) => p.first);
    west = points.map((p) => p.longitude).reduce(math.min);
    east = points.map((p) => p.longitude).reduce(math.max);
    south = points.map((p) => p.latitude).reduce(math.min);
    north = points.map((p) => p.latitude).reduce(math.max);
  }

  final List<List<List<CampusPoint>>> rings = [];
  late final double west, east, south, north;
  CampusPoint get center => CampusPoint((west + east) / 2, (south + north) / 2);
  Iterable<CampusPoint> get outerPoints => rings.expand((p) => p.first);

  bool contains(CampusPoint point) => rings.any(
    (polygon) =>
        _inside(point, polygon.first) &&
        !polygon.skip(1).any((hole) => _inside(point, hole)),
  );

  static bool _inside(CampusPoint p, List<CampusPoint> ring) {
    var inside = false;
    for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final a = ring[i], b = ring[j];
      if ((a.latitude > p.latitude) != (b.latitude > p.latitude) &&
          p.longitude <
              (b.longitude - a.longitude) *
                      (p.latitude - a.latitude) /
                      (b.latitude - a.latitude) +
                  a.longitude) {
        inside = !inside;
      }
    }
    return inside;
  }

  /// Positive inside, negative outside. Handles polygon holes as well as islands.
  double signedEdgeDistance(CampusPoint point) {
    var closest = double.infinity;
    final scaleX = 111320 * math.cos(point.latitude * math.pi / 180);
    const scaleY = 111320.0;
    for (final ring in rings.expand((p) => p)) {
      for (var i = 1; i < ring.length; i++) {
        final ax = (ring[i - 1].longitude - point.longitude) * scaleX;
        final ay = (ring[i - 1].latitude - point.latitude) * scaleY;
        final bx = (ring[i].longitude - point.longitude) * scaleX;
        final by = (ring[i].latitude - point.latitude) * scaleY;
        final dx = bx - ax, dy = by - ay;
        final length = dx * dx + dy * dy;
        final t = length == 0
            ? 0.0
            : (-(ax * dx + ay * dy) / length).clamp(0.0, 1.0);
        closest = math.min(
          closest,
          math.sqrt(math.pow(ax + t * dx, 2) + math.pow(ay + t * dy, 2)),
        );
      }
    }
    return contains(point) ? closest : -closest;
  }

  CampusPoint clampCameraCenter(CampusPoint point) => CampusPoint(
    point.longitude.clamp(west, east),
    point.latitude.clamp(south, north),
  );

  static double distance(CampusPoint a, CampusPoint b) {
    final x =
        (a.longitude - b.longitude) *
        111320 *
        math.cos(a.latitude * math.pi / 180);
    final y = (a.latitude - b.latitude) * 111320;
    return math.sqrt(x * x + y * y);
  }
}
