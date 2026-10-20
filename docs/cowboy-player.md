# GPS cowboy runtime

The owner chose rendered animated sprites after reviewing the separate-renderer
camera/depth tradeoff. No new rendering package or Flame installation is needed.

## Authoritative source

`SourceArt/human-cowboy/v008-hands-paint-repair/Cowboy_Hands_and_Paint_Repair.blend`
with the preserved `Cowboy_Relaxed_Walk` action. The v008 status/build records
identify the repaired gloves and garment paint and prove unchanged approved walk
channels/rig. The owner subsequently approved that result in “Start mascot
creation in Blender” (“looks so good!! ty!”). The older v006 static mannequin and
v007 intermediates are not the runtime source. The master remains local/ignored;
its SHA-256 is recorded in the runtime manifest and verified after export.

## Export and rendering

`tool/export_player_sprites.py` runs in an independent background Blender 5.2
worker; it opens the master read-only and never saves it. `tool/pack_player_sprites.py`
assembles `assets/player/cowboy/cowboy-pitch-{0,30,50}.png` and `manifest.json`.
Each atlas contains eight headings, twelve walk frames and a standing view.
The walk is sampled evenly from its existing 40-frame/30fps loop (1.333 seconds;
nine exported sprite frames per second at normal playback).
Standing holds the existing relaxed arms with neutral rest lower-body transforms
on the export copy. Hat, body, gloves, accessories, materials and proportions are
rendered directly; no character generation or replacement rig is involved.

The source's separate `Matched_Travel_Preview` driver is disabled in the worker.
The walk stays in place. GPS alone supplies geographic displacement; sprite
animation cannot change coordinates. The atlas has transparent surroundings and
an explicitly projected ground-origin anchor for each pitch. Flutter draws each
frame at that anchor relative to Mapbox's `pixelForCoordinate` result in logical
pixels. The frame direction is travel heading minus camera bearing. Sprite tiles
are bounded to 48–84 logical pixels high, rather than growing exponentially with
map zoom. No platform pixel-ratio correction is applied twice.

Mapbox 2.26.0 exposes a glTF location puck but does not expose skeletal clip
playback. Mapbox documents no glTF keyframe/skinning/morph animation support:
[Mapbox 3D model limitations](https://docs.mapbox.com/style-spec/guides/using-3d-models/).
The installed SDK documents `pixelForCoordinate` in logical pixels, matching
[the public API](https://docs.mapbox.com/flutter/maps/api/latest/mapbox_maps_flutter/MapboxMap/pixelForCoordinate.html).

This is a cartographic sprite overlay, not a live skeletal 3D model: heading
quantization is 45 degrees and pitch uses the nearest of 0/30/50 degrees. The
current campus map locks its camera to 45 degrees/north-up; the corresponding
50-degree view is a five-degree approximation. The marker deliberately draws
above buildings and does not cast map shadows or participate in building depth.
It can remain visible through a building footprint. Perspective, map lighting and
sub-pixel ground contact are approximations; owner appearance review is required.
Three decoded atlases use about 38 MB RGBA memory, excluding Flutter overhead.

## GPS behavior

`MapScreen` now mounts the existing sprite only for an accepted on-campus GPS
marker. It reprojects the marker after GPS/camera updates and hides the overlay
when the point leaves the viewport or GPS becomes outside, uncertain, stale or
unavailable. App inactivity removes the overlay and stops GPS/motion evidence;
resume waits for fresh fixes. The orange ground ring remains; the old solid dot
is hidden. Cowboy assets are included in the Flutter bundle. These integration
changes have not yet been visually verified over the native map on a device.

The existing campus policy owns permission/service state, boundary uncertainty,
real position smoothing, and hiding stale/outside locations. No replacement
on-campus coordinate is generated. Motion requires accuracy within 20 meters,
two directionally coherent segments above max(1.8 m, half the reported accuracy),
and derived speed of 0.45–3.5 m/s. Opposite jumps, teleports, duplicate timestamps,
future and stale fixes do not start walking. A 4.5-second movement timeout, checked
once per second, returns to standing. Playback uses the source rig's recorded 1.06451 m/s travel speed,
clamped to 0.65–1.6 times. Delayed walking is deliberate when GPS cannot resolve
short steps. Movement is never inferred from camera events or extrapolated beyond
received fixes. Manual map browsing suspends follow; Follow me resumes it.

## Focused verification

`test/cowboy_motion_test.dart` uses explicitly synthetic GPS only, never a recorded
location history. Runtime atlas verification checks transparency, unclipped bounds,
distinct animated frames and the master hash. Build/analyze, sprite playback and
synthetic walk/stop/turn/exit checks are the requested scope. No input automation,
touch tests, video capture or device installation is part of this task. Native
Mapbox/GPS alignment and subjective appearance remain for manual review.

The focused run passed 15 checks: six synthetic GPS/motion cases, offscreen
Flutter sprite playback/standing/camera-relative orientation, and eight campus
policy/style cases. The actual 390×844 offscreen standing/walking frames were
inspected; these have a plain test background, not a native Mapbox screenshot.
No tests inject mouse, keyboard or touch input. The analyzer excludes the
established ignored `tmp/` and `output/` folders so earlier diagnostic Dart
source copies are not analyzed as application files.

Android universal debug build succeeded without installation. Every packaged
cowboy asset was byte-compared with its source, and the debug kernel's embedded
motion/sprite/map/location source was compared with the checked files. The build
also contains concurrent opening-screen work; that work is independently owned.
Build SHA-256: `6952055e261860e850e3629cad8dc6afe46a6d821700398ae6708b010a05f081`.
Detailed local verification is in ignored `tmp/avatar/build-verification.json`.
Full Flutter analysis passed after excluding the diagnostic folders. iOS was
not compiled. The saved build is `build/app/outputs/flutter-apk/app-debug.apk`;
future builds may replace it, so compare its hash before reusing this evidence.

Animation provenance: existing Quaternius Universal Animation Library Standard v3
`Walk_Loop` (CC0), retained in the source production records. Glove source: CC0
MakeHuman base hands fitted during the approved v008 repair; its license remains
in `SourceArt/human-cowboy/v008-hands-paint-repair/source/LICENSE.ASSETS.md`.
