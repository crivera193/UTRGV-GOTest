# Campus exploration map

Implemented October 19, 2026 for Flutter 3.47.7, mapbox_maps_flutter 2.26.0,
native Mapbox 11.26.0 and geolocator 14.1.1. No Mapbox Studio publication or
account-side change is needed. Existing ACCESS_TOKEN configuration is retained.

## Extent and data

The sole editable display extent is [boundary.geojson](../assets/campus/boundary.geojson).
It includes the main academic campus, east/south campus parking, The Village,
Unity/Troxel residence areas, recreation, western soccer/track grounds and their
access/parking, and the northern baseball, pavilion/performance/practice area.
Other cities, separately listed off-campus clinics/facilities and the separate
Robert & Janet Vackar football stadium are excluded.

Coverage reference: [UTRGV official Edinburg map](https://www.utrgv.edu/ucentral/_files/documents/campus-maps/utrgv-edinburg-map.pdf),
read as a facility/extent reference, never as coordinate imagery or a property
survey. Northern athletics location was cross-checked with
[UTRGV's performance-center opening announcement](https://goutrgv.com/news/2025/9/11/football-utrgv-athletics-to-unveil-vaqueros-performance-center-to-public-sept-19.aspx).

Geographic source: [OpenStreetMap API bounded extract](https://api.openstreetmap.org/api/0.6/map?bbox=-98.188,26.297,-98.160,26.319),
downloaded directly, with source way/relation IDs and versions preserved. The
boundary begins with OSM university way 276326924 and northern parking ways
51323426/51323427. Campus display extensions west and north follow the mapped
athletic/road arrangement and official coverage reference. These extensions are
approximate display extents, not verified cadastral/property boundaries. Review
the northern practice-field perimeter on site before using it for gameplay gates.
The former app's faction polygons and small creation rectangle are not used.

The bundled adapted database is under [ODbL 1.0](https://opendatacommons.org/licenses/odbl/1-0/),
with [OSM attribution](https://www.openstreetmap.org/copyright). The Mapbox logo,
attribution/telemetry control remain; the source adds linked OSM/ODbL attribution.
No Mapbox tiles were extracted or cached as source data. PDF graphics and
proprietary imagery are not bundled.

`features.geojson` currently contains 93 rendered building footprint parts,
43 parking polygons, 21 sports shapes, 666 paths, 278 roads, 6 water shapes and
2 other green shapes. Campus ground supplies the continuous green base.
All features are geometrically intersected with the boundary before export,
including polygon holes and line endpoints. Heights are display estimates:
82 footprint parts use 9 m; 11 use mapped building levels times 3.5 m. No measured
height tags were available. This is not surveyed height information.

Data gaps: OSM does not contain all newer northern athletics buildings/practice
field details. Their grounds are included, but no invented rectangular building
substitutes are drawn. Footprints/paths and building names may lag current campus
construction. Library/Union have warm orange accents; selected useful building
labels are shown from zoom 16. Detailed architectural models are outside this pass.

Regenerate with Python and Shapely: `python tool/build_campus_data.py`.
An optional XML argument reuses a previously downloaded bounded OSM extract.
Edit the boundary first; regeneration never replaces it. `provenance.json`
records source URL/hash, retrieval time, counts and height bases. The raw extract,
PDF reference and intermediate output stay in ignored `tmp/campus`.

## Rendering, camera and GPS

`lib/map/campus_style.dart` creates one complete custom style, using only inline
local GeoJSON, an opaque calm background, green grounds, light paths, subdued
roads/parking, blue water and shaded solid extrusions. No basemap imports, raster
or vector tile sources, terrain or surrounding labels exist. A local file URI is
supplied at native map construction, behind an opaque loading/error cover. Style
reload uses the same JSON, restores the filtered player source and preserves
camera bounds. There is no temporary unrestricted basemap or flat outside mask.
Mapbox font glyphs are the only map content fetched online; glyph errors may omit
labels but leave local geography usable.

The native camera center is constrained to the campus extent's bounding box;
in empty corners only the calm background appears. Pitch is fixed at 55 degrees,
rotation disabled, maximum zoom 19.5. View campus fits all exterior boundary
vertices with screen/UI padding using the installed SDK's camera fit API. The
fit becomes the minimum zoom; it is recalculated on viewport size changes.
Gestures are suspended during fit calculation, with campus center/pitch bounds
kept active. Every programmatic move goes through one bounded gateway. No visible
escape/snapback correction loop is used.

Follow me requests existing foreground location permission and starts Geolocator
updates only on demand. View campus and manual pan/zoom suspend following.
Returning to campus requires Follow me to restore following. Background/pause
cancels subscriptions/timer and hides the old marker; resume requests fresh data.
No background tracking, location database writes or location history is added.

GPS older than 20 seconds, more than 5 seconds in the future, or worse than 40 m
accuracy is hidden. Boundary classification uses uncertainty margins (at least
8 m to enter, 12 m to exit, or reported accuracy when larger). An outside fix is
never moved to a false campus coordinate. Near-edge uncertain fixes receive a
clear message; outside positions stop following and remain hidden. A 3 m/accuracy
deadband and interpolation between actual accepted points reduce jitter without
predicted movement. The existing cowboy and Flame integration are retained. This
presentation pass preserves their animation, smoothing and travel systems.

## Verification and review boundary

Focused tests cover representative campus areas/exclusions, every exported
coordinate within clipping tolerance, bounded camera centers, on/off-campus GPS,
uncertainty, stale/poor/future/duplicate readings, stationary jitter and complete
style reconstruction without default sources or duplicated extrusions.
`dart run tool/export_campus_style.dart` exports the exact runtime style for
Mapbox's `gl-style-validate` tool. Automated style reconstruction is not a native
style-reload interaction test.

Per owner instruction this task performs no input automation, touch testing,
recording, installation or live deployment. Native app captures of this changed
map are therefore unavailable: the existing installed app contains older source.
The compiled Android artifact is for manual preview installation/review, not a
verified visual result or release. iOS compilation and real on-campus GPS remain
unverified. Review overview coverage, tilted close-up, boundary/off-campus message
and logo/attribution layout on native hardware before accepting the appearance.

Original map baseline (4425a9d): Flutter analysis reported no issues, all 14 map/foundation
tests passed, Mapbox's style validator accepted the exported runtime JSON, and
the Android x86_64 debug build succeeded. Its packaged campus assets were compared
byte-for-byte with source. The saved, uninstalled artifact is
`output/campus-map/UTRGV-GO-campus-map-x86_64-debug.apk` (ignored), SHA-256
`7c88d6303556d3423b379a460d3b9074acd3a910c030c384acdff81a6b1046b9`.
The full working-folder test run additionally encountered a failing, untracked
cowboy sprite-loading test during concurrent player work. That separate work
was preserved and is not part of the checked map baseline or artifact.


## Reference presentation and UTRGV-GO titles

The owner supplied two Pokemon GO reference images and the current app screenshot.
A read-only native capture reproduced isolated buildings and extremely faint ground.
The installed cached style contained the campus polygon, route features, opaque
colors and no outside mask: the source data was present. SwiftShader/GFXSTREAM
logged GL_INVALID_VALUE; this suggests a driver issue but does not prove the exact
failed shader. No unsupported claim of a confirmed GPU root cause is made.

The revised style uses shallow fill-extrusion meshes for ground, parking, sports,
water and buffered route surfaces, alongside the existing building footprints.
Ground offsets of 0.20-0.36 m are rendering offsets only. Buildings retain their
original display heights above a 0.40 m base, with warm cream roofs/walls, white
lighting and sparse orange accents. Polygon winding is canonicalized at load.

Paths/roads keep OSM centerlines and connections. Cartographic widths are 3 m for
paths, 4 m for pedestrian areas, 5.5 m for service roads and 9 m for other roads,
with restrained edges. Buffered polygons are clipped again AFTER widening; nothing
extends into the city. The asset adds 278 road surfaces/edges and 661 path surfaces/
edges. Five mapped walking plazas also receive the path color. No routes, new
buildings or land-use areas are invented. Data/height gaps above are unchanged.

CampusPresentation targets approximately 220 m across the padded viewport at the
focus, with an initial zoom between 16 and 17.5 (about 16.7 at 390 logical pixels).
Pitch is 55 degrees. Exploration padding places the geographic player lower:
top 35% of map height, bottom 100 logical pixels; short landscape uses 80/64.
The non-follow initial view uses the actual academic core, not a false player.
CampusCameraSession retains selected exploration zoom across ordinary GPS updates
and Follow me. View campus deliberately fits the full extent without overwriting
that zoom. Pinch and explicit + / - controls remain bounded. The compact map header,
app-bar product titles and native/web/window display names use UTRGV-GO. Package,
auth/session and bundle identifiers are retained. Existing cowboy/Flame behavior
and concurrent source edits are preserved.

The new source is NOT installed or deployed under the owner's explicit limit.
The baseline capture diagnoses the old result; it is not a revised-style capture.
New player-follow, closer zoom and overview native captures remain unavailable
until manual installation/review is authorized. A build is not visual acceptance.
