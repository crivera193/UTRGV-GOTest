# Dynamic live points and rules — October 22, 2026

Supabase now owns the live point catalog and editable rule sets. The map, invitation/proximity checks, point list, card and free-kick game use reusable point models. There is no compiled production point list, chapel coordinate/configuration or device-local combat fallback. Stable point `echap-local-v1` remains in Supabase with its existing location, ownership, health and history.

## Managing live content

Use the authenticated Supabase Table Editor in project `oipidltfvzodpiumdsaq`:

- `public.game_spots`: add a stable unique `id`, name and latitude/longitude; edit description, optional HTTPS image, entry/exit/attack radii, maximum health and `rule_set_id`. `game_id` is `free-kick`, the currently supported executable game. Additional game algorithms still require application implementation. Keep production points inside the approved campus area and verify safe pedestrian access. Existing IDs must remain stable when moving or renaming.
- `public.game_rule_sets`: edit question count, seconds per question, maximum attempt damage percentage and cooldown seconds. Supported ranges are 1–20 questions, 1–300 seconds, greater than 0 through 100% maximum damage, and 0–86400 cooldown seconds. Rules can be shared across points or assigned separately. Versions and timestamps advance automatically.
- To remove a referenced point, set `enabled=false`; this removes its marker/list entry and prevents attacks while preserving history, ownership and account cooldowns. Re-enabling the same ID preserves those records. Avoid destructive deletion or replacing IDs to move a point.
- Questions remain in private `app_private.question_bank`. Keep the four labeled production placeholders until the owner provides the real bank. New attempts snapshot randomly selected prompts and shuffled choices; correct answers never appear in public payloads.

The `standard` rule set remains **4 questions × 15 seconds, maximum 25% damage and a 600-second entry cooldown**. A correct standard kick deals 6.25%. Wrong answers, misses and timeouts deal zero and advance. The final damaging player's permanent team wins and full health is restored. Configurability does not change these current standard settings.

The app subscribes to point and rule changes through Supabase Realtime, including transitions to disabled. It also reloads on foreground return. Loading, empty catalog, connection failure, unsupported game and retired-point states are explicit. The map projects the whole current catalog with a batched native Mapbox call. Names, descriptions, optional images, owner badges and health update from live data. QA point rows remain hidden from ordinary players and excluded by the normal catalog.

Each attempt snapshots its rule set, starting maximum health, point play version and absolute cooldown end. Edits affect new attempts; already-started attempts retain their original question count, timers, damage budget and cooldown. Cumulative numeric rounding makes a perfect attempt reach the configured budget exactly, even when it is not evenly divisible by question count. Moving or disabling a point invalidates active attempts, without erasing earned damage or cooldown history. Deadlines continue while away; authority, receipt idempotency and answer adjudication remain on the server.

Migration `20261022210000_dynamic_points_and_rules.sql` was applied successfully to the live project through the authenticated crivera193 dashboard. Do not replay it. Ordinary authenticated clients have read-only access to public point/rule tables and cannot change health, rules or private answers.

## Observed verification

Analysis is clean and **77 Flutter tests passed**. Live REST checks on isolated QA fixtures verified a seven-question, 120-second, 30%/180-second attempt continuing under its original rules after an admin edit to three questions, eight seconds and 40%/60 seconds. A perfect seven-question attempt removed exactly 36 of 120 HP; a new account used the edited rules and dealt 16 HP for one correct answer, with zero for wrong/missed answers. Moves/disabling invalidated attacks; receipt retries and direct-write restrictions remained enforced. Four real synthetic accounts then captured a fresh standard point in 25% contributions, with the final Math and Engineering player's ownership visible to every client. Real campus point HP and coordinates were not changed by the tests.

On UTRGV_GO_Preview / emulator-5554, Android x86_64 at 1080×2400, test build 12026/versionCode 16026 received point additions, moves, renames, rule edits and disabling in the same running app without rebuilding. Rendered marker positions/names and the native card were checked. The test launcher initially lacked its normal Material container; that launcher was corrected and the successful native checks repeated. [Updated card](evidence/dynamic-points/card-rules.png), [map before](evidence/dynamic-points/map-before.png), [retired points](evidence/dynamic-points/map-retired.png).

A custom three-question/nine-second game displayed its server timer, auto-advanced a real timeout and accepted actual Flutter pointer input through the free-kick physics. One correct kick removed 10% under its 30% maximum. The process was fully stopped with no remaining PID; a later COLD launch preserved 90% HP, the rule snapshot and entry cooldown, with both unanswered questions recorded as timeouts and the attempt completed. [Timer](evidence/dynamic-points/custom-timer.png), [cold restart](evidence/dynamic-points/cold-restart.png).

The normal app was restored using fresh build 12027/versionCode 16027, installed in place with the same signing certificate. Pulled installed APK SHA-256 matched the built artifact: `59cf984e9fb6f03a2fe9af08cbfc46a42778cd5a96d6d7f1942d1b020d14cdb8`. Normal and QA auth storage remain separate. The normal account already had a profile but no team membership; the owner confirmed they had not selected a team. Its selection screen is therefore expected until its first confirmation. QA accounts retained their memberships across restarts. No permanent choice was made for the owner's account.

Reproduction: provision fresh isolated IDs using `supabase/tests/dynamic_points_fixture.sql` as a template (do not replay existing fixture inserts or reset cooldowns). `test_driver/dynamic_points_rest.py start|edited|capture` runs authenticated server checks; between start and edited, change only the QA custom rules, move the QA move point and disable the QA disable point. Native phases use `test_driver/dynamic_points_flow.dart catalog-start|catalog-edited|catalog-disabled|play|resume` with `test_driver/team_app.dart` and the ignored synthetic configuration. Apply QA map/rule edits between catalog phases; force-stop and reconnect the new VM endpoint between play and resume. Tokens, credentials and VM URLs stay ignored. The feature remains on `codex/live-attacks` for owner review; unrelated map/cowboy working changes are excluded from the source commit but included in the combined emulator build. No iOS build or real outdoor GPS acceptance was performed. Existing Mapbox/Kotlin future-toolchain warnings remain.

---

Historical fixed-default implementation record (the defaults remain current; editable configuration above supersedes fixed values):

# Timed point attacks — October 22, 2026

Current owner rules supersede the earlier unlimited attack record below. Every attack contains **four questions**, **15 seconds each**, and can deal **at most 25% of maximum point health**. Each correct kick deals exactly 6.25%; wrong answers, misses and timeouts deal zero. All outcomes advance automatically, with no Continue pause. The attempt ends after four resolved questions or an earlier capture. A ten-minute cooldown per account and point starts at entry; closing the game, switching devices, or a change of ownership does not clear it. An unfinished attempt resumes with its original deadlines. Unanswered questions continue expiring while the app is away; elapsed slots are reconciled on the next authenticated server read.

The last damaging player's permanent team wins the point, even if another team dealt more total damage. Capture restores full health. The map beacon shows the canonical owner's team name/color; the card has a matching owner badge and health bar. Unclaimed points are neutral. The card shows the cooldown countdown and disables a fresh attack until it expires; active attempts offer Resume attack.

Migration `20261022190000_four_question_attacks.sql` was applied successfully to live project `oipidltfvzodpiumdsaq` through the authenticated crivera193 dashboard. Do not replay it or the two earlier migrations. It adds question deadlines/resolution records, timeout counters, attempt damage totals and a completed status. HP uses exact numeric arithmetic instead of rounded integers. Existing HP, owners, profiles, permanent teams and shot receipts were preserved; legacy unlimited active attempts were retired as expired. The four labeled production placeholders remain until the owner provides their list. Bank selection avoids repeats within an attempt when four or more active questions exist; choices remain shuffled and correct indices private.

Supabase derives the actor/team and owns deadlines, score, cooldown, shared health and capture. `point_attack_access` supplies server time, cooldown end and resume availability. `read_point_attack`, begin/retry and kick operations reconcile elapsed deadlines under the existing actor/spot lock order. Catch-up uses the preceding deadline, so reopening after a long absence cannot grant four fresh timers. A kick reaching the server after its deadline cannot award damage. Command receipts and question IDs prevent duplicate or concurrent damage. Inputs retain the existing bounded trajectory and safe proximity checks; client-reported GPS is not device attestation. Client countdowns use a monotonic clock calibrated from server responses; background/route return refreshes authoritative state. A pending kick remains intact across a same-question foreground refresh.

Verification: analysis clean; **74 Flutter tests passed**, including exact fractional damage, four-question cap, timeouts, uncertain-response retries, cooldown display, nested card/game navigation and an interrupted flight. Native testing used the source-matching test build 12022/versionCode 16022 on UTRGV_GO_Preview / emulator-5554 at 1080×2400, preserving app data and signing. The real GameWidget timer advanced question 1 automatically after 15 seconds, and a real pointer kick on question 2 removed exactly 6.25%. The app process was force-stopped 2.38 seconds after question 3 became active, with no PID remaining. A later COLD launch preserved the team and 93.75% health, reconciled the two offline unanswered questions (three total timeouts), and displayed the remaining cooldown with Attack disabled. Captures: [timer](evidence/timed-attacks/timer-question-one.png), [correct kick](evidence/timed-attacks/fractional-damage.png), [cold launch](evidence/timed-attacks/cold-relaunch-cooldown.png).

Live REST verification used four synthetic accounts on hidden QA points: Art and Stuff accounts dealt the first three 25% contributions (HP 75/50/25), then a Math and Engineering account delivered the last 25% and became owner for all four clients, despite the opposing team's 75% contribution. Every attempt stopped after four questions; a new request during cooldown was rejected. A mixed attempt (two correct, one wrong, one real 15-second timeout) dealt exactly 12.5%; a late correct kick awarded zero. Duplicate, stale and simultaneous commands could not multiply damage. Own profiles/memberships remained intact, another account's attack was inaccessible, direct HP edits and anonymous access were denied. QA rows, answers and private timer helpers remained protected by RLS/ACL checks. A rolled-back boundary test rejected at 9:59 and allowed at 10:01. The real chapel remained neutral at HP 100/revision 0; no real location history was used or retained.

The fresh normal app was restored in place using build 12023/versionCode 16023. Its installed APK SHA-256 matched the new artifact: `b7f5ae90450b529bfb912c5f7945d74b4e5a322020451d2bca33c36725ad9d6b`. Signing stayed unchanged, normal/test authentication storage remained separate, and the real user's existing team-selection screen was restored. The Mapbox Kotlin plugin migration warning remains. iOS and real outdoor GPS acceptance remain untested. Source stays on `codex/live-attacks` for owner review; unrelated map/cowboy changes remain outside this feature commit, while the emulator build includes the combined working tree.

Reproduction: use the ignored project configuration and synthetic credential fixture. `test_driver/prepare_timed_accounts.py` creates/reuses only the additional synthetic C/D accounts and their permanent teams. The original `supabase/tests/live_attack_fixture.sql` supplies QA questions; `supabase/tests/timed_attack_fixture.sql` creates fresh timed QA points and tags only the named synthetic accounts. These are one-time fixtures, never reset real points or memberships to rerun them. `python test_driver/live_attack_rest.py` runs the four-account/partial/race cases. `supabase/tests/timed_attack_boundary.sql` checks the boundary with all fixture changes rolled back. Build `test_driver/team_app.dart` with the ignored test configuration; run `live_attacks_flow.dart prepare`, immediately force-stop and verify no PID while question 3 is active, then wait beyond both remaining deadlines before a COLD launch and `resume`. Reconnect the new authenticated VM endpoint without putting it in tracked files. The first test-host run exposed a Python timestamp-parser limitation and was retained as an isolated diagnostic attempt; a fresh QA point was used rather than resetting its cooldown. An initial native observation was repeated because the process had not been stopped before its remaining timers expired; the recorded cold-stop evidence above is the corrected source-matching run.

---

## Earlier live-attack record (superseded by the rules above)

# Live point attacks — October 22, 2026

This section supersedes the historical local/preview notes below. The owner requires live gameplay with only a few placeholder questions until the full bank is supplied.

Production uses Supabase project `oipidltfvzodpiumdsaq`. Both migrations `20261022160000_live_point_attacks.sql` and `20261022170000_attack_conflict_responses.sql` were applied successfully through the authenticated crivera193 dashboard. Do not replay them. The second migration returns application conflicts as HTTP 409 instead of a database serialization failure; stale-question REST calls timed out with the original error and passed after this correction.

`app_private.question_bank` holds four labeled placeholder questions and private correct indices. Only the admin manages the bank. Each attack snapshots one random question, shuffles its answer choices, and sends the prompt and choices without the answer key. The next selection avoids an immediate repeat when another active question exists. Editing/deactivating bank rows does not change questions already dealt; increment `version` for authored revisions. Replace placeholders with the supplied list later. An empty bank blocks new attacks; if it empties during an attack, earned damage is retained and that attack ends.

`public.game_spots` is authoritative shared state. The chapel retains stable ID `echap-local-v1`, starts unclaimed at 100 HP, takes 25 damage per correct kick, and restores 100 HP on capture. Owners use the same canonical IDs as permanent account membership. Former inconsistent local saves are preserved on disk but never imported or used by gameplay. Membership/profile records remain unchanged by attacks.

The authenticated RPCs are `begin_point_attack`, `read_point_attack` and `submit_point_kick`. Begin derives the player and permanent team from authentication, requires a fresh fix (10 seconds, accuracy at most 15 m) and distance plus uncertainty within 39.624 m, and rejects friendly points. GPS values are client-reported, not device attestation. Position is not stored. Reopening an active attack resumes its existing question; inactivity expires it after 15 minutes. Leaving does not erase earned damage. A capture invalidates competing attacks using a capture epoch.

Every valid kick consumes its current question: miss/wrong means zero damage and a loss, correct means damage. All outcomes advance to a new question after feedback/Continue; there is no three-shot cutoff. Play ends at capture or Close. Supabase computes the answer lane from the same bounded swipe trajectory as `FootballShot`; clients cannot submit a result, damage or team. Question IDs reject stale submissions, command IDs return identical receipts on retry, and locks serialize shared HP/capture. A lost response keeps the same command for Retry; a conflict refreshes the authoritative question or ends a superseded attack. Offline operation never awards damage. Realtime point updates and refresh on foreground/return update the map/card.

The point card and game use the authenticated nested navigator, fixing the game-hidden-behind-card regression. Production debug launchers, local resets and demo routes were removed. Explicit test entry points remain under `test_driver/`; they use a separate authentication storage namespace and a private QA point at synthetic coordinates. An admin-only metadata flag gates QA rows; ordinary accounts cannot see them. Test accounts retain their permanent teams.

Verification on UTRGV_GO_Preview / emulator-5554 (1080×2400): 71 Flutter tests passed; analysis clean after host logging cleanup. Live REST checks passed for authentication/RLS, private answers, GPS rejection, random next questions, more than three losses, correct damage, duplicate receipts, stale-question rejection, simultaneous submissions and second-account shared HP. Native driver used the actual card > Attack > GameWidget pointer path, missed/advanced, force-stopped the process, verified a COLD launch, resumed the exact attack/question/HP/team, kicked correctly twice and captured for Art and Stuff. Both live accounts then read owner `art_stuff`, HP 100, revision 4; profiles/memberships remained intact. The real chapel stayed neutral at HP 100, revision 0. Captures: [before close](evidence/live-attacks/before-close.png), [captured online](evidence/live-attacks/captured-online.png).

The test build used input build 12019 (installed versionCode 16019); the normal app was restored with fresh build 12020/versionCode 16020, the same signing certificate and an in-place install preserving user data. Normal and test auth storage are distinct. The last recovery refinements are covered by focused unit tests; native full-flow evidence precedes those error-path-only refinements. Android Mapbox/Kotlin plugin migration warning remains; no iOS build or real outdoor GPS acceptance was performed. Feature remains on `codex/live-attacks` for owner review; unrelated map/cowboy work is excluded from its commit but present in the combined emulator build.

Reproduction uses `test_driver/team_app.dart` and `test_driver/live_attacks_flow.dart prepare|resume`, the ignored `.env.app.local.json` and synthetic fixture configuration. Prepare records the active question; force-stop, verify no PID, launch cold and reconnect the new VM endpoint before resume. QA point needs 50 HP before this two-correct-kick capture scenario. No credentials, VM tokens or real location data belong in tracked evidence.

References checked: [Supabase Flutter stream](https://supabase.com/docs/reference/dart/stream), [database functions](https://supabase.com/docs/guides/database/functions), [PostgREST custom HTTP errors](https://docs.postgrest.org/en/stable/references/errors.html#raise-errors-with-http-status-codes).

---

Historical implementation record (superseded where it describes local or preview gameplay):

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
