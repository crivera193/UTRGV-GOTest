import 'dart:convert';

/// Entire style is rebuilt from local, pre-clipped assets on each load. There
/// are no default basemap imports, tiles, terrain, outside labels or buildings.
abstract final class CampusStyle {
  static const background = '#e8eee7';
  static const empty = <String, Object>{
    'type': 'FeatureCollection',
    'features': <Object>[],
  };

  static Map<String, dynamic> build(String boundary, String geography) => {
    'version': 8,
    'name': 'UTRGV campus exploration',
    'glyphs': 'mapbox://fonts/mapbox/{fontstack}/{range}.pbf',
    'light': {
      'anchor': 'map',
      'position': [1.5, 210, 40],
      'color': '#fff3d6',
      'intensity': 0.45,
    },
    'sources': {
      'campus-boundary': {'type': 'geojson', 'data': jsonDecode(boundary)},
      'campus-data': {
        'type': 'geojson',
        'data': jsonDecode(geography),
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
      {
        'id': 'campus-ground',
        'type': 'fill',
        'source': 'campus-boundary',
        'paint': {'fill-color': '#94d273'},
      },
      _fill('green', '#71be74'),
      _fill('sport', '#56b58b'),
      _fill('parking', '#bfccbb'),
      _fill('water', '#55bce0'),
      _line('water-lines', 'water', '#55bce0', 3),
      _line('roads-edge', 'road', '#aab9a9', 8),
      _line('roads', 'road', '#d2d9c9', 6),
      _line('paths-edge', 'path', '#b2bf89', 4),
      _line('paths', 'path', '#fff2cc', 2.5),
      {
        'id': 'campus-edge',
        'type': 'line',
        'source': 'campus-boundary',
        'paint': {
          'line-color': '#608f70',
          'line-width': 1.5,
          'line-opacity': 0.65,
        },
      },
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
          'fill-extrusion-height': ['get', 'height_m'],
          'fill-extrusion-base': 0,
          'fill-extrusion-opacity': 1,
          'fill-extrusion-vertical-gradient': true,
        },
      },
      {
        'id': 'campus-labels',
        'type': 'symbol',
        'source': 'campus-data',
        'minzoom': 15,
        'filter': ['has', 'label'],
        'layout': {
          'text-field': ['get', 'label'],
          'text-font': ['DIN Pro Medium', 'Arial Unicode MS Regular'],
          'text-size': 12,
          'text-max-width': 9,
          'text-padding': 12,
          'text-offset': [0, -1.2],
        },
        'paint': {
          'text-color': '#334f3f',
          'text-halo-color': '#f9ffe9',
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

  static Map<String, Object> _fill(String kind, String color) => {
    'id': '$kind-fill',
    'type': 'fill',
    'source': 'campus-data',
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
    'paint': {'fill-color': color},
  };
  static Map<String, Object> _line(
    String id,
    String kind,
    String color,
    double width,
  ) => {
    'id': id,
    'type': 'line',
    'source': 'campus-data',
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
        'LineString',
      ],
    ],
    'layout': {'line-join': 'round', 'line-cap': 'butt'},
    'paint': {
      'line-color': color,
      'line-width': [
        'interpolate',
        ['linear'],
        ['zoom'],
        14,
        width * 0.4,
        18,
        width * 1.6,
      ],
    },
  };
}
