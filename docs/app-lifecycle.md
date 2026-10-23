# App task and lifecycle continuity

October 23, 2026; feature branch `codex/app-lifecycle`.

## Evidence and causes

Android showed two Recents records for one installed package: task 57 from a bare ADB component intent and task 58 from the launcher MAIN/LAUNCHER intent. Back finished the first task, leaving an empty snapshot. Logs showed the Flutter engine detached and a new engine created in the same PID, rather than a crash or low-memory process exit. The former `singleTop` launch policy did not enforce one task across launch sources.

The map also treated `inactive`, `hidden` and `paused` as repeated teardown requests. It cleared following and restarted GPS on resume without waiting for earlier cancellation operations. `inactive` also occurs for brief focus changes such as the notification shade. The nested account Navigator did not explicitly route all system Back events before platform root exit. Map view state had no restoration scope.

## Implemented behavior

- Android `singleTask` reuses the activity for ordinary launcher and explicit component launches. Empty `taskAffinity` is retained. On creation only obsolete, empty task records belonging to this component are removed; live tasks and app data are preserved.
- `tool/open_preview.ps1` uses the same MAIN/LAUNCHER identity as the app icon. The root account `PopScope` asks its Navigator to pop/confirm a profile/game first. Root exit delegates through `SystemNavigator.pop` to the documented native `popSystemNavigator` hook, which backgrounds the root task.
- `MapLifecycle` ignores mere focus loss, deduplicates suspension/recovery and preserves following intent. GPS stop/start operations are serialized; a failed operation cannot poison the queue. Recovery checks permission without showing a dialog. Fresh fixes are required again for player rendering and proximity eligibility.
- `RestorationMixin` records one validated, versioned view snapshot: center, zoom, overview/exploration mode, follow intent and location opt-in. Restoration scopes isolate it by authenticated account. Initial route settings are retained so Flutter can restore child state. Initial fitting reapplies saved preferences after calculating bounds. GPS fixes, answers, HP and cooldowns are never restored as trusted local data.
- Style initialization is coalesced so map-created/style-loaded callbacks cannot compete over initial fitting. Normal resume retains the map instance and style.

## Online research actually read

- [Android tasks](https://developer.android.com/guide/components/activities/tasks-and-back-stack): launch modes, intent identity and root Back. Single-task behavior fits this single-activity Flutter app; it is not a universal recommendation.
- [Activity manifest](https://developer.android.com/guide/topics/manifest/activity-element): affinity and launch flags.
- [Flutter affinity security issue](https://github.com/flutter/flutter/issues/63559) and [Android StrandHogg guidance](https://developer.android.com/privacy-and-security/risks/strandhogg): preserve the existing affinity protection.
- [Flutter lifecycle](https://api.flutter.dev/flutter/dart-ui/AppLifecycleState.html): focus loss, hidden/paused and synthesized transitions.
- [Flutter restoration](https://docs.flutter.dev/platform-integration/android/restore-state-android) and [RestorationMixin](https://api.flutter.dev/flutter/widgets/RestorationMixin-mixin.html): ephemeral state, registration and disposal. Installed framework Navigator source was checked for restorable initial-route requirements.
- [PopScope](https://api.flutter.dev/flutter/widgets/PopScope-class.html), [NavigatorPopHandler](https://api.flutter.dev/flutter/widgets/NavigatorPopHandler-class.html) and [FlutterActivity hook](https://api.flutter.dev/javadoc/io/flutter/embedding/android/FlutterActivity.html#popSystemNavigator()): route-first Back and platform root behavior.
- [Mapbox camera guide](https://docs.mapbox.com/flutter/maps/guides/camera-and-animation/camera/): camera initialization, reads and updates.

## Verification

90 Flutter tests passed and analysis is clean. Tests cover focus versus visibility, deduplicated lifecycle transitions, serialized GPS cancellation/startup and recovery after errors, corrupt restoration data, account isolation, restorable initial routes and nested/root system Back. Existing game-host pause/resume checks passed too.

Native QA build 12043/versionCode 16043 on UTRGV_GO_Preview/emulator-5554 (Android API 36.1, x86_64, 1080×2400) passed notification-shade return, profile system Back, three Home/one-second/launcher cycles, Recents, root Back and explicit component relaunch. The driver compared map-widget identity, camera position/zoom/mode and follow intent. One process and one Recents entry remained across ordinary interruptions. `test_driver/lifecycle_flow.dart exercise|restore` reproduces these checks using the separate QA session and synthetic coordinates.

For process-death simulation, the emulator's Home/Settings transitions did not consistently complete a stopped activity. Turning the screen off produced a verified STOPPED activity and saved Android state bundle. Only the QA process was then terminated with its own UID, without force-stop, task removal or data clearing. Wake/relaunch created a new process/Flutter engine and restored the same camera, zoom, mode and visible **Following** control. An initial saved-data-only assertion missed follow being disabled during initial fitting; the final implementation reapplies that preference and the native test asserts the actual control. [Before](evidence/app-lifecycle/before.png), [restored](evidence/app-lifecycle/restored.png).

Normal preview restored in place as build 12044/versionCode 16044. The pulled installed APK matches the fresh artifact SHA-256 `3a62f18e97f6ec8e9f7cca04fa5ab4b353d44bc586db334cce88e3cb296a928c`; signing is unchanged. Existing normal-account data remains accessible. Emulator checks do not establish physical-device, older-Android or iOS acceptance. This was simulated process death after saved state, not an observed natural low-memory kill. Supabase schema/gameplay authority is unchanged. Pre-existing camera/cowboy work remains separately uncommitted.
