# Independent campus exploration foundation

The former social-events product has been removed in place. Campus Explorer is a temporary label. Flutter Android/iOS infrastructure remains; the next playable slice is the cowboy walking around UTRGV Edinburg using real location updates.

## Current scope

- Email/password accounts restricted to .edu addresses, without email verification (all .edu domains, not only UTRGV).
- Clean account screens and campus Mapbox screen with opt-in location display.
- No events, factions, friends, event moderation, social notifications, Bon/Sparky branding or demo XP.
- Cowboy authoring source and neutral campus geographic data are retained. They are not yet registered runtime assets.
- Flame/gameplay and animated 3D character rendering are not integrated. The map still uses the native default location indicator when location is enabled.

## New Supabase project only

The former backend URL/key and event migrations were removed. No remote database was modified. No previous accounts or sessions are migrated; the client uses an independent session-storage namespace.

1. Create the owner's new Supabase project. Apply supabase/migrations/20261020000000_independent_accounts.sql ONLY to that new project. It rejects non-.edu Auth email creation/changes, creates private player profiles, and restricts profile reads to the owning .edu account.
2. Enable email/password signup and DISABLE Confirm email so signup returns a session immediately. No email verification is required for this project. Require passwords of at least eight characters; disable anonymous, phone and social-provider signups for this initial scope.
3. No email confirmation landing page or verification deep-link flow is needed.
4. Supply SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY as Dart defines. Never provide secret/service-role keys. Supply ACCESS_TOKEN for the owner's Mapbox project separately.
5. Check that .edu signup enters the app immediately without an email link. Check rejection of non-.edu requests through the Auth API and profile isolation between accounts. These backend checks have NOT been executed without the new project.

The SQL is unapplied and not runtime-verified. Existing migration history from the former backend must not be replayed here. New game tables must use equivalent authenticated .edu-user authorization. This project checks the email suffix only; it does not verify mailbox ownership or enrollment.

Example build configuration (placeholders only):

```powershell
flutter run --dart-define=SUPABASE_URL=https://NEW_PROJECT.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=NEW_PUBLISHABLE_KEY --dart-define=ACCESS_TOKEN=YOUR_MAPBOX_PUBLIC_TOKEN
```

The owner-supplied public Mapbox token is saved in .env.mapbox.local.json (ignored by Git). A read-only request to the Standard style returned HTTP 200. Include --dart-define-from-file=.env.mapbox.local.json when running/building locally; do not print the token or add the file to version control. This validates the token, not live native rendering.

Without backend configuration the app shows an account-service configuration notice; it never falls back to the previous backend. Without Mapbox configuration the map shows its existing notice.

## Verification and remaining work

Use the established Flutter 3.47.7 installation and Android-only dependency procedure in AGENTS.md. Run flutter analyze --no-pub and flutter test --no-pub after changes.

The campus center remains a point-based initial camera, not a verified whole-campus fit. Complete boundary verification, campus camera constraints, GPS filtering, Flame integration, optimized cowboy export and animated map rendering remain necessary before claiming a playable walking experience. Do not add new gameplay features before proving that representative slice.

Android/iOS platform identifiers/signing were not changed. Android release still uses debug signing; iOS's original team ownership must be verified before release. Do not install, deploy or upload without the appropriate task authorization. Project Git restrictions remain in AGENTS.md.

## Repository and branches

Private repository: https://github.com/crivera193/UTRGV-GO . Use crivera193 only; never Nayster/TheNayster. Owner authorized source pushes and the following tracking branches:

- main: integrated independent app baseline.
- codex/campus-map: campus geography, camera constraints and location behavior.
- codex/cowboy-player: optimized cowboy and walking/idle rendering integration.
- codex/flame-gameplay: Flame game layer and gameplay systems.

The baseline retains Git ancestry from the original source. Local SourceArt (approximately 26 GB), character references and untracked authoring scripts remain on disk outside this app-code delivery; no bulk source-art upload or deletion was performed. Runtime mascot assets will be added after mobile preparation. Never upload .env files, signing material or generated builds.
