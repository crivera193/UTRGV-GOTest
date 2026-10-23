import 'package:flutter/widgets.dart';
import 'campus_geography.dart';

/// Ephemeral view state only. GPS fixes and combat eligibility are never saved.
class MapViewState {
  const MapViewState({
    required this.center,
    required this.zoom,
    required this.overview,
    required this.following,
    required this.locationEnabled,
  });
  final CampusPoint center;
  final double zoom;
  final bool overview, following, locationEnabled;
}

class RestorableMapView extends RestorableValue<MapViewState?> {
  @override
  MapViewState? createDefaultValue() => null;
  @override
  void didUpdateValue(MapViewState? oldValue) => notifyListeners();
  @override
  MapViewState? fromPrimitives(Object? data) {
    if (data is! Map || data['version'] != 1) return null;
    final lon = data['longitude'], lat = data['latitude'], zoom = data['zoom'];
    if (lon is! num ||
        lat is! num ||
        zoom is! num ||
        !lon.isFinite ||
        !lat.isFinite ||
        !zoom.isFinite ||
        lon.abs() > 180 ||
        lat.abs() > 85 ||
        zoom < 0 ||
        zoom > 22 ||
        data['overview'] is! bool ||
        data['following'] is! bool ||
        data['locationEnabled'] is! bool) {
      return null;
    }
    return MapViewState(
      center: CampusPoint(lon.toDouble(), lat.toDouble()),
      zoom: zoom.toDouble(),
      overview: data['overview'],
      following: data['following'],
      locationEnabled: data['locationEnabled'],
    );
  }

  @override
  Object? toPrimitives() {
    final v = value;
    return v == null
        ? null
        : <String, Object>{
            'version': 1,
            'longitude': v.center.longitude,
            'latitude': v.center.latitude,
            'zoom': v.zoom,
            'overview': v.overview,
            'following': v.following,
            'locationEnabled': v.locationEnabled,
          };
  }
}
