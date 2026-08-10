# Today real-device validation

Simulator and CI results do not validate HealthKit, signed Keychain access,
notifications, App Group/widget propagation, WorkoutKit, or a paired Apple Watch.
This is the release gate for those paths. A blank row means **not verified**.

## Run record

| Field | Value |
| --- | --- |
| Date | 2026-08-09 |
| Commit | `69bdba6` (post-run dashboard, progress-aware plan filtering, and prior widget hardening) |
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
pass. The exact build installed on iOS 26.6. The OS update reset Apple
Development trust and verification initially stalled until the phone could reach
Apple's PPQ service; after verification, automated launch and forced relaunch
both passed. CoreDevice showed both Today and TodayWidget alive. Read-only App
Group inspection first found a 42-byte keyless plist, proving v1 was deleted,
then found only the `today-widget-snapshot-v2` key after host-app publication.
No stored value was printed. On-screen widget and action checks remain hands-on.

Commit `69bdba6` replaces completed-run instructions with a factual dashboard
(distance, duration, pace, plan comparison, and—only when the run belongs to the
declared week—weekly impact). It preserves remaining lift, swim, and unknown
tasks instead of guessing that they are complete. The signed commit installed
and launched on the iPhone. Read-only app-container inspection confirmed that
the production Aug 9 bridge day was accepted and cached; the former validator
rejected that payload because its declared Aug 10–16 week deliberately included
Aug 9 for the Sunday handoff. Bridge activity is excluded from the new week's
totals. Whether the real Health run selected the dashboard and whether the
layout is usable remain hands-on checks.

Do not paste body weight, tokens, encryption keys, pairing codes, precise workout
routes, or screenshots containing those values into this file.

## Preconditions

- [x] Working tree and commit under test recorded above.
- [x] iPhone is unlocked, trusted, and paired to the intended Apple Watch.
- [x] Health contains a known recent run and sleep sample that are safe to inspect.
- [ ] Coach transport secrets are configured at the allowlisted production endpoint.
- [x] Current coach has published a seven-day plan plus the intentional prior-day bridge.
- [x] Today is installed from this checkout with `./tools/install-on-phone.sh`.
- [x] Today widget is installed on the Lock Screen or Home Screen.

## Required evidence

Mark each row `PASS` or `FAIL` and add concise, non-sensitive evidence. `N/A` is
not acceptable for a release-gating row.

| ID | Path | Check | Status | Evidence / defect |
| --- | --- | --- | --- | --- |
| D01 | Signed install | App launches as **Today** after a fresh signed install and again after force-quit. | | Exact `69bdba6` upgrade install and launch passed on iOS 26.6. Earlier forced termination and relaunch passed after online developer verification. Fresh uninstall/reinstall was not run because it would erase local state. |
| D02 | Health authorization | First launch requests only the expected Health read/write permissions; denial leaves the app usable. | | |
| D03 | Health reads | Insights shows the known run, sleep, and movement data without sample-data labels. | PASS | Rohan answered yes after checking Insights with recent real run and sleep data. |
| D04 | Body-mass write | Enter a distinctive test weight, verify one matching Apple Health sample, then correct it and verify replacement behavior. | | |
| D05 | Keychain | Pair coach sync, force-quit, relaunch, and confirm credentials persist without an entitlement or “invalid code” error. | | Rohan answered “probably”; no observed force-quit/relaunch result, so this is not evidence of a pass. |
| D06 | Private sync | Log a test lift and weight, sync, and confirm the coach decrypts the private snapshot. | | |
| D07 | Public boundary | Confirm the public fitness page shows only split, duration, working sets, and broad muscles; no exact weight, exercise detail, token, or route appears. | | |
| D08 | Offline retry | Disable connectivity, save a change, confirm pending state, restore connectivity, and confirm one successful retry without duplicate data. | | |
| D09 | Widget/App Group | After weight, lift, and plan changes, confirm the installed widget refreshes; weekly totals may appear, but exact weight, exercise detail, token, and route must not. | FAIL | Earlier installed widget showed exercise/workout detail. On `7c07626`, physical App Group inspection proved v1 was deleted and only v2 existed after launch; both app and extension processes were alive. All three widget deep-link URLs launched successfully on-device. On-screen privacy, real-change refresh, and medium/large layout/action observation remain before retest can pass. |
| D10 | Notifications | With permission granted, confirm the scheduled 8:30 AM and noon behavior; with permission denied, confirm no misleading enabled state. | | |
| D11 | Wake-aware reminder | After a completed Health sleep session, confirm the reminder reschedules as documented. | | |
| D12 | WorkoutKit | Send today’s run to Apple Watch, confirm distance/location, and repeat to prove duplicate-safe replacement. | | |
| D13 | Watch completion | Complete or use a safe short test run on Watch; confirm HealthKit ingestion updates Today and the widget without creating a second workout. | | |
| D14 | Protected persistence | Start a lift, lock the phone, unlock, force-quit, and confirm the active session and last-good recovery remain intact. | | |
| D15 | App Shortcuts | From Shortcuts or Spotlight, open weight, plan, and workout picker intents and verify the intended destinations. | | Direct physical delivery of `today://weight`, `today://`, and `today://workout` each launched the app successfully. That proves URL plumbing, not invocation from Shortcuts/Spotlight or the visible destination, so this remains unverified. |
| D16 | Post-run progression | After a real completed run, Today replaces run instructions with the dashboard, shows no stale run/fueling cues, and preserves any lift or swim still planned. | | Exact `69bdba6` installed and launched; production bridge plan accepted and cached. On-screen dashboard selection, copy, and layout await Rohan's observation. |

## Exit criteria

- Every D01-D16 row is `PASS` on the recorded commit.
- Any failure has a reproducible defect with observed result, expected result, and
  device/OS details.
- Run the automated app suite and the separate `TodayWidget` build on the same
  commit; record their results below, but do not use them as substitutes for D01-D15.

| Automated check | Result |
| --- | --- |
| App unit/UI suite (ScreenshotWalkthrough skipped) | PASS — full simulator `xcodebuild test` exited 0 against `69bdba6` source on 2026-08-09; Xcode recovered from one transient UI-runner clone launch denial and every listed UI test passed. |
| TodayWidget build | PASS — redesigned widget built for iOS Simulator and as part of the signed `69bdba6` iPhone install; privacy and unsafe-v1 migration tests passed on 2026-08-09. Installation/visual proof is tracked separately in D09. |

Release decision: **NOT VERIFIED** until every required row is completed.
