//
//  Health_TrackerUITestsLaunchTests.swift
//  Health TrackerUITests
//
//  Created by Rohan Singh on 6/17/25.
//

import XCTest

final class Health_TrackerUITestsLaunchTests: XCTestCase {

    // Was `true`, which ran this test once per UI configuration — including
    // landscape. Two costs, both paid on CI: it multiplied the slowest test in the
    // suite, and it left the simulator rotated, which is the poisoning
    // `Health_TrackerUITests.setUpWithError` exists to undo. The app is portrait
    // only, so the extra configurations were never exercising a supported state.
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        false
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        // Every other UI test launches with mock data; this one did not, and that is
        // why it failed only on CI. Without it the app asks a clean simulator for
        // real HealthKit authorization, and the test sat on a permission dialog it
        // never dismissed — 74 seconds before CI gave up on it.
        app.launchArguments = ["-useMockData", "true"]
        app.launch()

        // A screenshot alone asserted nothing: the app could have launched to a blank
        // window and this still would have "passed". Now it is a real smoke test of
        // the launch path.
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 30))

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
