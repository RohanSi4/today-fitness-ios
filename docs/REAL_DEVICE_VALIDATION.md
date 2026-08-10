# Today real-device validation

Simulator and CI results do not validate HealthKit, signed Keychain access,
notifications, App Group/widget propagation, WorkoutKit, or a paired Apple Watch.
This is the release gate for those paths. A blank row means **not verified**.

## Run record

| Field | Value |
| --- | --- |
| Date | 2026-08-09 |
| Commit | `7c07626` (expanded widget, privacy-safe payload, and legacy-payload retirement) |
| Tester | Codex automation; hands-on checks require Rohan |
| iPhone model / iOS | iPhone 17 Pro Max / iOS 26.6; paired over USB |
| Apple Watch model / watchOS | Apple Watch Ultra 2; paired and available; OS version not reported |
| Signing team | `46Q2G4XNBY` / automatic Apple Development signing |
| Coach endpoint environment | production allowlisted endpoint |

Execution resumed after the iPhone connected over USB. The installer initially
rejected CoreDevice's valid `connected` state because it accepted only
`available`; the device parser was fixed and shell-validated. A signed debug
build then installed over the existing Today app and launched successfully. A
second launch with `--terminate-existing` also succeeded. Rohan confirmed the
app opened normally. The app was not uninstalled because doing so would erase
local state, so this is an upgrade-path check, not the fresh-install proof
required by D01.

The installed widget exposed exercise/workout detail, so D09 failed. Commit
`605744e` replaces exact daily plan/completion copy with generic status, adds
medium and large layouts, and adds Weight, Plan, and Workout deep-link actions.
Commit `7c07626` also retires and deletes the unsafe v1 App Group payload so an
upgraded widget cannot render cached private copy before the host app launches.
The code-level regression tests, simulator widget build, and signed-device build
pass. The exact build installed on iOS 26.6, but iOS refused automated launch
until the Apple Development profile is explicitly trusted after the OS update;
hands-on launch and widget refresh checks are still required before D09 can be
retested.

Do not paste body weight, tokens, encryption keys, pairing codes, precise workout
routes, or screenshots containing those values into this file.

## Preconditions

- [x] Working tree and commit under test recorded above.
- [x] iPhone is unlocked, trusted, and paired to the intended Apple Watch.
- [x] Health contains a known recent run and sleep sample that are safe to inspect.
- [ ] Coach transport secrets are configured at the allowlisted production endpoint.
- [ ] Current coach has published a seven-day plan.
- [x] Today is installed from this checkout with `./tools/install-on-phone.sh`.
- [x] Today widget is installed on the Lock Screen or Home Screen.

## Required evidence

Mark each row `PASS` or `FAIL` and add concise, non-sensitive evidence. `N/A` is
not acceptable for a release-gating row.

| ID | Path | Check | Status | Evidence / defect |
| --- | --- | --- | --- | --- |
| D01 | Signed install | App launches as **Today** after a fresh signed install and again after force-quit. | | Earlier signed upgrade install, launch, forced termination, and relaunch passed; Rohan confirmed the app opened normally. Exact `7c07626` upgrade install passed on iOS 26.6, but launch was denied until the development profile is explicitly trusted. Fresh uninstall/reinstall was not run because it would erase local state. |
| D02 | Health authorization | First launch requests only the expected Health read/write permissions; denial leaves the app usable. | | |
| D03 | Health reads | Insights shows the known run, sleep, and movement data without sample-data labels. | PASS | Rohan answered yes after checking Insights with recent real run and sleep data. |
| D04 | Body-mass write | Enter a distinctive test weight, verify one matching Apple Health sample, then correct it and verify replacement behavior. | | |
| D05 | Keychain | Pair coach sync, force-quit, relaunch, and confirm credentials persist without an entitlement or “invalid code” error. | | Rohan answered “probably”; no observed force-quit/relaunch result, so this is not evidence of a pass. |
| D06 | Private sync | Log a test lift and weight, sync, and confirm the coach decrypts the private snapshot. | | |
| D07 | Public boundary | Confirm the public fitness page shows only split, duration, working sets, and broad muscles; no exact weight, exercise detail, token, or route appears. | | |
| D08 | Offline retry | Disable connectivity, save a change, confirm pending state, restore connectivity, and confirm one successful retry without duplicate data. | | |
| D09 | Widget/App Group | After weight, lift, and plan changes, confirm the installed widget refreshes; weekly totals may appear, but exact weight, exercise detail, token, and route must not. | FAIL | Earlier installed widget showed exercise/workout detail. The migration-safe `7c07626` build is installed and deletes the unsafe v1 payload, but trust-gated launch, refresh, and on-screen observation remain before retest. |
| D10 | Notifications | With permission granted, confirm the scheduled 8:30 AM and noon behavior; with permission denied, confirm no misleading enabled state. | | |
| D11 | Wake-aware reminder | After a completed Health sleep session, confirm the reminder reschedules as documented. | | |
| D12 | WorkoutKit | Send today’s run to Apple Watch, confirm distance/location, and repeat to prove duplicate-safe replacement. | | |
| D13 | Watch completion | Complete or use a safe short test run on Watch; confirm HealthKit ingestion updates Today and the widget without creating a second workout. | | |
| D14 | Protected persistence | Start a lift, lock the phone, unlock, force-quit, and confirm the active session and last-good recovery remain intact. | | |
| D15 | App Shortcuts | From Shortcuts or Spotlight, open weight, plan, and workout picker intents and verify the intended destinations. | | Rohan answered “probably”; the three destinations were not individually observed, so this remains unverified. |

## Exit criteria

- Every D01-D15 row is `PASS` on the recorded commit.
- Any failure has a reproducible defect with observed result, expected result, and
  device/OS details.
- Run the automated app suite and the separate `TodayWidget` build on the same
  commit; record their results below, but do not use them as substitutes for D01-D15.

| Automated check | Result |
| --- | --- |
| App unit/UI suite (ScreenshotWalkthrough skipped) | PASS — full simulator `xcodebuild test` exited 0 against `7c07626` on 2026-08-09; Xcode retried one transient UI-runner clone launch before every UI test passed. |
| TodayWidget build | PASS — redesigned widget built for iOS Simulator and as part of the signed `7c07626` iPhone install; privacy and unsafe-v1 migration tests passed on 2026-08-09. Installation/visual proof is tracked separately in D09. |

Release decision: **NOT VERIFIED** until every required row is completed.
