# Today — iOS training app

Private SwiftUI app. Pairs with the marathon coach in `../marathon-prep-bot` (it
publishes the weekly plan; this app displays it and syncs strength + body weight back).

## The naming trap — read this first

The folder is `today-fitness-ios` and the product is **Today**, but **only the outer
folder was renamed.** The Xcode project, target, scheme, and every internal path are
still literally `Health Tracker`:

- `Health Tracker.xcodeproj` · target `Health Tracker` · bundle `rohansingh.Health-Tracker`
- source dirs `Health Tracker/`, `Health TrackerTests/`, `Health TrackerUITests/`

**Do NOT "fix" this.** And note the space breaks unquoted shell commands — always quote.

## Build and test

```bash
xcodebuild -project "Health Tracker.xcodeproj" -scheme "Health Tracker" \
  -destination "platform=iOS Simulator,id=<udid>" \
  -skip-testing:"Health TrackerUITests/ScreenshotWalkthrough" \
  CODE_SIGNING_ALLOWED=NO test
```

- **`CODE_SIGNING_ALLOWED=NO` is required** off a signing-identity machine. It also means
  the simulator app has no `application-identifier` entitlement, so **Keychain writes
  return `errSecMissingEntitlement (-34018)`.** Code that stores secrets must surface
  that as its own error, never as "invalid input" — that exact masking cost a week of
  debugging in Jul 2026.
- **`TodayWidget` is a separate scheme** and is NOT built by the app scheme.
- **Always skip `ScreenshotWalkthrough`.** It is a screenshot harness, not assertions; it
  needs locally seeded state (`tools/seed-active-workout.sh`) and pushes CI past 27
  minutes against a 30-minute timeout. Run it deliberately with `-only-testing:` or not
  at all.
- No shared schemes are committed (only `xcuserdata`). `xcodebuild` auto-creates them on
  a clean clone. Don't add shared schemes without checking CI first.

## Two test frameworks

- **Unit tests are swift-testing** — `import Testing`, `@Test`, `#expect`. All of
  `Health TrackerTests/`.
- **UI tests are XCTest** — `XCUIApplication`. All of `Health TrackerUITests/`.

Don't write `XCTAssert` in a unit-test file. Note `#expect(throws:)` on an enum with an
associated value requires `Equatable` conformance.

**Never cite a test count from memory or from the README** — the README's number is
already stale and the count has leaked onto Rohan's resume twice. Run the suite or read
the assertion.

## Things that will bite you

- **HealthKit does not exist in Simulator.** Real Health reads, body-mass writes, sleep
  background delivery, and notifications only work on a physical iPhone. **CI passing
  proves nothing about those paths** — never report a HealthKit change as verified
  because CI is green.
- **UI-test timeouts are deliberately generous — do not tighten them.** 2s/5s passed on
  local M-series and failed on shared CI runners; the ceiling is now `uiTimeout = 20`.
  `waitForExistence` returns immediately on success, so a high ceiling costs nothing.
  Lowering it reintroduces a known flake.
- **CI picks the simulator by parsed model number, not name** (`ci.yml`). A name sort
  once chose "iPhone SE (3rd generation)" over "iPhone 17 Pro" because `"S" > "1"`,
  silently running CI on the slowest device. Don't simplify it back.
- **Widget data crosses an App Group** (`group.rohansingh.today`).
  `TodayWidgetShared/TodayWidgetSnapshot.swift` is the shared contract — changing its
  shape requires rebuilding both targets.
- **`web/` is a standalone Next.js app that CI does not touch.** `ci.yml` is iOS-only.
- **Coach sync has a strict production-endpoint allowlist** (`DataSafetyTests`). Tests
  must stay isolated from real sync. Treat that as an invariant.

## Getting it on the phone

Pushing to GitHub does **not** install anything. Run `./tools/install-on-phone.sh`.
The network blocks SSH:22, so the git remote is pinned to `ssh.github.com:443`.
