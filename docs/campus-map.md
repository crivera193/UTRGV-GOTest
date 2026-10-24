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

## Tappable building labels — October 21, 2026

Owner selected short labels plus tap-to-name. `assets/campus/building-labels.json`
joins the existing named campus polygons and cached OSM tags to current display
footprints. There are 78 footprint-part labels (69 named, 9 explicitly unverified
building IDs). Roof/bridge-only structures are excluded. Multipart buildings have
distinct part IDs. Polygon area centroids are used when inside the footprint;
concave/courtyard cases use an interior pole of inaccessibility. Every stored
anchor passes containment against its exact rendered polygon, including holes.

Mapbox native point annotations use center anchors, viewport-facing badges and
symbol-z-elevate for actual roof placement. No screen offsets or Flutter camera
projection queue positions the labels. Badge size stays fixed across zooms;
native collision handling hides crowded badges without displacing their anchors.
Tap opens the full name/code card; its close button preserves the map camera.
The former sparse full-name symbol layer is replaced. No building geometry,
animation, GPS policy or backend is changed by this feature.

Names/codes were checked where available against UTRGV's facilities inventory:
https://www.utrgv.edu/campus-operations/departments/campus-facilities-operations/building/index.htm
Regenerate with `python tool/build_building_labels.py PATH_TO_CACHED_OSM_XML`.
Nine unnamed minor footprints retain neutral IDs; do not invent their names.

Validation: analysis clean, 58 tests passed. Android x86_64 preview build 8013,
installed package version 12013 on UTRGV_GO_Preview/emulator-5554, 1080x2400.
Signing matched the installed app; in-place update preserved the signed-in session.
Installed APK hash matched the fresh build:
fb69475e6fa520cebf2fac70b015ddb7f816218a96fe9495e0114f0aee132145.
Native tap/close and zoom-in, zoom-out, return-to-original checks passed; badges
remain centered on their roofs at each scale. Evidence is in ignored
`tmp/building-labels/`, including `zoom-and-tap.mp4`. No GPS override was needed.
Shared camera/cowboy repairs remain separate uncommitted work. Feature branch:
`codex/building-labels`; owner visual acceptance/main integration remain pending.


## Nearby dragon and flower — October 23, 2026 (superseded below)

Each existing decorative landmark now uses the cats' shared raw-GPS arrival policy independently: enter within 30 m for 2 seconds, remain visible until beyond 45 m, require accuracy at most 20 m and a fix no older than 10 seconds. Stale/disabled GPS, leaving campus, pausing and opening a game hide decorations. Camera panning alone cannot reveal them. Existing artwork, landmark coordinates and zoom visibility remain unchanged. The reusable gate accepts the landmark collection without per-landmark behavior. The pre-existing bundled decoration catalog remains source-defined; this scoped change does not migrate it to the live game-point catalog or alter Supabase combat.

Analysis is clean; five focused proximity/cat tests passed, including independent arrival, departure, stale/poor GPS and off-campus rejection. Android synthetic GPS checks on emulator-5554 (1080×2400) verified both hidden far away, Dragon near CS only, Flower near MED only, and both hidden again after leaving. Reproduce with `test_driver/campus_creatures_flow.dart` against the separate QA driver session. [Dragon](evidence/campus-creatures/dragon-near.png), [flower](evidence/campus-creatures/flower-near.png), [far away](evidence/campus-creatures/far.png).

Normal preview restored in place as build 12035/versionCode 16035, signing unchanged. The pulled installed APK matches fresh SHA-256 `b8759c01c7827c6bc5fc837738c849431ff36457cc8f38f829bf69bfea176fa6`. Real outdoor GPS and owner visual acceptance remain unverified. Shared uncommitted camera/cowboy work is preserved separately; source changes stay on `codex/campus-creatures` for review.


## Southern camera breathing room — October 23, 2026

`boundary.geojson` now has editable `camera_buffer_meters` properties (west/east/south/north; absent directions mean zero). South is 450 m, tuned on the actual preview to keep SWOT clear of the bottom controls at close and wider exploration zooms. Other directions remain unchanged. Both native Mapbox bounds and programmatic camera clamping use these limits. This is camera-only space: campus rendering, polygon membership, GPS eligibility, game points and Supabase data are unchanged. Invalid negative/non-finite settings fail loading explicitly.

Analysis is clean and 13 focused camera/geography/GPS tests passed. Native QA at SWOT on emulator-5554, 1080×2400, exercised following, two zoom-out steps and southward panning. Visual review confirmed the whole building clears the controls at both zooms. An initial 150 m trial was insufficient at the wider zoom and was replaced before delivery. [Close view](evidence/camera-buffer/swot-close.png), [wide view](evidence/camera-buffer/swot-wide.png). Reproduce with `test_driver/camera_buffer_flow.dart` and the isolated QA driver session; its screenshots require visual inspection.

Normal preview restored in place as build 12039/versionCode 16039. Installed bytes match the fresh APK SHA-256 `cebe67abe65b91ec05e1c3b36d2d33397564ce373bdd55da53f05a388a44a976`; signing and account data are preserved. Source stays on `codex/campus-map` for owner review. Existing unrelated camera/cowboy edits remain separate.

## Map controls cleanup — October 23, 2026

Removed the Game points and View campus buttons, their point-list bottom sheet, and the obsolete multi-button layout. Points still open their existing detail/attack card by tapping the map marker. Follow me remains centered at the bottom. Internal viewport fitting remains necessary for initial bounds and resize and is named accordingly; it has no separate overview control.

Flutter analysis is clean and 20 focused campus-map, lifecycle and GPS tests passed. Normal emulator build 12048/versionCode 16048 was installed in place with unchanged signing. At 1080×2400, both buttons are absent; tapping Follow me centers the map and displays the cowboy and Following control. Installed APK bytes match the fresh artifact SHA-256 `a91766c0a291ddd80c021493a9e25f750cb389d088140c0e4eddd1e0357ff714`. Existing unrelated camera/cowboy work is preserved separately. No Supabase changes were needed.

## Always-visible decorations — October 23, 2026

Owner reversed the proximity behavior: dragon, flower and cats now render whenever their locations are in the map viewport, including before enabling GPS and at overview zoom. Removed both decoration proximity classes, their distance/accuracy/dwell/expiry settings, GPS subscriptions to those gates and obsolete tests. Startup, camera changes and foreground recovery project decorations independently of GPS; background/game screens still stop/hide map animation. Attack-point proximity rules are unchanged. Existing artwork and source-defined landmark coordinates are preserved; no live point or Supabase configuration changed.

Analysis is clean; 17 focused cat/creature animation, GPS-resume and attack-proximity tests passed. Normal emulator build 12050/versionCode 16050 installed in place with unchanged signing. A native 1080×2400 map check showed all three decorations while location was not enabled, after zooming out. [Native map evidence](evidence/campus-creatures/always-visible.png). The old native driver flow now checks browsing while GPS stays distant; it was updated and analyzed, but not run in this pass. Installed APK SHA-256 matches the fresh artifact: `4586e5134c5b5365cc7235707d89d028e568d48fbc0da26bfcd5a793fb8b271e`. Phone installation was not repeated for this change. Unrelated camera/cowboy work remains separate.
