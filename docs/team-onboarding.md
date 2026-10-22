# Permanent team onboarding

Implemented on `codex/team-onboarding`; **owner visual review pending**. No main
integration until review. Existing map/cowboy/chapel source is retained.

Owner revision: removed the three pillars from the scene. The original shared
hat sprites now float above the colored lights; hat positions, selection controls
and permanent-membership behavior are unchanged. The pedestal export is retained
as historical asset material but is no longer loaded or rendered. Updated widget
captures were inspected; analysis and all eight onboarding widget tests passed.

## Experience and code

After a real Supabase session is established, `AuthGate` mounts an account-keyed
`TeamGate`. It loads `account_teams` before mounting `MainScreen`. Loading errors
show Retry/Sign out, never the teamless screen or map. The gate owns the nested
navigator, including gameplay routes and dialogs; changing/signing out of an
account discards that entire subtree. Chapel's existing route observer is attached
to that navigator. Existing debug mini-game launchers remain debug-only.

`TeamMembership` is an owned ChangeNotifier, following the app's existing
StatefulWidget/ChangeNotifier pattern rather than introducing another global
store. `TeamScope` exposes the authoritative result to descendants. It holds no
persisted "seen onboarding" flag. The account button beside Sign out shows the
saved team with no switch/reset control.

Stable IDs and editable copy live in `lib/teams/game_team.dart` and the database
catalog. Keep descriptive copy aligned when editing it; identifiers must stay
stable. Any major can choose any of these game teams:

| ID | Display name | Color |
| --- | --- | --- |
| health_science | Health and Science | Blue |
| math_engineering | Math and Engineering | Red |
| art_stuff | Art and Stuff | Yellow |

The Flame scene is decorative 2.5D. Flutter supplies named, keyboard-focusable
semantic buttons over each full column and readable team-name buttons. Only the
confirmation dialog's Choose team invokes the repository. Choose another and
browsing never write. Reduced-motion preferences suppress idle motion. App
backgrounding/dialog presentation pauses the scene; it owns its image cache.
Asset errors have a scene retry, independent of account errors.

Saving disables both dialog actions. Every submission first rereads membership;
if saving fails or times out, a fresh read reconciles an uncertain commit. An
unreadable result goes to a blocking error/retry state. The server's winning team
always wins, including another device choosing first. Async responses after
account disposal are ignored. The existing no-confirm-email backend policy and
login/signup flow are unchanged; typed credentials alone do not enter the gate.

## Assets

`tool/export_team_assets.py` renders the supplied
`SourceArt/human-cowboy/v010-hat-only/Cowboy_Hat.blend` into two transparent PNGs:
512×384 hat and 256×448 original geometric stone pedestal. All three choices
share the **same** neutral hat sprite. Blue/red/yellow light is drawn behind it,
without recoloring any existing player asset. The derived editable scene is
`SourceArt/team-selection/v001/Team_Selection_Export.blend` (ignored source art).
`assets/teams/provenance.json` records the source hash, source inventory,
materials and Blender version. Export checked that the original hash stayed
`591c0634510d4e8fd689e7e84c080ee6b7d214eec7690718c69f60beef1ad10e`.

Blender MCP could not connect. BlenderBridge was live but attached to Eddy's
unrelated Feathered-Raptor project and was left untouched. Assets were actually
exported and inspected using isolated background **Blender 5.2.2**, not through
the live bridge. The references supplied arrangement/mood only; their image
pixels, artwork and characters are not used.

## Live database

Verified through the authenticated dashboard as **crivera193**:
**UTRGV-GO / SeniorProjectUTRGV / oipidltfvzodpiumdsaq**. Before changes, inspected
all public table columns, policies, application functions and Auth/profile
triggers. Only `player_profiles(id, created_at)` existed. No legacy assignments,
profile team fields or privileged assignment/reset RPCs were present. Existing
.edu eligibility and profile-creation functions matched the initial migration.
The automatic-RLS event trigger was also inspected.

`20261022000000_permanent_teams.sql` was applied manually through the SQL editor;
do **not replay it** on the live project. It adds the three canonical rows,
`account_teams(user_id PK → auth.users, team_id FK, chosen_at)`, own-row .edu RLS,
SELECT-only client grants and authenticated-only `choose_team(text)` execution.
The SECURITY DEFINER RPC has an empty search path, fully qualified objects,
derives its actor from `auth.uid()` and checks the real Auth email via the
existing helper. It accepts no user-ID argument. INSERT ON CONFLICT DO NOTHING
plus the primary key arbitrates races; a subsequent read returns the winner.
An update/delete trigger supplies defense against future accidental broad grants.
Membership is independent of profiles. Account deletion is deliberately restricted
by the membership FK; there is no ordinary delete/reset API or self-service
account-deletion feature in this change. Database-owner maintenance remains
privileged SQL, never a shipped app capability.

`supabase/tests/permanent_teams.sql` **passed live**. Synthetic users and rows were
rolled back. It checks valid/invalid/null choices, anonymous execution/read,
forged user arguments, own-row isolation, direct insert/update/delete/truncate,
upsert, immutable triggers even as database owner, same/different retries and
profile deletion/recreation.

A separate two-session live test used one tagged disposable Auth fixture. Session
A chose health_science and held its uncommitted unique row for 12 seconds;
session B concurrently requested art_stuff. B waited, then returned
**health_science**. The first choice remained authoritative. Cleanup checked the
fixture's exact UUID, synthetic email and disposable metadata, took an exclusive
membership-table lock, temporarily disabled only the immutable trigger within
that transaction, removed only that test assignment, reenabled the trigger and
removed only the tagged fixture. Final readback: **0 fixture users, 0 fixture
memberships, immutable trigger O (enabled)**. No real user's team was assigned,
reset or deleted. No service-role key, database password or other secret is in
the application or this change.

## Checks and review

Flutter 3.47.7 / Dart 3.13.5; pinned Flame 1.38.2. Formatting, Flutter analysis and
all **72 tests passed**, including 14 new membership/onboarding tests and existing
map, cowboy and chapel tests. The new tests exercise the actual GameWidget and
Flutter dialog, all choices/cancel/confirmation, blocked back navigation,
missing/error/assigned gates, duplicate confirmation, failed/uncertain saves,
late responses, account-switch route disposal, shared persisted-repository
restart behavior and accessible small-phone/landscape/large-text layouts.
The persistence tests use a repository double; SQL tests exercise the real DB.

Actual Flutter renders at **390×844, DPR 1**, with bundled fonts, are in
`docs/evidence/team-selection-390x844.png` and
`docs/evidence/team-confirmation-390x844.png`. They are widget renders, not native
screenshots. Recreate with:

```powershell
flutter test --no-pub test/team_onboarding_test.dart --dart-define=CAPTURE_TEAM_REVIEW=true --update-goldens
```

Android x86_64 preview build uses ignored `.env.app.local.json` and Android
Studio's JBR. Confirmed SharedPreferences native registration. The pre-existing
Mapbox Kotlin migration warning remains. iOS is not built on Windows. Emulator
installation and source/artifact hashes are recorded under ignored
`output/team-review/`; the normal build number must exceed the installed preview
(a default-number attempt was rejected as a downgrade without changing data).
Final preview: **UTRGV_GO_Preview / emulator-5554**, version **1.0.0**, installed
version code **16015** (build input 12015 plus the existing x86_64 ABI offset).
Existing and new APK signing certificate SHA-256 matched. The installed base APK
was pulled back and matched the fresh build byte-for-byte:
`430f01d1edef10a268f9f3d5692b92cada561a5c3f7c41f3ff589883529f008a`.
The existing authenticated session survived the update and was correctly gated.
The native **1080×2400** capture is `docs/evidence/team-selection-emulator.png`;
all three choices/names and the corrected status-bar contrast were inspected.
No team was chosen for the existing account. Existing unrelated working-tree
map/cowboy edits were included in the preview build and preserved outside this
feature's commit; the full source-file hash manifest is in the ignored evidence
directory.

Physical touch feel, actual two-device operation, outdoor GPS and owner
visual acceptance remain separate from these automated checks. No phone install,
production release, purchase or transaction is authorized by this implementation.

References read: [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security),
[functions](https://supabase.com/docs/guides/database/functions),
[column privileges](https://supabase.com/docs/guides/database/postgres/column-level-security)
and [FlameGame](https://docs.flame-engine.org/latest/flame/game.html). The Flame
guide identifies itself as older documentation; lifecycle, asset loading,
disposal and GameWidget behavior were checked against installed 1.38.2 source.

Floating-hat revision preview: installed version code **16016** on the same AVD with matching signing, retained session and byte-for-byte APK verification (SHA-256 e5ec2197d5c3369cdb7df5ce3aafbb8696880656e1f114c2087f7a9e896cf419). Native capture updated; no team was selected.

## October 22 — live signup, gameplay and full process restart

Owner-requested end-to-end tests **passed** against the actual configured
Supabase project on UTRGV_GO_Preview, emulator-5554, 1080×2400. This is native
Flutter driver execution, not repository doubles or widget-only rendering.

- Created two synthetic `.edu` accounts through the actual Create account form.
  The real signup trigger created each private player profile. Each account was
  initially gated with zero membership rows.
- Opened/canceled team information for each account; reread Supabase and confirmed
  that canceling created no assignment. Explicit confirmation saved Art and Stuff
  for A and Math and Engineering for B.
- For both accounts, checked the live account_teams row, matching Auth/profile ID,
  TeamScope state and the visible account/profile dialog. Membership is stored
  separately from the profile table by design; the profile UI reads that saved
  membership. A new independent authenticated Supabase client read the same team.
- Signed out of A, created/selected B, then signed out and signed A back in. A
  immediately reached the map with its own original team, without onboarding or
  another account's cached team.
- Launched the existing chapel GameHost after the membership gate. Used a
  dedicated run-specific local chapel save and explicitly debug-only GPS bypass.
  Delivered two actual timed Flutter pointer swipes through the game's input
  callbacks, waited for normal live-loop resolution, answered both correctly and
  observed persisted test HP drop **100 → 75 → 50**. Closed gameplay back to the
  real map and rechecked the saved team/profile.
- Ran `am force-stop`, verified the app PID no longer existed, then launched the
  activity with Android reporting **LaunchState: COLD**. Reconnected a fresh driver
  to the new process. The restored test session immediately reached MainScreen;
  TeamSelectionScreen was absent. The profile and Supabase still had the exact
  same account, team ID and original `chosen_at` timestamp.

Reusable test entry/host: `test_driver/team_app.dart` and `team_flow.dart`.
The explicit debug-only entry requires a named run and verifies the exact backend
host. It runs the real CampusApp/AuthGate/TeamGate with a separate test auth
storage namespace, keeping the owner's normal session untouched. Flutter driver
is a dev dependency only; normal `lib/main.dart` never imports or enables it.
The two login field keys are the only app-code changes required for reliable
form targeting. No gameplay, membership or backend behavior needed fixing.

The test build was version 16017. After testing, restored a fresh **normal app**
build, version **16018**, via an in-place signed update. Pulled back the installed
APK and verified its SHA-256 matched the fresh build:
`dba7e5172cf81b0d5f37e046018c0150ab0416915917ad3ba9afacb8c137a460`.
The owner's original session returned to its still-unassigned team screen;
no team was chosen for that account. No app data was cleared, uninstalled or
downgraded. Removed the test VM-service port forwarding.

Analysis passed and all **72 existing unit/widget tests** passed after adding
the SDK driver dependency and field keys. Driver phases `create` and `relaunch`
both passed. New native screenshots: `docs/evidence/team-e2e-chapel-play.png` and
`docs/evidence/team-after-cold-relaunch.png`. Detailed JSON, screenshots and logs
are retained under ignored `output/team-e2e/` and `tmp/team-e2e/`. The two synthetic
test accounts remain assigned for reproducibility; random test credentials stay
only in the ignored fixture file and are not published. No real users or real
memberships were edited or deleted.

To reproduce, prepare a new ignored fixture with `run`, synthetic `a`/`b`
mailboxes and a random `password`, and an ignored build-config copy with the
same `TEAM_E2E_RUN`. Build the explicit test entry, install in place with a
monotonically increasing version, launch and forward its authenticated loopback
VM-service endpoint. Supply that URL through `TEAM_VM_URL`, then run:

```powershell
dart run test_driver/team_flow.dart create output/team-e2e/fixture.json
# Force-stop, verify no PID, cold-launch, and forward the NEW VM endpoint.
dart run test_driver/team_flow.dart relaunch output/team-e2e/fixture.json
```

Restore a freshly built normal `lib/main.dart` preview afterward. Do not use a
real account in the fixture, replay create against an already-used fixture, ship
the test entry or disable VM-service authentication. Physical devices and real
outdoor GPS were not part of this test.
