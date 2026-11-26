import XCTest

final class OnboardingUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testWelcomeLeadsToMicrophoneStep() {
        let app = XCUIApplication.fresh()
        app.launch()
        app.buttons["Get Started"].tap()
        XCTAssertTrue(app.staticTexts["Microphone Access"].waitForExistence(timeout: 5))
    }

    func testAllowingMicrophoneAdvancesToModelDownload() {
        let app = XCUIApplication.fresh()
        app.resetAuthorizationStatus(for: .microphone)
        app.launch()
        app.buttons["Get Started"].tap()
        app.buttons["Allow Microphone"].tap()
        XCTAssertTrue(Springboard.tapAlertButton("Allow"), "no microphone permission alert")
        XCTAssertTrue(app.staticTexts["Download Speech Model"].waitForExistence(timeout: 5))
    }

    /// Regression (H9): denying the microphone must leave the user a way forward.
    func testDenyingMicrophoneOffersAWayToSettings() {
        let app = XCUIApplication.fresh()
        app.resetAuthorizationStatus(for: .microphone)
        app.launch()
        app.buttons["Get Started"].tap()
        app.buttons["Allow Microphone"].tap()
        XCTAssertTrue(Springboard.tapAlertButton("Don’t Allow") || Springboard.tapAlertButton("Don't Allow"))
        XCTAssertTrue(app.staticTexts["Microphone Access"].waitForExistence(timeout: 3), "should stay on the step")
        XCTAssertTrue(app.buttons["Open Settings"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Allow Microphone"].exists, "the dead-end button is replaced")
    }

    /// The whole flow with a small model: download → Apple Intelligence →
    /// keyboard setup → Home, which should then report Ready.
    func testCompleteOnboardingWithTinyModel() throws {
        // Downloads a model and starts the keep-alive audio session, which
        // needs a working simulator microphone. Opt in with
        // TEST_RUNNER_WHISPIT_FULL_ONBOARDING=1 xcodebuild test …
        try XCTSkipUnless(ProcessInfo.processInfo.environment["WHISPIT_FULL_ONBOARDING"] == "1",
                          "Set WHISPIT_FULL_ONBOARDING=1 to run (needs network + simulator mic)")
        let app = XCUIApplication.fresh(["-WhispItModelVariant", "openai_whisper-tiny"])
        app.launch()
        app.buttons["Get Started"].tap()
        let micButton = app.buttons["Continue"].exists ? app.buttons["Continue"] : app.buttons["Allow Microphone"]
        micButton.tap()
        Springboard.tapAlertButton("Allow", timeout: 2)

        XCTAssertTrue(app.staticTexts["Download Speech Model"].waitForExistence(timeout: 5))
        let download = app.buttons["Download Model"].exists ? app.buttons["Download Model"] : app.buttons["Continue"]
        download.tap()

        // Download (if needed) + model load, then Continue appears.
        let next = app.buttons["Continue"]
        let ready = expectation(for: NSPredicate(format: "exists == true AND isEnabled == true"), evaluatedWith: next)
        wait(for: [ready], timeout: 300)
        next.tap()

        XCTAssertTrue(app.staticTexts["Apple Intelligence"].waitForExistence(timeout: 5))
        app.buttons["Continue"].tap()

        XCTAssertTrue(app.staticTexts["Add the Keyboard"].waitForExistence(timeout: 5))
        // Regression (U2): iOS 26+ enables keyboards under Settings → Apps →
        // WhispIt → Keyboards; "Add New Keyboard" no longer lists them.
        XCTAssertTrue(app.staticTexts["Tap Keyboards and turn on WhispIt"].exists)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Add New Keyboard'")).firstMatch.exists)
        app.scrollTo(app.buttons["I've Added the Keyboard"])
        app.buttons["I've Added the Keyboard"].tap()

        XCTAssertTrue(app.staticTexts["WhispIt"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Ready"].waitForExistence(timeout: 120), "Home never reported Ready")
    }
}
