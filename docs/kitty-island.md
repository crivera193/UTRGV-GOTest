# Kitty Island

Owner-confirmed location: **26.307804, -98.171621**, the tree-filled Education
Complex courtyard in the supplied satellite screenshot. The earlier Physical
Science cat sighting is not this landmark. The three decorative anchors near the
pin are approximate visual placements, not surveyed positions.

On `codex/kitty-island`, the existing foreground GPS stream feeds an independent
decoration policy. Two seconds of fresh on-campus fixes within 30 m reveal the
cats; leaving beyond 45 m hides them. Accuracy must be 20 m or better. Stale fixes
(over 10 seconds), unavailable/denied GPS, off-campus state and app inactivity hide
the cats. Duplicate or reordered timestamps cannot supply arrival dwell. No new
permissions, background tracking, server state or game invitation is introduced.

Mapbox projects three geographic anchors into map-local logical pixels through
the existing latest-projection queue pattern. Camera changes invalidate in-flight
results. Cats render as flat Flutter overlays above the map, without building
occlusion or map lighting. Their widgets ignore input and semantics, preserving
map gestures and attribution. Mini-games hide the decoration. Each Lottie player
uses its original 1.28-second loop with a different phase, plus a 350 ms entry
scale effect. Reduced-motion preference disables animation.

The dark original and owner-selected orange/gray color-only derivatives are
bundled, with provenance and license under `assets/animations/kitty-island/`.
No network animation fetch is required. Regenerate derivatives using
`python tool/create_kitty_variants.py`.

Verification: `flutter analyze --no-pub` and `flutter test --no-pub` (53 tests)
passed October 21. Focused tests cover arrival/exit/re-entry, duplicate and stale
fixes, poor accuracy/off-campus rejection, actual JSON decoding/rendering, frame
changes and input passing through the overlays. Native Android and outdoor GPS
review status is recorded below. Owner appearance review remains required before
integration into main.

## Native preview — October 21, 2026

Built with Flutter 3.47.7 using the ignored project configuration:
`flutter build apk --debug --no-pub --split-per-abi --target-platform android-x64 --build-number=8007 --dart-define-from-file=.env.app.local.json`.
Installed in place on `UTRGV_GO_Preview`, `emulator-5554`, Android API 36.1,
1080 × 2400. Split APK package version: `com.example.campus_app` 1.0.0 (12007).
Installed and new APK signing SHA-256 matched; existing signed-in session remained.
APK SHA-256: `72A976907405ABBDA507E179ABD6CE5F7CA5B35CC902B1BF46E894D8D262AD76`.

Observed the three colors on the native map, hiding beyond 45 m and revealing
again on approach using **simulated emulator GPS**, not an outdoor field test.
Moved the orange decorative anchor ~8 m north of the pin after observing that the
cowboy covered it at the exact center. Normal animation timing is retained; a
26-second native screen recording demonstrates the requested approach. Local
captures are in ignored `tmp/kitty-island/`, including `kitty-walk-arrival.mp4`.
Actual outdoor accuracy, device performance and owner appearance acceptance
remain unverified.

The preview build includes the pre-existing uncommitted campus-camera and cowboy
repairs in the shared workspace. Only Kitty Island additions are staged/committed
on this feature branch; those unrelated changes remain local and visible. Main
is not integrated while owner review is pending.
