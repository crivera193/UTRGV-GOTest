# Trainer profiles and progression

Implemented October 22, 2026 on `codex/trainer-progression`. Open the account icon after permanent team selection to view the trainer screen. Existing profiles and team memberships are preserved; an unset username does not force another onboarding flow.

## Profile and photos

Trainer name (optional, 32 characters), unique username (3–20 lowercase letters/numbers/underscores, starting with a letter), bio (200 characters), and a profile photo are editable. Usernames are normalized and unique in PostgreSQL. `update_trainer_profile` derives the actor from Auth, validates every field, checks avatar ownership and uses the original edit revision to reject conflicting saves. Background updates never replace the draft's revision. Loading, error/retry, failed uploads, uncertain saves, cancellation and discard-on-Back are explicit.

`trainer-avatars` is a private Supabase Storage bucket. Users can access only their own UUID folder; no public profile directory or public photo access was introduced. The app uploads a uniquely named 512×512 JPEG, re-encoded into a fresh pixel image to strip original EXIF/GPS metadata. Input decoding and upload size are bounded. Android's system photo picker is used; interrupted picker results are recovered when the same account reopens the trainer screen. iOS photo-library purpose text is included. Signed URLs are short-lived and regenerated on refresh/foreground return. Removing a photo unlinks it from the profile; prior uploaded objects remain private in Storage, rather than silently deleting retained assets.

## Server-owned progression

The owner approved these starting values: **25 XP per correct kick**, **50 bonus XP for a perfect attack**, **100 bonus XP for a capture**. Wrong answers, misses and timeouts earn zero. A perfect attack requires every configured question to be correct; an early capture does not receive a perfect bonus unless all questions were completed correctly.

`point_attacks` snapshots reward settings at entry. A protected trigger issues private XP events with unique event keys, then atomically updates the account's progress and evaluates milestones. Retrying or replaying shot receipts cannot award XP again. No client supplies XP, rank, level or unlocked achievement flags. Combat damage/capture/cooldown defaults are unchanged. The attack summary reports server-confirmed XP earned.

Progression begins with gameplay resolved after this feature's migration; previous completed attacks are not retroactively rewarded. Existing attack history is retained. `read_trainer` reconciles the account's active attacks against elapsed deadlines before returning completion counters. It uses the same actor-advisory-lock then point-row-lock order as combat. No background job or device clock grants rewards.

## Editable catalogs

Manage these tables in the verified UTRGV-GO Supabase project `oipidltfvzodpiumdsaq`:

| Table | Purpose |
| --- | --- |
| `progression_settings` | One row: `correct_xp`, `perfect_xp`, `capture_xp`. Changes affect new attacks; existing attempts retain their snapshot. |
| `progression_levels` | Level and cumulative `min_xp`. Keep level 1 at zero, with increasing levels and thresholds. Initially 20 levels with `100 × (level−1)²` cumulative XP. |
| `progression_ranks` | Rank name and minimum level. Initial ranks: Newcomer, Campus Scout, Trailblazer, Campus Guardian and Campus Legend. Keep a baseline rank at level 1. |
| `progression_achievements` | Stable ID, title, description, badge/achievement kind, emblem, target metric/amount, order and enabled flag. Supported metrics: correct kicks, captures, perfect attacks, completed attacks and XP. |
| `player_progress` | Server-owned XP and counters; ordinary clients have own-account read access only. |
| `player_achievements` | Server-owned earned timestamps; unique per account/milestone. Disabling a definition hides it without erasing earned history. |

Eight initial milestones cover first/10/100 correct kicks, first/10 perfect attacks, first/10 captures and 10 completed attacks. Their definitions, targets and display content come from Supabase. Earned milestones persist even if their target is later changed. Level and rank changes are derived from the current catalog and total XP. The screen listens to profile, progress and catalog updates, reloads on foreground return, and supports manual refresh. Missing/invalid configuration produces an error rather than invented fallback data. Expanding a supported catalog requires no app rebuild; adding a new metric algorithm requires reviewed server support.

Migrations `20261023010000_trainer_profiles_progression.sql`, `20261023011000_trainer_reward_feedback.sql` and `20261023012000_trainer_offline_recovery.sql` were applied through the authenticated crivera193 dashboard. **Do not replay them.** No former-team backend was accessed.

## Verification

82 Flutter tests passed. Focused checks cover configured level/rank thresholds, invalid configuration, photo resizing/metadata removal, editable profile validation, saving without changing XP, stale draft revisions despite live updates, and loading/error recovery. Analysis is clean.

Live REST checks used existing isolated QA accounts and fresh hidden QA points. Unique username conflicts, stale revisions, invalid usernames, cross-account profile/progress reads and writes, unauthorized settings changes, real JPEG upload, foreign-avatar linking and foreign-folder uploads/signing were checked. Four attacks produced exactly **550 XP / 10 correct kicks / 2 captures / 2 perfect attacks / 4 completions**, unlocking four milestones. Replayed receipts added zero XP; wrong/miss/timeout results added zero; an early capture earned its capture bonus without a perfect bonus. The other account stayed at zero XP and permanent teams were unchanged.

A rolled-back live SQL contract verified reward snapshots through mid-attempt configuration edits, offline timeout catch-up, earned XP feedback, editable levels/ranks/milestones and inaccessible private reward helpers. All temporary users, points and catalog changes rolled back.

Android native checks used UTRGV_GO_Preview / emulator-5554, x86_64, 1080×2400, test build 12028/versionCode 16028. The actual trainer screen saved name/bio edits, displayed a real private avatar, and showed 550 XP / level 3 / Campus Scout. A second authenticated client changed the profile; Realtime updated the same running screen. A full process stop (no remaining PID) and cold launch preserved the profile, photo, XP, rank, four earned milestones and permanent team, without repeating team selection. [Saved profile](evidence/trainer/profile-saved.png), [earned and locked milestones](evidence/trainer/badges.png), [cold launch](evidence/trainer/cold-launch.png).

The normal emulator app is restored in place after QA as build 12031/versionCode 16031; the pulled installed APK matches fresh SHA-256 `c53cf32afd40e95b985231cbdd719015a36a607f6696c9627cb4e6a3810f660c`. Native evidence covers profile editing and saved photo rendering; image decoding/upload permissions are separately tested. Automated OS-gallery selection, deliberate Android process death during the picker, and an iOS build were not exercised. Android Mapbox/Kotlin future-toolchain warnings remain. User data and signing are preserved. The normal account's permanent team choice is left to its owner.

Reproduction: use `supabase/tests/trainer_fixture.sql` as a fresh-ID template, never reset existing cooldowns. `test_driver/trainer_rest.py` expects fresh progression and its one-time QA points. `supabase/tests/trainer_rules_contract.sql` is fully transactional and rolls back. `test_driver/trainer_flow.dart edit|remote|restart` uses the separate `test_driver/team_app.dart` session and ignored test fixture; update only the QA profile between edit and remote, then force-stop and reconnect the new VM endpoint before restart. Credentials, signed photo URLs, app builds and real saves remain ignored.

## Research used

- [Pokémon GO trainer profile/progress](https://niantic.helpshift.com/hc/en/6-pokemon-go/faq/82-viewing-your-trainer-profile-progress/): a single identity/progress/milestone overview informed the screen; game-specific rewards were not copied.
- [Supabase Flutter user management](https://supabase.com/docs/guides/getting-started/tutorials/with-flutter): profile and avatar integration with Auth/RLS.
- [Storage access control](https://supabase.com/docs/guides/storage/security/access-control) and [private buckets](https://supabase.com/docs/guides/storage/buckets/fundamentals): account-folder policies, upload restrictions and signed reads.
- [Database functions](https://supabase.com/docs/guides/database/functions): explicit actor checks, restricted execution and empty search paths for trusted RPCs.
- [Flutter image_picker](https://pub.dev/packages/image_picker): native gallery selection, platform setup and Android lost-data recovery. Resolved packages: image_picker 1.2.4 and image 4.12.0; native plugin registration was checked.
