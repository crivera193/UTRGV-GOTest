# Independent campus exploration foundation

The former social-events product has been removed in place. The app is named UTRGV-GO. Flutter Android/iOS infrastructure remains; the next playable slice is the cowboy walking around UTRGV Edinburg using real location updates.

## Current scope

- Email/password accounts restricted to .edu addresses, without email verification (all .edu domains, not only UTRGV).
- Clean account screens and a custom campus-only Mapbox map with opt-in GPS.
- No events, factions, friends, event moderation, social notifications, Bon/Sparky branding or demo XP.
- The existing cowboy sprite atlases are registered and connected to the filtered campus GPS position. The cowboy appears only with a valid on-campus fix and hides off campus, on stale/unavailable GPS and while the app is inactive. Location remains opt-in through Follow me.
- The cowboy uses a rendered sprite overlay with GPS-driven walking/standing; The Flame mini-game host is integrated separately; actual gameplay and live animated 3D rendering are not implemented. Native map alignment and real campus walking remain to be reviewed on-device. See [cowboy source, runtime assets and rendering limits](docs/cowboy-player.md).

## New Supabase project only

The former backend URL/key and event migrations were removed. No remote database was modified. No previous accounts or sessions are migrated; the client uses an independent session-storage namespace.

Configured on October 19, 2026 in the new UTRGV-GO project (oipidltfvzodpiumdsaq), SeniorProjectUTRGV free organization, signed in as crivera193. Region: West US (Oregon). No paid upgrade or former-team backend access.

- Email/password signup enabled; Confirm email OFF; minimum password length 8. Anonymous, phone and social-provider signups disabled.
- independent_accounts.sql applied through the dashboard SQL editor. It rejects non-.edu Auth email creation/changes, creates private player profiles and permits only the owner's .edu account to read its profile. Automatic RLS enabled at project creation; automatic broad grants disabled.
- SQL transactional checks passed for .edu eligibility, non-.edu rejection, profile creation and account isolation; synthetic test records were rolled back.
- Public Auth settings endpoint reachable; mailer_autoconfirm=true. Direct non-.edu Auth signup rejected with HTTP 500 / P0001 from the database trigger. Flutter provides a friendly .edu validation message before making this request.
- Local .env.app.local.json contains SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY and the existing ACCESS_TOKEN. It is ignored by Git. No database password or secret/service-role key is needed in the app.
- No permanent test account was created. Actual end-to-end signup/sign-in with the owner's chosen .edu account remains to be exercised by the owner.

The initial migration is already applied manually to this project; do not replay it or the old team's migrations. New game tables must use equivalent authenticated .edu-user authorization. The project checks the email suffix only, not mailbox ownership or enrollment.

Example build configuration (placeholders only):

```powershell
flutter run --dart-define-from-file=.env.app.local.json
```

The owner-supplied public Mapbox token is saved in .env.mapbox.local.json (ignored by Git). A read-only request to the Standard style returned HTTP 200. Include --dart-define-from-file=.env.mapbox.local.json when running/building locally; do not print the token or add the file to version control. This validates the token, not live native rendering.

Without backend configuration the app shows an account-service configuration notice; it never falls back to the previous backend. Without Mapbox configuration the map shows its existing notice.

## Verification and remaining work

Use the established Flutter 3.47.7 installation and Android-only dependency procedure in AGENTS.md. Run flutter analyze --no-pub and flutter test --no-pub after changes.

The campus map now uses local campus-clipped OSM geometry, an opaque background and simplified raised buildings, a fixed 45-degree camera, whole-campus fit, native pan/zoom bounds and Follow me / View campus controls. Foreground GPS is filtered for campus membership, accuracy, age and boundary uncertainty. See [campus-map implementation and review limits](docs/campus-map.md) for editable extent, sources/licenses, approximate heights, data gaps and reproducible checks. Native visual review and actual on-campus GPS are still pending; no install or deployment is part of this map update. The separate Flame preview host and GPS arrival foundation are documented in [mini-game foundation](docs/flame-games.md).

Android/iOS platform identifiers/signing were not changed. Android release still uses debug signing; iOS's original team ownership must be verified before release. Do not install, deploy or upload without the appropriate task authorization. Project Git restrictions remain in AGENTS.md.

## Repository and branches

Private repository: https://github.com/crivera193/UTRGV-GO . Use crivera193 only; never Nayster/TheNayster. Owner authorized source pushes and the following tracking branches:

- main: integrated independent app baseline.
- codex/campus-map: campus geography, camera constraints and location behavior.
- codex/cowboy-player: optimized cowboy and walking/idle rendering integration.
- codex/flame-gameplay: Flame game layer and gameplay systems.

The baseline retains Git ancestry from the original source. Local SourceArt (approximately 26 GB), character references and character-authoring adapters are explicitly ignored by Git and remain on disk; no bulk source-art upload or deletion was performed. Runtime mascot assets under assets/ and new application tooling remain trackable and will be added after mobile preparation. Dependency caches, temporary outputs, .env files, signing material and packaged app builds are ignored too. Do not use broad model/image/source-extension ignores that would hide actual runtime assets or application code.

### Connected Android preview — October 19, 2026

Built current source with .env.app.local.json and installed the fresh app-x86_64-debug.apk on the dedicated UTRGV_GO_Preview emulator (emulator-5556, API 36.1). Visually confirmed the .edu login/create-account screen, replacing the missing-backend notice. No account was created and the authenticated map has not yet been reviewed.

The original Medium_Phone emulator had insufficient internal storage; Android cache trimming did not free space. Its app was not uninstalled or data-cleared. A separate fresh preview AVD was created instead. Source build command: flutter build apk --debug --no-pub --split-per-abi --target-platform android-x64 --dart-define-from-file=.env.app.local.json . The same source remains configured for Android/iOS; this artifact is specifically for the x86_64 emulator.
