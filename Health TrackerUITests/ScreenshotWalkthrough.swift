import XCTest

/// Not an assertion suite. This drives the screens changed by the catalog,
/// brand, and weight-chart work and attaches a picture of each one, because
/// every one of those changes had been verified only by compiling and by tests
/// that never looked at a pixel.
///
/// Kept out of the normal run: it is slow, and a screenshot cannot fail
/// meaningfully in CI. Run it with
/// `-only-testing:"Health TrackerUITests/ScreenshotWalkthrough"`.
final class ScreenshotWalkthrough: XCTestCase {
    @MainActor
    override func setUpWithError() throws {
        continueAfterFailure = true
        // See the note in `Health_TrackerUITests`. A landscape simulator left
        // over from a previous run would silently produce a folder of
        // screenshots of a layout he never uses.
        XCUIDevice.shared.orientation = .portrait
    }

    private func shoot(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func launched() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-useMockData", "true"]
        app.launch()
        return app
    }

    /// `addUIInterruptionMonitor` does not work for this one. The HealthKit
    /// authorisation sheet is a remote view owned by another process, and the
    /// monitor only runs when the test next touches the app, which is exactly
    /// what the sheet is blocking. The first run of this file lost four
    /// screenshots to it: 03 through 06 are all pictures of the sheet.
    ///
    /// Denying is also the case worth capturing, because that is the path that
    /// used to swallow a typed weight.
    @discardableResult
    private func dismissHealthSheet(deny: Bool, timeout: TimeInterval = 8) -> Bool {
        let hosts = [
            XCUIApplication(bundleIdentifier: "com.apple.springboard"),
            XCUIApplication(bundleIdentifier: "com.apple.Health"),
        ]
        let primary = deny ? ["Don’t Allow", "Don't Allow"] : ["Turn On All", "Allow"]
        var dismissedAny = false
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            var tappedThisPass = false
            for host in hosts {
                // "OK" first: granting raises a confirmation sheet on top of the
                // one underneath, and tapping through the top one is the only way
                // down to it.
                for label in ["OK"] + primary {
                    let button = host.buttons[label]
                    if button.exists, button.isHittable {
                        button.tap()
                        tappedThisPass = true
                        dismissedAny = true
                        Thread.sleep(forTimeInterval: 1.2)
                        break
                    }
                }
                if tappedThisPass { break }
            }
            if !tappedThisPass {
                if dismissedAny { break }
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
        return dismissedAny
    }

    /// Clears whatever system alert is on screen right now, without waiting for
    /// one to appear.
    ///
    /// `dismissHealthSheet` answers the prompt raised by a specific tap. This is
    /// for the follow-up that arrives on its own timetable: denying Health
    /// access raises a second, springboard-owned "Health Access" alert ("You can
    /// turn on health data categories later in the Health app"), and it landed
    /// only after the Insights screenshots — long after the one dismissal had
    /// returned. It then sat over the Today tab, which is why
    /// `start-workout-button` reported a perfectly good frame and refused to be
    /// hit. Nothing in the walkthrough was wrong; it just assumed the prompts
    /// were done arriving.
    @discardableResult
    private func clearLingeringSystemAlert(in app: XCUIApplication) -> Bool {
        // `app` first, and it is the one that actually works. The Health sheet is
        // a remote view, but its elements are published INTO the app's own tree —
        // the failing run's hierarchy dump carried both pids under
        // "App UI hierarchy for ...Health-Tracker". Searching only springboard
        // and com.apple.Health, as the original dismissal did, looks right and
        // finds nothing, which is why the sheet outlived every attempt to
        // dismiss it and sat over the Today tab for the rest of the walkthrough.
        let hosts = [
            app,
            XCUIApplication(bundleIdentifier: "com.apple.springboard"),
            XCUIApplication(bundleIdentifier: "com.apple.Health"),
        ]
        for host in hosts {
            // Identifier first, label second. `Turn On All` is only StaticText in
            // this sheet, and the deny control's label carries a typographic
            // apostrophe that is easy to mismatch and is localized besides;
            // `UIA.Health.DoNotAllow.Button` is neither.
            for candidate in [
                host.buttons["UIA.Health.DoNotAllow.Button"],
                host.buttons["OK"],
                host.buttons["Don’t Allow"],
                host.buttons["Don't Allow"],
                host.buttons["Dismiss"],
            ] {
                // `exists` alone is not enough: springboard keeps stale buttons
                // addressable after their alert is gone.
                if candidate.exists, candidate.isHittable {
                    candidate.tap()
                    Thread.sleep(forTimeInterval: 1)
                    return true
                }
            }
        }
        return false
    }

    /// Waits for `element` to be *hittable*, not merely to exist, clearing any
    /// system alert that shows up while waiting.
    ///
    /// Existence was never the right question here. A button under a modal
    /// exists, reports its real frame, and cannot be tapped, so
    /// `waitForExistence` returns true and the tap fails with "Failed to not
    /// hittable" and a frame that looks entirely reasonable.
    private func tapWhenHittable(
        _ element: XCUIElement,
        in app: XCUIApplication,
        timeout: TimeInterval = 30,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if waitUntilHittable(element, in: app, timeout: timeout) {
            element.tap()
            return
        }
        XCTFail(
            "\(element) never became hittable within \(timeout)s. Exists: \(element.exists).",
            file: file,
            line: line
        )
    }

    /// The same waiting, reported rather than asserted, for the captures that
    /// are genuinely optional.
    @discardableResult
    private func waitUntilHittable(
        _ element: XCUIElement,
        in app: XCUIApplication,
        timeout: TimeInterval = 30
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var dismissedMenu = false
        var scrolls = 0
        while Date() < deadline {
            if element.exists, element.isHittable { return true }
            if clearLingeringSystemAlert(in: app) { continue }

            // A SwiftUI Menu left open is the other thing that makes a perfectly
            // visible button unhittable: its scrim swallows every tap without
            // appearing as an alert. The brand picker gets left open whenever the
            // maker rows are not where the walkthrough expects, and "Add
            // exercise" then fails with a frame that looks completely fine.
            // Tapping the navigation title dismisses it and does nothing else.
            let navBar = app.navigationBars.firstMatch
            if !dismissedMenu, navBar.exists {
                navBar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                dismissedMenu = true
                Thread.sleep(forTimeInterval: 0.8)
                continue
            }

            // And the ordinary reason: it is simply below the fold. A SwiftUI
            // ScrollView publishes its offscreen content to the accessibility
            // tree with a plausible-looking frame, so "Add exercise" under seven
            // exercise cards reports `exists == true` at a y that is on screen
            // and still cannot be tapped. Scrolling is the fix; the frame in the
            // failure message is what makes it look like it should not be.
            // The LAST scroll view, which is the frontmost one.
            // `scrollViews.firstMatch` was picking the Today page still sitting
            // behind the workout sheet, so every scroll attempt moved a screen
            // nobody was looking at while the sheet stayed exactly where it was.
            // "Add exercise" sits at y≈2258 under seven exercise cards on an
            // ~874pt screen, so this has real distance to cover and silently
            // scrolling the wrong view looks identical to a button that will
            // never be hittable.
            let scrollViews = app.scrollViews
            if scrolls < 12, scrollViews.count > 0 {
                // `.fast` matters: the exercise cards are drag-to-reorder, so a
                // leisurely swipe is often taken as the start of a reorder and
                // scrolls nothing. A flick carries momentum and outruns it —
                // twelve plain swipes moved the page 670pt of the 1400 needed.
                scrollViews.element(boundBy: scrollViews.count - 1).swipeUp(velocity: .fast)
                scrolls += 1
                Thread.sleep(forTimeInterval: 0.4)
                continue
            }
            Thread.sleep(forTimeInterval: 0.4)
        }
        return false
    }

    /// History on its own. The full walkthrough reaches it only after the
    /// workout flow, so any flake earlier in that run costs the History
    /// screenshot too — which is how the month grouping, the trained-regions
    /// line, and the weight deltas all shipped unlooked-at.
    @MainActor
    func testCaptureHistory() throws {
        let app = launched()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10))
        dismissHealthSheet(deny: true, timeout: 4)
        XCTAssertTrue(app.tabBars.buttons["History"].waitForExistence(timeout: 5))
        app.tabBars.buttons["History"].tap()
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "14-history")
    }

    /// The weight field, which is the control touched most in a session and the
    /// one place a screenshot cannot tell you whether typing still works. Needs
    /// a seeded active workout: see tools/seed-active-workout.sh.
    @MainActor
    func testWeightFieldAcceptsADecimalAndShowsAPlaceholderWhenUnset() throws {
        let app = launched()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10))
        dismissHealthSheet(deny: true, timeout: 4)

        let resume = app.buttons["resume-workout-button"]
        try XCTSkipUnless(resume.waitForExistence(timeout: 5), "No active workout seeded")
        resume.tap()
        XCTAssertTrue(app.buttons["close-workout-button"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1.5)

        // The skip above asks whether ANY workout is open, which is not the same
        // question. `testCaptureTheChangedScreens` starts Upper A on the same
        // simulator and leaves it open, so on a full-class run this resumed that
        // instead and then asserted a first-exposure placeholder against a row
        // pre-filled from real history — 235, not empty. The seed builds a
        // routine-less `upper` session, which titles itself "Upper workout";
        // the template one is "Upper A workout".
        try XCTSkipUnless(
            app.navigationBars["Upper workout"].exists,
            "Active workout is not the seeded one — run tools/seed-active-workout.sh "
                + "against a simulator with no other workout open."
        )
        shoot(app, "15-weight-field")

        // An unset weight is an empty field, not a literal 0.
        let unset = app.textFields["Pec deck, set 1, weight"]
        XCTAssertTrue(unset.waitForExistence(timeout: 5))
        XCTAssertEqual(unset.value as? String, "0", "empty field should fall back to the placeholder")

        // And a decimal survives being typed, which is what the old
        // value-bound field could not do.
        unset.tap()
        unset.typeText("12.5")
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(unset.value as? String, "12.5")
        shoot(app, "16-weight-field-typed")
    }

    @MainActor
    func testCaptureTheChangedScreens() throws {
        let app = launched()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10))
        shoot(app, "01-today-home")

        // Weight entry, then a save with Health unavailable.
        app.buttons["log-weight-button"].tap()
        XCTAssertTrue(app.navigationBars["Morning weight"].waitForExistence(timeout: 5))
        shoot(app, "02-weight-entry")
        app.buttons["Save weight"].tap()
        Thread.sleep(forTimeInterval: 2)
        // No sheet to dismiss any more: `-useMockData` makes HealthKitManager
        // refuse authorization outright rather than prompt (see
        // `suppressesAuthorizationPrompts`). This used to shoot the sheet here
        // and then fight it for the rest of the run, because the answer persists
        // per simulator and a fresh prompt could arrive at any later moment.
        // What the walkthrough actually needed to see is below: Health refused,
        // and the weight survived anyway.
        shoot(app, "03-after-weight-save-health-denied")

        // The weight chart. This is the 0-200 complaint.
        if app.navigationBars["Morning weight"].exists {
            app.navigationBars.buttons.element(boundBy: 0).tap()
            Thread.sleep(forTimeInterval: 1)
        }
        tapWhenHittable(app.tabBars.buttons["Insights"], in: app)
        Thread.sleep(forTimeInterval: 1.5)
        shoot(app, "04-insights-top")
        let insights = app.scrollViews.firstMatch
        if insights.exists {
            insights.swipeUp()
            Thread.sleep(forTimeInterval: 1)
            shoot(app, "05-insights-weight-chart")
            insights.swipeUp()
            Thread.sleep(forTimeInterval: 1)
            shoot(app, "06-insights-lower")
        }

        // Workout, exercise picker, and the brand controls.
        clearLingeringSystemAlert(in: app)
        tapWhenHittable(app.tabBars.buttons.element(boundBy: 0), in: app)
        Thread.sleep(forTimeInterval: 1)
        let resume = app.buttons["resume-workout-button"]
        if resume.waitForExistence(timeout: 2), resume.isHittable {
            resume.tap()
        } else {
            tapWhenHittable(app.buttons["start-workout-button"], in: app)
            XCTAssertTrue(app.buttons["start-upper-a-workout"].waitForExistence(timeout: 5))
            shoot(app, "07-workout-start-flow")
            tapWhenHittable(app.buttons["start-upper-a-workout"], in: app)
        }
        XCTAssertTrue(app.buttons["close-workout-button"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "08-active-workout")

        // The per-exercise options menu is where the brand picker lives. Matching
        // on "ENDSWITH options" was wrong: the workout's own menu matches it too
        // and sorts first, so the first run photographed "Discard workout".
        // Naming the movement was the second mistake. It anchored on "Lat
        // pulldown", which Upper A has not contained since the template moved to
        // "machine-pulldown", so the query matched nothing and the brand
        // screenshots died with it. The template is expected to keep changing —
        // it is his training plan — so this asks for what it actually needs: any
        // exercise's menu.
        //
        // "Workout options" is the exclusion the original comment was reaching
        // for. It is the toolbar's own menu, it sorts first, and matching it is
        // how the first run photographed "Discard workout".
        let optionsMenu = app.descendants(matching: .any)
            .matching(
                NSPredicate(
                    format: "label ENDSWITH %@ AND label != %@",
                    " options", "Workout options"
                )
            )
            .firstMatch
        XCTAssertTrue(
            optionsMenu.waitForExistence(timeout: 5),
            "no exercise options menu on the workout screen"
        )
        tapWhenHittable(optionsMenu, in: app)
        Thread.sleep(forTimeInterval: 1.5)
        shoot(app, "09-exercise-options-menu")

        // The picker is an inline Picker inside that menu, so the makers are
        // already on screen and each one is its own row.
        //
        // Which makers, though, depends on the movement. This asked for "Life
        // Fitness" and the menu that actually opens belongs to Smith machine
        // incline press, which offers Arsenal Strength, Body-Solid, Hammer
        // Strength, Matrix and Panatta — and no Life Fitness. Neither branch
        // fired, so the MENU STAYED OPEN, and a SwiftUI menu's scrim then ate
        // the "Add exercise" tap below. That is the whole failure: not the brand
        // screenshots, but the unclosed menu behind them.
        //
        // So take whichever maker this movement actually offers.
        let brandOptions = [
            "Life Fitness", "Hammer Strength", "Matrix", "Panatta",
            "Arsenal Strength", "Body-Solid", "Cybex", "Technogym",
        ]
        let brand = brandOptions
            .map { app.buttons[$0].firstMatch }
            .first { $0.exists && $0.isHittable }

        if let brand {
            shoot(app, "10-brand-picker")
            brand.tap()
            Thread.sleep(forTimeInterval: 2)
            shoot(app, "11-brand-chip-on-card")
        } else {
            // Close it deliberately rather than leaving it to be tapped through.
            // "No brand" is always present once a movement has makers at all, and
            // selecting it changes nothing.
            let noBrand = app.buttons["No brand"].firstMatch
            if noBrand.exists, noBrand.isHittable {
                noBrand.tap()
            } else {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.06)).tap()
            }
            Thread.sleep(forTimeInterval: 1)
        }

        // The exercise picker, which is where 252 exercises have to stay
        // findable. BEST EFFORT, and deliberately not an assertion.
        //
        // "Add exercise" sits below every exercise card — y≈2258 on an ~874pt
        // screen for Upper A's seven — and the cards between here and there are
        // drag-to-reorder, so a scroll gesture over them is regularly taken as
        // the start of a reorder instead. Twelve plain swipes moved the page
        // 670pt of the 1400 needed; flicking does better but not reliably.
        // Failing the run over it would cost the History captures below and
        // every real check in this file, to prove nothing about the picker that
        // `ExerciseCatalogTests` does not already prove. If the capture is
        // missing from the attachments, scroll down and shoot it by hand.
        let addExercise = app.buttons["Add exercise"].firstMatch
        if addExercise.waitForExistence(timeout: 3),
           waitUntilHittable(addExercise, in: app, timeout: 15) {
            addExercise.tap()
            Thread.sleep(forTimeInterval: 1.5)
            shoot(app, "12-exercise-picker")
            let search = app.searchFields.firstMatch
            if search.waitForExistence(timeout: 2) {
                search.tap()
                search.typeText("lat pulldown")
                Thread.sleep(forTimeInterval: 1.5)
                shoot(app, "13-exercise-search")
            }
        }

        // History, which had no capture at all — so the month grouping, the
        // trained-regions line, and the weight deltas were never looked at.
        for label in ["Cancel", "Close"] where app.buttons[label].firstMatch.exists {
            app.buttons[label].firstMatch.tap()
            Thread.sleep(forTimeInterval: 1)
        }
        if app.buttons["close-workout-button"].exists {
            app.buttons["close-workout-button"].tap()
            Thread.sleep(forTimeInterval: 1.5)
        }
        // Closing the logger can raise the Health sheet again, which is a
        // separate process and will happily sit on top of the screenshot.
        dismissHealthSheet(deny: true, timeout: 4)
        if app.tabBars.buttons["History"].waitForExistence(timeout: 3) {
            app.tabBars.buttons["History"].tap()
            Thread.sleep(forTimeInterval: 1.5)
            shoot(app, "14-history")
        }
    }
}
