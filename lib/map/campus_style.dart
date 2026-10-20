import 'dart:convert';

/// Campus-only local geometry. Shallow route/ground meshes deliberately use the
/// same 3D render pass as buildings rather than relying on flat draped layers.
abstract final class CampusStyle {
  static const background = '#c9ddd3';
  static const ground = '#69ce99';
  static const road = '#487c7c';
  static const path = '#fff0bc';
  static const empty = <String, Object>{
    'type': 'FeatureCollection',
    'features': <Object>[],
  };

  static Map<String, dynamic> build(String boundary, String geography) => {
    'version': 8,
    'name': 'UTRGV-GO',
    'glyphs': 'mapbox://fonts/mapbox/{fontstack}/{range}.pbf',
    'light': {
      'anchor': 'map',
      'position': [1.5, 210, 45],
      'color': '#ffffff',
      'intensity': 0.3,
    },
    'sources': {
      'campus-boundary': {'type': 'geojson', 'data': _canonical(boundary)},
      'campus-data': {
        'type': 'geojson',
        'data': _canonical(geography),
        'attribution':
            '<a href="https://www.openstreetmap.org/copyright">© OpenStreetMap contributors</a> · <a href="https://opendatacommons.org/licenses/odbl/1-0/">ODbL</a>',
      },
      'player': {'type': 'geojson', 'data': empty},
    },
    'layers': [
      {
        'id': 'calm-background',
        'type': 'background',
        'paint': {'background-color': background},
      },
      _surface('campus-ground', 'campus-boundary', ground, 0.2),
      _surface('green-fill', 'campus-data', '#4dbb87', 0.22, kind: 'green'),
      _surface('sport-fill', 'campus-data', '#39aa8d', 0.24, kind: 'sport'),
      _surface('parking-fill', 'campus-data', '#a1c6b6', 0.26, kind: 'parking'),
      _surface('water-fill', 'campus-data', '#55c4ec', 0.28, kind: 'water'),
      _surface('roads-edge', 'campus-data', '#efd99c', 0.30, kind: 'road-edge'),
      _surface('roads', 'campus-data', road, 0.32, kind: 'road-surface'),
      _surface('paths-edge', 'campus-data', '#a5ddb0', 0.34, kind: 'path-edge'),
      _surface('paths', 'campus-data', path, 0.36, kind: 'path-surface'),
      _surface('walking-plazas', 'campus-data', path, 0.36, kind: 'path'),
      {
        'id': 'campus-buildings',
        'type': 'fill-extrusion',
        'source': 'campus-data',
        'filter': [
          '==',
          ['get', 'kind'],
          'building',
        ],
        'paint': {
          'fill-extrusion-color': ['get', 'color'],
          'fill-extrusion-height': [
            '+',
            0.4,
            ['get', 'height_m'],
          ],
          'fill-extrusion-base': 0.4,
          'fill-extrusion-opacity': 1,
          'fill-extrusion-vertical-gradient': true,
        },
      },
      {
        'id': 'campus-labels',
        'type': 'symbol',
        'source': 'campus-data',
        'minzoom': 16,
        'filter': ['has', 'label'],
        'layout': {
          'text-field': ['get', 'label'],
          'text-font': ['DIN Pro Medium', 'Arial Unicode MS Regular'],
          'text-size': 12,
          'text-max-width': 9,
          'text-padding': 16,
          'text-offset': [0, -1.2],
        },
        'paint': {
          'text-color': '#284e46',
          'text-halo-color': '#effff2',
          'text-halo-width': 1.5,
        },
      },
      {
        'id': 'player-ring',
        'type': 'circle',
        'source': 'player',
        'paint': {
          'circle-radius': 15,
          'circle-color': '#ef8538',
          'circle-opacity': 0.2,
          'circle-pitch-alignment': 'map',
        },
      },
      {
        'id': 'player-dot',
        'type': 'circle',
        'source': 'player',
        'layout': {'visibility': 'none'},
        'paint': {
          'circle-radius': 7,
          'circle-color': '#eb711d',
          'circle-stroke-width': 3,
          'circle-stroke-color': '#ffffff',
        },
      },
    ],
  };

  static Map<String, Object> _surface(
    String id,
    String source,
    String color,
    double height, {
    String? kind,
  }) => {
    'id': id,
    'type': 'fill-extrusion',
    'source': source,
    if (kind != null)
      'filter': [
        'all',
        [
          '==',
          ['get', 'kind'],
          kind,
        ],
        [
          '==',
          ['geometry-type'],
          'Polygon',
        ],
      ],
    'paint': {
      'fill-extrusion-color': color,
      'fill-extrusion-base': 0,
      'fill-extrusion-height': height,
      'fill-extrusion-opacity': 1,
      'fill-extrusion-vertical-gradient': false,
    },
  };

  /// RFC 7946 exterior CCW / holes CW, including future edits from GIS tools.
  static Map<String, dynamic> _canonical(String text) {
    final collection = jsonDecode(text) as Map<String, dynamic>;
    for (final feature in collection['features'] as List) {
      final geometry = feature['geometry'] as Map;
      final type = geometry['type'];
      if (type != 'Polygon' && type != 'MultiPolygon') continue;
      final polygons = type == 'Polygon'
          ? [geometry['coordinates']]
          : geometry['coordinates'] as List;
      for (final polygon in polygons) {
        for (var r = 0; r < polygon.length; r++) {
          final ring = polygon[r] as List;
          var area = 0.0;
          final originX = ring.first[0] as num, originY = ring.first[1] as num;
          for (var i = 1; i < ring.length; i++) {
            area +=
                ((ring[i - 1][0] as num) - originX) *
                    ((ring[i][1] as num) - originY) -
                ((ring[i][0] as num) - originX) *
                    ((ring[i - 1][1] as num) - originY);
          }
          if ((r == 0 && area < 0) || (r > 0 && area > 0)) {
            polygon[r] = ring.reversed.toList();
          }
        }
      }
    }
    return collection;
  }
}
