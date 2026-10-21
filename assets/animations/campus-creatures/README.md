# Campus building animations

Owner-supplied art, accepted October 21, 2026. Floral source:
`Concept_ Floral Branch_Butterfly and tree.json`; dragon source: `dragon.json`.
Creator/source URL/distribution license were not supplied. Kitty Island licensing
must not be assumed to cover these independent assets.

- Dragon: Computer Science/EIEAB, longitude -98.1747739, latitude 26.3062088.
  Roof height 10.9 m matches the bundled 10.5 m building plus its 0.4 m base.
- Floral: School of Medicine/EMEBL, north campus, longitude -98.17508,
  latitude 26.30995. Roof height 9.4 m matches the bundled 9 m building plus base.
  This is the Medicine footprint, not the older Health Affairs East marker.

`floral.json` preserves the original transparent vector Lottie, 500 x 500,
30 fps, 181 frames. `dragon.webp` packages the accepted transparent cleanup:
150 original frames, 30 fps, five seconds, looping. Buildings, ground and detached
small fires were removed before packaging; original head/jaw motion and the main
fire remain. No Blender reconstruction or generated body is used.

The dragon uses a common crop across every frame (484,0,716,504) and a 540 x 380
lossless animated WebP to avoid loading 150 full-size Lottie bitmap assets together.
`dragon-still.png` is its reduced-motion poster. The source SHA-256, crop and timing
are in dragon-provenance.json. Repackage with:
`python tool/pack_campus_dragon.py PATH_TO_ACCEPTED_TRANSPARENT_JSON`.
The large editable cleanup remains local under output/dragon-background-removed-v1.

Both landmarks appear when viewing their buildings at zoom >= 16, without needing
GPS arrival. Latest-only native projection tracks camera changes; the displayed
size follows zoom. A local height/pitch calculation approximates roof alignment.
These are camera-facing Flutter overlays, not depth-occluded 3D objects. IgnorePointer
preserves map gestures; offscreen/background/mini-game states remove the widgets.
Reduced-motion uses the dragon poster and stops the floral Lottie controller.

Validation: Flutter analysis clean; all 56 tests pass, including actual WebP
frame count/loop/timing/transparency, frame changes, floral playback, reduced
motion and gesture pass-through. Android preview verification is recorded below.

## Native preview — October 21, 2026

Built from codex/campus-creatures with the shared workspace's existing campus-camera
and cowboy repairs preserved. Flutter 3.47.7 debug Android x86_64, build number
8010; installed package com.example.campus_app 1.0.0 (12010) on UTRGV_GO_Preview,
emulator-5554, 1080 x 2400. In-place install; existing signing certificate matched,
installed APK SHA-256 matched the fresh artifact, signed-in session retained.
APK SHA-256: d70a6a3462b983149f315f2dfb97d7a40d4753d2545c77ced5b8e0efb53c2993.

Observed both transparent animations over the intended roofs, plus panning and
zooming. Native 6/7-second clips and full-screen captures are in ignored
`tmp/campus-creatures/`. Preview navigation used synthetic emulator GPS, not
outdoor GPS. No phone installation or production deployment. Owner appearance
review is still pending; retain the feature branch and do not merge main yet.
