# Mini-game foundation

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
