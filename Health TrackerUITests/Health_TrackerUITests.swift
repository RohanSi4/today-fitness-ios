import XCTest

final class Health_TrackerUITests: XCTestCase {
    /// How long to wait for an element that SHOULD appear.
    ///
    /// These were 2 and 5 seconds, which is comfortable on an M-series Mac and not
    /// on a shared CI runner: `testActiveWorkoutCanCloseAndResumeWithoutBeingDiscarded`
    /// passed locally every time and failed on CI, where a SwiftUI transition can
    /// easily outlast two seconds. A generous ceiling costs nothing when the app is
    /// healthy, because `waitForExistence` returns the moment the element shows up —
    /// it only changes how long a genuine failure takes to report.
    static let uiTimeout: TimeInterval = 20

    /// How long to wait for an element that may legitimately NOT be there.
    ///
    /// Deliberately short, and NOT `uiTimeout`: this one asks "did an earlier test
    /// leave a workout open?", where "no" is a normal answer. Waiting 20 seconds to
    /// hear it would add that to every clean run.
    static let probeTimeout: TimeInterval = 3

    @MainActor
    override func setUpWithError() throws {
        continueAfterFailure = false

        // Device orientation is simulator state, not process state: it outlives
        // the test run that set it. `Health_TrackerUITestsLaunchTests` has
        // `runsForEachTargetApplicationUIConfiguration = true`, which includes
        // landscape, and the app declares no supported orientations, so it
        // happily rotates. The run therefore *ends* in landscape and poisons the
        // next one - four tests here failed on a 956x440 window with the
        // controls they tap pushed below the fold, having passed minutes before
        // on identical code.
        //
        // These screens are designed portrait, so pinning it is both the honest
        // precondition and the thing that makes the suite reproducible.
        XCUIDevice.shared.orientation = .portrait
    }

    /// The app is portrait only, declared in build settings rather than at
    /// runtime, which means nothing in the Swift sources mentions it and a stray
    /// edit to the project file would go unnoticed. This is the guard.
    ///
    /// It is also the root cause of the flakiness the `setUpWithError` note
    /// describes: while landscape was allowed, the launch test's rotation
    /// outlived the run and broke the next one.
    @MainActor
    func testTheAppStaysPortraitWhenTheDeviceIsRotated() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-useMockData", "true"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: Self.uiTimeout))

        let portrait = app.windows.firstMatch.frame
        XCTAssertGreaterThan(portrait.height, portrait.width, "did not start portrait")

        defer { XCUIDevice.shared.orientation = .portrait }
        for orientation in [UIDeviceOrientation.landscapeLeft, .landscapeRight] {
            XCUIDevice.shared.orientation = orientation
            // The rotation is animated and the device may honour it even when the
            // app does not, so settle before measuring the app's own window.
            Thread.sleep(forTimeInterval: 1.5)

            let frame = app.windows.firstMatch.frame
            XCTAssertGreaterThan(
                frame.height,
                frame.width,
                "app rotated to \(orientation.rawValue); it is meant to be portrait only"
            )
        }
    }

    @MainActor
    func testTodayOpensTheFastWeightLogger() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-useMockData", "true"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: Self.uiTimeout))
        app.buttons["log-weight-button"].tap()
        XCTAssertTrue(app.navigationBars["Morning weight"].waitForExistence(timeout: Self.uiTimeout))
        XCTAssertTrue(app.buttons["Save weight"].exists)
        XCTAssertTrue(app.buttons["Adjust weight by +0.1 pounds"].exists)
    }

    @MainActor
    func testSampleRecapRemainsAvailableFromInsights() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-useMockData", "true"]
        app.launch()

        app.tabBars.buttons["Insights"].tap()
        app.buttons["sleep-movement-recap-button"].tap()
        XCTAssertTrue(app.staticTexts["Sample data"].waitForExistence(timeout: Self.uiTimeout))
        XCTAssertTrue(app.staticTexts["Sleep details"].exists)

        let recap = app.scrollViews["daily-recap-scroll"]
        XCTAssertTrue(recap.exists)
        recap.swipeUp()
        XCTAssertTrue(app.staticTexts["Movement"].waitForExistence(timeout: Self.uiTimeout))
    }

    @MainActor
    func testWeeklySnapshotOpensFromToday() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-useMockData", "true"]
        app.launch()

        let card = app.buttons["weekly-snapshot-card"]
        XCTAssertTrue(card.waitForExistence(timeout: Self.uiTimeout))
        card.tap()
        XCTAssertTrue(app.navigationBars["This week"].waitForExistence(timeout: Self.uiTimeout))
        XCTAssertTrue(app.descendants(matching: .any)["weekly-snapshot-table"].exists)
    }

    @MainActor
    func testStretchRoutineCanBeBrowsedAndGuided() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-useMockData", "true"]
        app.launch()

        let stretches = app.buttons["stretches-button"]
        XCTAssertTrue(stretches.waitForExistence(timeout: Self.uiTimeout))
        stretches.tap()

        XCTAssertTrue(app.navigationBars["Run stretches"].waitForExistence(timeout: Self.uiTimeout))
        let firstCard = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Butt kickers"))
            .firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: Self.uiTimeout))
        firstCard.tap()
        XCTAssertTrue((firstCard.value as? String)?.contains("Expanded") == true)

        let start = app.buttons["start-stretch-routine"]
        XCTAssertTrue(start.exists)
        start.tap()

        XCTAssertTrue(app.scrollViews["stretch-session-scroll"].waitForExistence(timeout: Self.uiTimeout))
        XCTAssertTrue(app.staticTexts["Butt kickers"].exists)
        app.buttons["complete-stretch-step"].tap()
        XCTAssertTrue(app.staticTexts["Frankensteins"].waitForExistence(timeout: Self.uiTimeout))
    }

    @MainActor
    func testPostRunHoldWaitsForPlayAndCanPauseOrOpenRoutineWheel() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-useMockData", "true"]
        app.launch()

        let stretches = app.buttons["stretches-button"]
        XCTAssertTrue(stretches.waitForExistence(timeout: Self.uiTimeout))
        stretches.tap()

        let postRun = app.segmentedControls.buttons["Post-run"]
        XCTAssertTrue(postRun.waitForExistence(timeout: Self.uiTimeout))
        postRun.tap()
        app.buttons["start-stretch-routine"].tap()

        let timerButton = app.buttons["stretch-timer-button"]
        XCTAssertTrue(timerButton.waitForExistence(timeout: Self.uiTimeout))
        XCTAssertEqual(timerButton.label, "Start 30-second hold")
        XCTAssertTrue(app.staticTexts["Ready when you are"].exists)

        timerButton.tap()
        XCTAssertEqual(timerButton.label, "Pause")

        app.buttons["stretch-step-picker-button"].tap()
        XCTAssertTrue(app.navigationBars["Routine wheel"].waitForExistence(timeout: Self.uiTimeout))
        XCTAssertTrue(app.pickers["stretch-step-picker"].exists)
        app.buttons["Cancel"].tap()
        XCTAssertEqual(timerButton.label, "Resume hold")

        timerButton.tap()
        XCTAssertEqual(timerButton.label, "Pause")
        timerButton.tap()
        XCTAssertEqual(timerButton.label, "Resume hold")
    }

    @MainActor
    func testActiveWorkoutCanCloseAndResumeWithoutBeingDiscarded() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-useMockData", "true"]
        app.launch()

        let resume = app.buttons["resume-workout-button"]
        if resume.waitForExistence(timeout: Self.probeTimeout) {
            resume.tap()
        } else {
            let start = app.buttons["start-workout-button"]
            XCTAssertTrue(start.waitForExistence(timeout: Self.uiTimeout))
            start.tap()
            let upper = app.buttons["start-upper-workout"]
            XCTAssertTrue(upper.waitForExistence(timeout: Self.uiTimeout))
            upper.tap()
        }

        let close = app.buttons["close-workout-button"]
        XCTAssertTrue(close.waitForExistence(timeout: Self.uiTimeout))
        XCTAssertTrue(app.buttons["workout-options-menu"].exists)
        close.tap()

        XCTAssertTrue(resume.waitForExistence(timeout: Self.uiTimeout))
        resume.tap()
        XCTAssertTrue(app.buttons["close-workout-button"].waitForExistence(timeout: Self.uiTimeout))
    }
}
