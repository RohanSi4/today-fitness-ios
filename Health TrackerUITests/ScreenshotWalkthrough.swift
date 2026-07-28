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
        shoot(app, "03a-health-sheet-as-he-sees-it")
        // Only present until the simulator has an answer on record for this
        // bundle id, so its absence on a re-run is not a failure.
        dismissHealthSheet(deny: true)
        Thread.sleep(forTimeInterval: 2)
        // The one that matters: Health was refused, so did the weight survive?
        shoot(app, "03b-after-weight-save-health-denied")

        // The weight chart. This is the 0-200 complaint.
        if app.navigationBars["Morning weight"].exists {
            app.navigationBars.buttons.element(boundBy: 0).tap()
            Thread.sleep(forTimeInterval: 1)
        }
        app.tabBars.buttons["Insights"].tap()
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
        app.tabBars.buttons.element(boundBy: 0).tap()
        Thread.sleep(forTimeInterval: 1)
        let resume = app.buttons["resume-workout-button"]
        if resume.waitForExistence(timeout: 2) {
            resume.tap()
        } else {
            app.buttons["start-workout-button"].tap()
            XCTAssertTrue(app.buttons["start-upper-workout"].waitForExistence(timeout: 5))
            shoot(app, "07-workout-start-flow")
            app.buttons["start-upper-workout"].tap()
        }
        XCTAssertTrue(app.buttons["close-workout-button"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "08-active-workout")

        // The per-exercise options menu is where the brand picker lives. Matching
        // on "ENDSWITH options" was wrong: the workout's own menu matches it too
        // and sorts first, so the first run photographed "Discard workout".
        // Not an exact label. Once a maker is remembered the row opens branded, so
        // the menu is "Lat pulldown (Life Fitness) options" rather than the bare
        // name. Anchoring on the movement and the suffix survives both.
        let optionsMenu = app.descendants(matching: .any)
            .matching(
                NSPredicate(
                    format: "label BEGINSWITH %@ AND label ENDSWITH %@",
                    "Lat pulldown", " options"
                )
            )
            .firstMatch
        XCTAssertTrue(optionsMenu.waitForExistence(timeout: 5))
        optionsMenu.tap()
        Thread.sleep(forTimeInterval: 1.5)
        shoot(app, "09-exercise-options-menu")

        // The picker is an inline Picker inside that menu, so the makers are
        // already on screen and each one is its own row.
        let lifeFitness = app.buttons["Life Fitness"].firstMatch
        if lifeFitness.waitForExistence(timeout: 3) {
            shoot(app, "10-brand-picker")
            lifeFitness.tap()
            Thread.sleep(forTimeInterval: 2)
            shoot(app, "11-brand-chip-on-card")
        } else {
            let machineBrand = app.buttons["Machine brand"].firstMatch
            if machineBrand.waitForExistence(timeout: 2) {
                machineBrand.tap()
                Thread.sleep(forTimeInterval: 1.5)
                shoot(app, "10-brand-picker")
                app.buttons["Life Fitness"].firstMatch.tap()
                Thread.sleep(forTimeInterval: 2)
                shoot(app, "11-brand-chip-on-card")
            }
        }

        // The exercise picker, which is where 252 exercises have to stay findable.
        let addExercise = app.buttons["Add exercise"].firstMatch
        if addExercise.waitForExistence(timeout: 3) {
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
    }
}
