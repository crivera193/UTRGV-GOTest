# Chapel capture prototype — October 20, 2026

This section supersedes the historical preview-only foundation below. The chapel
now hosts a local Flame football quiz. No multiplayer, shared tables, rewards,
new accounts or background GPS were added.

## Entry and settings

Tap the ring/diamond/pedestal beacon or **Chapel Point** in the map controls.
The card opens at any distance. It includes a labeled placeholder illustration
and description, owner/player teams, local ownership notice, HP and distance.
Friendly ownership disables Attack. **DEBUG · Reset local owner and HP** restores
Team B / 100 HP. No state is written to Supabase.

For isolated review without an account, Mapbox or travel, use a debug build with
`--dart-define=CHAPEL_PREVIEW=true`, then **Open chapel · no GPS eligibility**.
This entry is guarded by `kDebugMode` and uses separate persistent local state
`utrgv_go_chapel_debug_v1`; normal map state uses `utrgv_go_chapel_local_v1`.
Existing GAME_PREVIEW/GAME_SPOTS_DEMO entries remain. The fountain demonstration
coordinate remains explicitly debug-only, never a substitute for the chapel.

`ChapelConfig` in `lib/games/chapel_capture.dart` centralizes text, coordinates,
placeholder teams, 100 maximum HP, 25 damage, three shots and demo questions.
Questions have stable IDs and stable a–d answer IDs. Topics are Edinburg, the
meaning of RGV, ECHAP and pedestrian safety; distractors are not factual claims.
`LocalPointPersistence` owns save format/key/validation. `CaptureSession` owns
the provisional policy of retaining earned damage after failure or Close.
Capture restores maximum HP under the new owner (`restoreHpOnCapture`).

## Coordinate evidence

Verified October 20 from the [official interactive map](https://www.utrgv.edu/maps/edinburg/index.htm),
which embeds [Concept3D map 1165](https://map.concept3d.com/?id=1165#!m/295835).
The public map search for chapel returned:

| Record | ID | Latitude | Longitude |
| --- | --- | --- | --- |
| Chapel (ECHAP), beacon anchor | 295835 | 26.305357 | -98.174683 |
| Chapel Lawn, outdoor context | 922984 | 26.305534 | -98.174644 |

The [building inventory](https://www.utrgv.edu/campus-operations/departments/campus-facilities-operations/building/index.htm)
identifies ECHAP as Chapel. The [official 2025 PDF](https://www.utrgv.edu/ucentral/_files/documents/campus-maps/utrgv-edinburg-map.pdf)
also identifies it (number 7 in that version; older maps number it 16).
The [official Earth Fest listing](https://calendar.utrgv.edu/event/earth-fest-2026-edinburg)
confirms chapel-lawn use, but its embedded geographic metadata points to Arizona;
those coordinates were rejected. No map photo was copied. The placeholder card,
beacon and stadium use original local shapes and existing Inter/OFL typography.

The mapped lawn is about 20 m north of the chapel anchor, inside the attack
radius. Play from a safe outdoor path or lawn; never enter the building to play.
Actual pedestrian access and GPS quality need outdoor human review; the official
landmark marker is not a surveyed pedestrian waypoint.

## GPS, map and game contract

The chapel's single approved radius is **130 ft = 39.624 m** in ChapelConfig.
Its invitation entry radius references that constant. The 45 m invitation exit
hysteresis never unlocks Attack; old 25/40 m defaults apply only to the legacy
preview demo. Card and press-time checks reuse SpotProximity's raw foreground
fix: confirmed on-campus, at most 10 s old, not future, accuracy at most 15 m,
and **distance + reported accuracy <= 39.624 m**. This is conservative about
uncertainty. Camera/avatar smoothing never supplies eligibility. An active
session survives GPS jitter. Backgrounding pauses play and cancels aim.

The beacon uses Mapbox pixelForCoordinate in logical pixels and a constant-size
Flutter control. LatestProjection discards obsolete camera replies. Camera
changes/style readiness reproject it; off-screen beacons are hidden. Existing
navigation bounds are unchanged. One opaque game route retains the map, blocks
map input, and returns through the same card with updated owner/HP and follow
state. Closing suppresses repeated proximity invitations.

FootballShot separates world lateral x, forward z and height h from projection.
All four separated goals share z=30. Direction sets lateral/forward velocity;
upward swipe displacement controls bounded power. Input uses a 400×650 logical
field and a generous ball start area. Tiny/backward, cancelled and secondary
pointer gestures cannot fire. There is no answer-dependent aim correction.
Flight uses analytic ballistic motion, perspective scale, spin and a turf shadow.
Scoring solves the forward-plane crossing even across a long frame and requires
ball-radius clearance between uprights, above crossbar and below post tops.
Answer panels are not hitboxes. Each shot ID resolves once.

States are question-ready, aiming, flying, resolving and session-ended. A miss
uses a shot and retains question/positions; three misses end the session. A wrong
goal ends it immediately. A correct goal saves one damage event before Continue
advances and resets shots. Four default correct goals capture Team A and restore
100 HP. Save failure awards no in-memory damage and ends visibly. Callbacks after
Close cannot apply a new result; an already earned pending save may finish
without advancing the closed session. The existing host owns pause, route
visibility, one instance per session and cache cleanup.

## Verification and review limits

Flutter analysis passed; all **50** tests passed. Targeted tests cover radius,
uncertainty/stale/campus rejection, invitation hysteresis, four reachable goals,
aperture/trajectory bounds, correct/wrong/miss rules, three misses, shot reset,
exactly-once damage, capture, local persistence/reset, late callbacks, actual
Flame cancel-to-end delegation, secondary pointers, pause and close/reopen.
A real GameWidget test drives a five-second crossing frame and checks that
another update cannot award the same hit again.

Android x86_64 debug APK built with the configured project toolchain. Native
SharedPreferences registration was confirmed. The existing Mapbox Kotlin plugin
migration warning remains. This working-tree build includes the preserved
pre-existing map/cowboy changes. Source/build hashes are under ignored
`output/chapel-review/`.

Actual Flutter test renders at **390×844, DPR 1** are under that same directory:
four-goal-widget.png, chapel-card-widget.png and capture-result-widget.png.
beacon-only-widget.png shows the original beacon by itself, without a map.
These render the real implementation with bundled fonts; they are **not native
emulator screenshots**. Native map-marker captures/projection checks, outdoor GPS,
normal-speed manual swipe feel and owner visual approval remain pending.
No device installation, PC input automation, touch campaign, video or deployment
was performed, as explicitly required for this task.

References read: [GameWidget](https://docs.flame-engine.org/latest/flame/game_widget.html),
[drag events](https://docs.flame-engine.org/latest/flame/inputs/drag_events.html),
[collision detection](https://docs.flame-engine.org/latest/flame/collision_detection.html),
[FlameGame](https://docs.flame-engine.org/latest/flame/game.html).
These guides identify themselves as older documentation; callbacks/lifecycle
were checked against installed Flame **1.38.2**, including cancellation semantics.

Changed files: `lib/games/chapel_capture.dart`, `chapel_card.dart`,
`chapel_football_game.dart`, `football_shot.dart`, `game_host.dart`,
`game_spot.dart`, `spot_proximity.dart`; `lib/screens/map_screen.dart`;
`lib/main.dart`; `pubspec.yaml`/`pubspec.lock`; `test/chapel_capture_test.dart`,
`test/spot_proximity_test.dart`; this guide and `README.md`.
Pre-existing edits to AGENTS, campus-map/cowboy guides, camera presentation,
cowboy motion and related tests remain uncommitted. Only chapel-specific map
hunks are included in this delivery; the working tree retains the existing
camera/GPS changes in that same file.

---

## Historical mini-game foundation — October 19

Implemented October 19, 2026 using Flutter 3.47.7 / Dart 3.13.5,
Flame **1.38.2** (stable, pinned) and existing geolocator 14.1.1.
Only Flame and its required ordered_set dependency were added to the lockfile.
Actual mini-game design is intentionally deferred.

## Behavior and ownership

Mapbox retains the campus map, camera and geographic rendering; the cowboy
sprite renderer is unchanged. MapScreen forwards raw CampusFix values from its
existing opt-in foreground GPS subscription to SpotProximity. No new location
subscription, permission, background tracking, backend table or server change.
Tests inject fixes directly into this same policy; no camera coordinates or
smoothed player positions are used for game eligibility.

GameSpot contains a stable ID, display name, WGS84 point, game ID, enabled flag
and per-spot entry/exit radii. ProximitySettings centralizes defaults: 25 m entry,
40 m exit, maximum 15 m reported accuracy, 10 second fix age and 3 second dwell.
Entry requires distinct increasing timestamps spanning dwell inside the entry
radius **including reported uncertainty**. Timers alone cannot earn eligibility.
Future, stale, inaccurate, invalid or missing fixes cannot unlock games. Campus
membership comes from the existing boundary policy. These settings need outdoor
tuning; reported accuracy is an estimate, not a guarantee.

Once entered, eligibility persists inside the larger exit threshold with an
accuracy margin. Outside fixes immediately prevent Play; reliable fixes beyond
exit plus accuracy for 3 seconds establish genuine departure. The nearest
eligible spot wins initially (stable ID breaks ties); it remains selected while
eligible. Dismiss/Play suppress overlapping arrival cards, including spots still
dwelling, until reliable departure and re-entry. GPS loss never counts as leaving.
States explicitly distinguish unavailable, outside campus, outside range,
eligible, dismissed and active. Eligibility is rechecked synchronously on Play.

The arrival card asks the player to stop walking, then choose Play or Dismiss.
Play pushes one opaque Flutter route; MapScreen and its native map remain mounted.
A synchronous session guard prevents duplicate launches. Map camera updates and
overview fitting are suspended during the session; the previous follow-mode is
restored at return, with the next real GPS update allowed to follow again.
GPS continues only while the app is foreground and never auto-closes the game.

GameHost creates its game once per session (a new instance only on explicit
failed-load retry). The registry currently contains only `preview`. Session
context contains spot ID, start time and a debug indicator, without GPS history or
account information. GameWidget provides loading and error/retry states; Flutter
provides SafeArea, title and Close. The preview draws a gently animated circle and
labels itself “Game preview — gameplay coming next.” There are no rewards,
completion writes, scoring, audio, combat or collecting. Close/system Back return
to the previous route; the optional exit callback returns only previewClosed.

The registered route observer combines route visibility and app lifecycle:
covered/inactive/background sessions pause and resume only when foreground and
current. New games should extend SessionGame, own/cancel their own listeners and
timers, and use its session-local image/asset caches. GameWidget invokes disposal;
global Flame caches and shared GPS services are never cleared by the host.
No orientation settings were added or changed.

## Spots and debug instructions

**Production spots are empty.** Legacy campus landmark records exist, but do not
verify safe pedestrian interaction positions. Do not treat building centroids,
approximate map boundaries or old fountain coordinates as approved destinations.
Add production spots only after verifying pedestrian access and campus inclusion.

The optional debug demonstration reuses the old fountain record at longitude
-98.176061, latitude 26.304802 with stable ID `debug-fountain-preview`. It is
labeled **DEBUG ONLY · fountain demonstration (unverified)**. This is a software
demonstration, not a direction to travel there or a verified production spot.
It is enabled only by `kDebugMode && GAME_SPOTS_DEMO`; real GPS gates still apply.

To inspect just the preview without an account, Mapbox or travel, run a debug
build later when interactive testing is authorized:

```powershell
flutter run --debug --dart-define=GAME_PREVIEW=true
```

Choose **Open game preview · no GPS eligibility**. Close returns to the debug
launcher. In the normal configured debug map, **DEBUG · Game preview** also opens
the host without asserting real GPS eligibility. For optional real-stream debug
demonstration, use normal account/Mapbox configuration plus
`--dart-define=GAME_SPOTS_DEMO=true`. It never synthesizes a player position.
Both flags and debug controls are disabled in profile/release builds.

## Verification and limits

Source checks: `flutter analyze --no-pub`; `flutter test --no-pub`.
Focused tests cover entry/exit and uncertainty margins, stale/poor/future/missing
fixes, outside-campus state, overlaps, replayed updates, duplicate launch,
dismissal, genuine leave/re-entry and close suppression. Widget checks invoke
callbacks without mouse/keyboard/touch input automation, run a real GameWidget,
verify loop progression, route/app pause and resume, load failure/retry, cleanup
and return to the same retained underlying widget. That underlying widget is a
test stand-in, not a native Mapbox rendering check.

Android arm64 debug build uses the unchanged platform configuration and ignored
`.env.app.local.json` via `flutter build apk --debug --no-pub --split-per-abi
--target-platform android-arm64 --dart-define-from-file=.env.app.local.json`.
The existing Mapbox Kotlin Gradle plugin migration warning remains. No unrelated
package upgrade was made to address that future-toolchain warning.

No device installation, interactive touch test, native visual inspection, video,
real outdoor GPS acceptance or live-server change is part of this task. iOS is
not built on Windows. The preview animation is exercised by widget frames;
normal-speed visual acceptance and safe launch locations still need manual review.

Official references read: [stable package](https://pub.dev/packages/flame),
[GameWidget](https://docs.flame-engine.org/latest/flame/game_widget.html),
[FlameGame](https://docs.flame-engine.org/latest/flame/game.html),
[overlays](https://docs.flame-engine.org/latest/flame/overlays.html),
[versioned 1.38.2 API](https://pub.dev/documentation/flame/1.38.2/game/FlameGame-class.html),
[Geolocator distance API](https://pub.dev/documentation/geolocator/latest/geolocator/Geolocator-class.html).
The supplied Flame “latest” guides identify themselves as older documentation;
API details, lifecycle, GameWidget disposal and private-cache behavior were also
checked against the installed 1.38.2 source. Version-specific GameWidget and
Geolocator distance pages were inaccessible through the browser, so they were
not treated as read references.

Changed files: `pubspec.yaml`, `pubspec.lock`, `lib/main.dart`,
`lib/screens/map_screen.dart`, `lib/games/game_spot.dart`,
`lib/games/spot_proximity.dart`, `lib/games/game_host.dart`,
`test/spot_proximity_test.dart`, `test/game_host_test.dart`, `README.md`,
`AGENTS.md` and this document. No source-art or cowboy assets were changed.
