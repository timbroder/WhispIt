import XCTest

final class LaunchSmokeTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testFreshInstallShowsWelcome() {
        let app = XCUIApplication()
        app.launchArguments = ["-WhispItResetState"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Welcome to WhispIt"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Get Started"].exists)
    }
}
