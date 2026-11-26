import XCTest

final class SettingsUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication.onboarded()
        app.launch()
    }

    func openSettings() {
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    func openDictionary() {
        openSettings()
        app.buttons["Personal Dictionary"].tap()
        XCTAssertTrue(app.navigationBars["Dictionary"].waitForExistence(timeout: 5))
    }

    func addWord(_ word: String) {
        app.navigationBars["Dictionary"].buttons["Add Word"].tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(word)
        app.navigationBars["Add Word"].buttons["Add"].tap()
    }

    func testHomeShowsStatusAndSettings() {
        XCTAssertTrue(app.staticTexts["WhispIt"].waitForExistence(timeout: 5))
        let status = ["Ready", "Initializing…", "Loading the speech model…", "Setup needs attention"]
        XCTAssertTrue(status.contains { app.staticTexts[$0].exists }, "no status shown")
        XCTAssertTrue(app.buttons["Settings"].exists)
    }

    func testSettingsShowsVersionAndPrivacyPolicy() {
        openSettings()
        // LabeledContent merges its label and value into one element.
        let version = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Version' OR value CONTAINS '0.1.0' OR label CONTAINS '0.1.0'"))
        XCTAssertGreaterThan(version.count, 0, "version row missing")
        let privacy = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Privacy Policy'"))
        XCTAssertGreaterThan(privacy.count, 0, "privacy policy link missing")
    }

    func testDictionaryStartsEmpty() {
        openDictionary()
        XCTAssertTrue(app.staticTexts["No Words"].waitForExistence(timeout: 5))
    }

    func testAddSearchFilterAndDeleteWords() {
        openDictionary()
        addWord("Kubernetes")
        addWord("Anthropic")
        XCTAssertTrue(app.staticTexts["Kubernetes"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Anthropic"].exists)
        XCTAssertEqual(app.staticTexts.matching(identifier: "Manual").count, 2)

        // Duplicate (different case) bumps frequency instead of adding a row.
        addWord("kubernetes")
        XCTAssertTrue(app.staticTexts["Seen 2 times"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["kubernetes"].exists)

        // Filter: nothing has been learned automatically.
        app.buttons["Automatic"].tap()
        XCTAssertTrue(app.staticTexts["No Words"].waitForExistence(timeout: 3))
        app.buttons["All"].tap()

        // Search.
        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("anth")
        XCTAssertTrue(app.staticTexts["Anthropic"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Kubernetes"].exists)
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4))
        XCTAssertTrue(app.staticTexts["Kubernetes"].waitForExistence(timeout: 3))

        // Swipe to delete.
        app.staticTexts["Anthropic"].swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertFalse(app.staticTexts["Anthropic"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Kubernetes"].exists)
    }

    func testAddButtonIsDisabledForBlankWord() {
        openDictionary()
        app.navigationBars["Dictionary"].buttons["Add Word"].tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("   ")
        XCTAssertFalse(app.navigationBars["Add Word"].buttons["Add"].isEnabled)
        app.navigationBars["Add Word"].buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["No Words"].waitForExistence(timeout: 3))
    }

    func testSilenceTimeoutPersistsAcrossLaunches() {
        openSettings()
        app.buttons["Dictation Preferences"].tap()
        let fiveSeconds = app.buttons["5s"]
        XCTAssertTrue(fiveSeconds.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["2s"].isSelected, "default is 2s")
        fiveSeconds.tap()
        XCTAssertTrue(fiveSeconds.isSelected)

        app.terminate()
        let relaunched = XCUIApplication()
        relaunched.launchArguments = ["-WhispIt.hasCompletedOnboarding", "YES", "-WhispItSkipBootstrap"]
        relaunched.launch()
        relaunched.buttons["Settings"].tap()
        relaunched.buttons["Dictation Preferences"].tap()
        XCTAssertTrue(relaunched.buttons["5s"].waitForExistence(timeout: 5))
        XCTAssertTrue(relaunched.buttons["5s"].isSelected)
    }
}
