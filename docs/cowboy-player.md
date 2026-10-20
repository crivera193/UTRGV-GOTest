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
current campus map locks its camera to 55 degrees/north-up; the corresponding
50-degree view is a five-degree approximation. The marker deliberately draws
above buildings and does not cast map shadows or participate in building depth.
It can remain visible through a building footprint. Perspective, map lighting and
sub-pixel ground contact are approximations; owner appearance review is required.
Three decoded atlases use about 38 MB RGBA memory, excluding Flutter overhead.

## Walking and movement repair

The repair preserves the approved master and runtime atlases byte-for-byte.
Independent inspection confirmed twelve distinct poses, correct 160×192 crops,
a 1.333-second loop and common foot anchors per pitch. No new export was needed.

### Causes found

- The old gate needed two segments above half the reported GPS accuracy, but a
  4.5-second timeout erased evidence between segments. At synthetic 1-second
  updates, 1.2 m/s and 12–20 m accuracy, walking never started (0/25 samples).
  Earlier passing tests used 3 m accuracy and missed that case.
- The displayed marker combined a 3–5 m deadband and a 55% sample filter, then
  jumped on arrival. The same route had maximum lag of 2.90/4.80 m and largest
  jumps of 2.25/3.30 m at 12/20 m accuracy. Follow copied those sample jumps.
- The existing ticker discarded elapsed gaps of 250 ms or longer. This can
  freeze playback during stalls; no device profile established whether stalls
  contributed to the outdoor report. Conditional mounting could also discard
  the animation instance on temporarily missing/offscreen projections.
- Each projection rebuilt MapScreen. Redundant camera reads and sample-time
  zoom/pitch resets added work. Follow used abrupt setCamera calls, not
  competing easeTo animations.

### Current behavior

CowboyMotion measures cadence and separates accumulated evidence from walking
expiry. Two coherent segments above max(1.8 m, min(3.5 m, accuracy × 0.15)) start
walking; genuinely reported reliable provider speed can corroborate the first
segment. Missing speed/accuracy is never interpreted as measured zero. Travel
must be 0.45–3.5 m/s. Stationary samples settle to idle; missing samples stop
walking after a cadence-dependent 3–8 seconds. Playback is bounded to 0.8–1.35×
the source speed. Invalid, stale, duplicate or implausible fixes do not walk.

CowboyTravel separates accepted targets from cosmetic position. A single 160 ms
time constant and a 650 ms settling budget after the last target replace stacked
filters. New updates continue from the current display point. There is no
prediction or extrapolation. Reacquisition after an 8-second gap or 25 m jump
uses the new fix rather than inventing intervening travel. Fixes older than
6 seconds cannot supply new targets. Small idle jitter is suppressed cosmetically.
Campus and game eligibility still use the original GPS policy/raw fixes, never
this display position. The old marker filter is not fed into this smoother.
GPS cadence/accuracy and native scheduling still limit responsiveness.

One persistent CowboySprite retains decoded atlases and loop phase across GPS,
direction/pitch changes and projection loss. Flutter vsync advances the loop
independently of GPS, pauses for idle/inactivity, and repaints only the avatar
canvas. Camera-relative heading has a 6° switching margin; pitch has a 3° margin.
The upright sprite is not rotated as an arrow. The separate Flame host does not
advance this Flutter-owned animation.

Display projection is requested at most every 33 ms. LatestProjection permits
one native read and one pending latest refresh, rejecting results invalidated
by new GPS, camera or lifecycle state. Camera state comes from installed SDK
events; avatar-only ValueNotifier updates replace map-tree rebuilds. Follow
sends serial center updates at most every 66 ms, without restarted easing or
sample-time zoom/pitch resets. Manual-pan suspension, campus bounds, selected
exploration zoom and View campus remain intact. These are request budgets,
not measured device frame rates. The above-building limitation is unchanged.

### Focused evidence and limits

The cowboy tests cover the cadence failure, continuous retargeting, 300 ms
frame gaps, facing hysteresis and obsolete asynchronous projections. A short
synthetic route covers start, steady walk, turn, stop, stale data and camera-only
changes. Runtime frames 11, 2 and 5 appear at 5.1, 5.4 and 5.7 seconds without
another GPS arrival. Phase survives updates, state survives stale visibility
loss, and the test background builds only once.

At synthetic 60 Hz, maximum displayed step was 0.119 m; residual to an accepted
1.2 m step was 0.053 m after 500 ms. Walking was active in 21/25 samples at
12 m accuracy and 19/25 at 20 m. Initial evidence-gathering delay is intentional.
These are synthetic display metrics, not GPS accuracy or measured device FPS.

[Full runtime frames, native 390×844 viewports](evidence/cowboy-walk-repair-full.png)
and [supplementary 2× crops](evidence/cowboy-walk-repair.png) use a plain test
background, not native Mapbox screenshots. Local metrics are in ignored
tmp/avatar-repair. No input automation, touch tests, recording, installation or
deployment was performed for this repair. Native alignment, outdoor GPS, iOS
and on-device UI/raster profile timing remain unverified.

APIs checked against installed Flutter 3.47.7, Mapbox Flutter 2.26.0,
geolocator platform interface 4.4.0 and Flame 1.38.2. References read:
[Ticker](https://api.flutter.dev/flutter/scheduler/Ticker-class.html),
[Mapbox animations](https://docs.mapbox.com/flutter/maps/guides/camera-and-animation/animations/),
[camera](https://docs.mapbox.com/flutter/maps/guides/camera-and-animation/camera/),
[Flame sprite lifecycle](https://docs.flame-engine.org/latest/flame/components/sprite_components.html),
[performance measurement](https://docs.flutter.dev/perf/rendering-performance).

Repair validation: full Flutter analysis passed; all 11 focused cowboy checks
passed. The uninstalled ARM64 Android profile build is saved at
`output/cowboy-player/UTRGV-GO-cowboy-walk-repair-arm64-profile.apk`, SHA-256
`733cb8a9810bd9710c87e3de70784ce4786a47600d209c53cdace01ddcabe05b`.
Packaged cowboy assets were compared byte-for-byte with source; the approved
master hash still matches its manifest. Player source stayed unchanged during
compilation; final MapScreen whitespace was checked against Dart formatter
output from the built source. Local build/source records are in
`tmp/avatar-repair/build-verification.json` and `format-equivalence.json`.

Animation provenance: existing Quaternius Universal Animation Library Standard v3
`Walk_Loop` (CC0), retained in the source production records. Glove source: CC0
MakeHuman base hands fitted during the approved v008 repair; its license remains
in `SourceArt/human-cowboy/v008-hands-paint-repair/source/LICENSE.ASSETS.md`.
