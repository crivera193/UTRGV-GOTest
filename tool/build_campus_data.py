"""Regenerate ODbL campus display data. Requires Python + shapely.

Usage: python tool/build_campus_data.py [cached-osm.xml]
The boundary.geojson asset is the sole editable display extent. Never overwrite it
with a bounding rectangle. No Mapbox tiles or proprietary imagery are consumed.
"""
import json
import hashlib
import math
from datetime import datetime, timezone
import re
import sys
import urllib.request
import xml.etree.ElementTree as ET
from collections import Counter
from pathlib import Path
from shapely.geometry import LineString, Polygon, mapping, shape
from shapely.geometry.polygon import orient
from shapely.ops import polygonize, unary_union, transform
from shapely.validation import make_valid

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'assets/campus'
URL = 'https://api.openstreetmap.org/api/0.6/map?bbox=-98.188,26.297,-98.160,26.319'


def main():
    raw = Path(sys.argv[1]).read_bytes() if len(sys.argv) > 1 else urllib.request.urlopen(
        urllib.request.Request(URL, headers={'User-Agent': 'UTRGV-GO-campus-data/1.0'}), timeout=60).read()
    root = ET.fromstring(raw)
    nodes = {n.get('id'): (float(n.get('lon')), float(n.get('lat'))) for n in root.findall('node')}
    ways = {w.get('id'): w for w in root.findall('way')}
    boundary = shape(json.loads((DEST / 'boundary.geojson').read_text())['features'][0]['geometry'])
    features = []
    relation_members = set()

    def emit(geom, tags, osm_id, version):
        if geom.is_empty:
            return
        kind = None
        if tags.get('building') not in (None, 'no'):
            kind = 'building'
        elif tags.get('amenity') == 'parking':
            kind = 'parking'
        elif tags.get('natural') == 'water' or tags.get('leisure') == 'swimming_pool' or tags.get('waterway'):
            kind = 'water'
        elif tags.get('leisure') in ('pitch', 'track', 'stadium'):
            kind = 'sport'
        elif tags.get('natural') in ('wood', 'scrub') or tags.get('landuse') in ('grass', 'forest') or tags.get('leisure') in ('garden', 'park'):
            kind = 'green'
        elif tags.get('highway'):
            kind = 'path' if tags['highway'] in ('footway', 'pedestrian', 'path', 'steps', 'cycleway') else 'road'
        if kind is None:
            return
        clipped = make_valid(geom).intersection(boundary)
        # Flatten collections to renderable polygon/line features, never export points.
        parts = list(clipped.geoms) if clipped.geom_type in ('GeometryCollection', 'MultiPolygon', 'MultiLineString') else [clipped]
        for part in parts:
            if part.is_empty or part.geom_type not in ('Polygon', 'LineString'):
                continue
            if kind in ('building', 'parking', 'green', 'sport') and part.geom_type != 'Polygon':
                continue
            props = {'kind': kind, 'osm_id': osm_id, 'osm_version': version}
            if kind == 'building':
                height = tags.get('height', '')
                try:
                    h = float(height.replace(' m', '').replace('m', '').strip())
                    basis = 'osm_height'
                except ValueError:
                    try:
                        h = float(tags.get('building:levels', '')) * 3.5
                        basis = 'osm_levels_x_3.5m'
                    except ValueError:
                        h, basis = 9, 'display_default_9m'
                props.update(height_m=round(max(3, min(70, h)), 1), height_basis=basis)
                # Only a few useful labels; no businesses, house numbers or road names.
                name = tags.get('name', '')
                for needle, label in [('Library', 'Library'), ('Union', 'Student Union'), ('Recreation', 'Recreation'), ('Unity', 'Unity Hall'), ('Troxel', 'Troxel Hall'), ('Performing Arts', 'Performing Arts'), ('Medicine', 'Medicine')]:
                    if needle.lower() in name.lower():
                        props['label'] = label
                        break
                props['color'] = '#ef9856' if props.get('label') in ('Student Union', 'Library') else '#e6ddc3'
            if part.geom_type == 'Polygon':
                part = orient(part, sign=1)
            features.append({'type': 'Feature', 'properties': props, 'geometry': mapping(part)})
            if part.geom_type == 'LineString' and kind in ('road', 'path'):
                # Cartographic route surfaces in local meters, not screen pixels.
                # Always re-clip AFTER buffering so a road edge cannot escape campus.
                scale_x = 111320 * math.cos(math.radians(boundary.centroid.y))
                origin_x, origin_y = boundary.centroid.x, boundary.centroid.y
                def to_m(x, y, z=None): return ((x-origin_x)*scale_x, (y-origin_y)*111320)
                def to_geo(x, y, z=None): return (x/scale_x+origin_x, y/111320+origin_y)
                width = 3.0 if kind == 'path' else (5.5 if tags.get('highway') == 'service' else 9.0)
                if tags.get('highway') == 'pedestrian': width = 4.0
                line_m = transform(to_m, part)
                for suffix, extra in [('edge', 1.3 if kind == 'road' else 0.55), ('surface', 0)]:
                    surface = transform(to_geo, line_m.buffer(width/2 + extra, cap_style=2, join_style=2)).intersection(boundary)
                    pieces = surface.geoms if surface.geom_type in ('MultiPolygon', 'GeometryCollection') else [surface]
                    for piece in pieces:
                        if piece.geom_type == 'Polygon' and not piece.is_empty:
                            features.append({'type':'Feature', 'properties':{
                                'kind':kind+'-'+suffix, 'osm_id':osm_id, 'osm_version':version,
                                'display_width_m':width+2*extra}, 'geometry':mapping(orient(piece, sign=1))})

    for rel in root.findall('relation'):
        tags = {t.get('k'): t.get('v') for t in rel.findall('tag')}
        if tags.get('type') != 'multipolygon':
            continue
        rings = {'outer': [], 'inner': []}
        used = []
        for m in rel.findall('member'):
            if m.get('type') == 'way' and m.get('ref') in ways:
                coords = [nodes[n.get('ref')] for n in ways[m.get('ref')].findall('nd')]
                if len(coords) > 1:
                    rings['inner' if m.get('role') == 'inner' else 'outer'].append(LineString(coords))
                    used.append(m.get('ref'))
        outer = unary_union(list(polygonize(rings['outer'])))
        inner = unary_union(list(polygonize(rings['inner'])))
        if not outer.is_empty:
            emit(outer.difference(inner), tags, 'relation/' + rel.get('id'), rel.get('version'))
            if any(k in tags for k in ('building', 'landuse', 'natural', 'amenity', 'leisure')):
                relation_members.update(used)
    for osm_id, w in ways.items():
        if osm_id in relation_members:
            continue
        tags = {t.get('k'): t.get('v') for t in w.findall('tag')}
        coords = [nodes[n.get('ref')] for n in w.findall('nd')]
        if len(coords) < 2:
            continue
        is_area = coords[0] == coords[-1] and len(coords) >= 4 and (tags.get('area') == 'yes' or any(k in tags for k in ('building', 'landuse', 'natural', 'leisure', 'amenity')))
        emit(Polygon(coords) if is_area else LineString(coords), tags, 'way/' + osm_id, w.get('version'))
    collection = {'type': 'FeatureCollection', 'license': 'ODbL-1.0', 'attribution': '© OpenStreetMap contributors', 'features': features}
    text = json.dumps(collection, separators=(',', ':'))
    # Stable 7-place coordinates (~1cm) keep the asset small without altering clipping.
    text = re.sub(r'-?\d+\.\d{8,}', lambda m: str(round(float(m.group()), 7)), text)
    (DEST / 'features.geojson').write_text(text + '\n', encoding='utf-8')
    retrieved = datetime.fromtimestamp(Path(sys.argv[1]).stat().st_mtime, timezone.utc).isoformat() if len(sys.argv) > 1 else datetime.now(timezone.utc).isoformat()
    summary = {'source': URL, 'retrieved_utc': retrieved, 'generated_utc': datetime.now(timezone.utc).isoformat(),
               'source_sha256': hashlib.sha256(raw).hexdigest(),
               'counts': dict(Counter(f['properties']['kind'] for f in features)),
               'height_basis': dict(Counter(f['properties']['height_basis'] for f in features if f['properties']['kind'] == 'building'))}
    (DEST / 'provenance.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(json.dumps(summary, indent=2))


if __name__ == '__main__':
    main()
