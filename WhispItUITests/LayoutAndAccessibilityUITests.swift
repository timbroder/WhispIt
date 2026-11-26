import XCTest

final class LayoutAndAccessibilityUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
    }

    func testLandscapeOnboardingButtonIsReachable() {
        let app = XCUIApplication.fresh()
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        let button = app.buttons["Get Started"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        app.scrollTo(button)
        XCTAssertTrue(button.isHittable, "Get Started unreachable in landscape")
        button.tap()
        XCTAssertTrue(app.staticTexts["Microphone Access"].waitForExistence(timeout: 5))
    }

    func testLandscapeHomeShowsSettings() {
        let app = XCUIApplication.onboarded()
        app.launch()
        XCUIDevice.shared.orientation = .landscapeRight
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        app.scrollTo(settings)
        XCTAssertTrue(settings.isHittable)
    }

    func testLargestAccessibilityTextKeepsOnboardingUsable() {
        let app = XCUIApplication.fresh([
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ])
        app.launch()
        let button = app.buttons["Get Started"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        app.scrollTo(button)
        XCTAssertTrue(button.isHittable, "Get Started unreachable at AX5 text size")
    }

    func testLargestAccessibilityTextKeepsHomeUsable() {
        let app = XCUIApplication.onboarded([
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ])
        app.launch()
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        app.scrollTo(settings)
        XCTAssertTrue(settings.isHittable, "Settings unreachable at AX5 text size")
    }

    // MARK: Accessibility audits (Xcode's built-in checks)

    func testAccessibilityAuditWelcome() throws {
        let app = XCUIApplication.fresh()
        app.launch()
        XCTAssertTrue(app.buttons["Get Started"].waitForExistence(timeout: 5))
        try audit(app)
    }

    func testAccessibilityAuditHome() throws {
        let app = XCUIApplication.onboarded()
        app.launch()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 5))
        try audit(app)
    }

    func testAccessibilityAuditSettingsAndDictionary() throws {
        let app = XCUIApplication.onboarded()
        app.launch()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        try audit(app)
        app.buttons["Personal Dictionary"].tap()
        XCTAssertTrue(app.navigationBars["Dictionary"].waitForExistence(timeout: 5))
        try audit(app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Dictation Preferences"].tap()
        XCTAssertTrue(app.navigationBars["Dictation"].waitForExistence(timeout: 5))
        try audit(app)
    }

    /// Runs Xcode's accessibility audit and sorts the results:
    /// - "nearly passed" contrast on system secondary colors: logged only;
    /// - known, filed findings (A1 contrast, A2 Dynamic Type/clipping):
    ///   expected failures until fixed;
    /// - anything else: a test failure.
    private func audit(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) throws {
        var unexpected: [String] = []
        var contrastFailures: [String] = []
        var dynamicTypeIssues: [String] = []
        try app.performAccessibilityAudit { issue in
            let element = issue.element.map { String($0.debugDescription.prefix(140)) } ?? "no element"
            let summary = "\(issue.compactDescription) — \(element)"
            print("[a11y] \(summary)")
            switch issue.auditType {
            case .contrast where issue.compactDescription.localizedCaseInsensitiveContains("nearly"):
                break
            case .contrast:
                contrastFailures.append(summary)
            case .dynamicType, .textClipped:
                dynamicTypeIssues.append(summary)
            default:
                unexpected.append(summary)
            }
            return true
        }
        if !contrastFailures.isEmpty {
            XCTExpectFailure("A1: tinted bordered button text fails contrast") {
                XCTFail(contrastFailures.joined(separator: "\n"), file: file, line: line)
            }
        }
        if !dynamicTypeIssues.isEmpty {
            XCTExpectFailure("A2: fixed-size text/icons and clipping at large Dynamic Type sizes") {
                XCTFail(dynamicTypeIssues.joined(separator: "\n"), file: file, line: line)
            }
        }
        XCTAssertTrue(unexpected.isEmpty, "\(unexpected.count) accessibility issue(s):\n" + unexpected.joined(separator: "\n"), file: file, line: line)
    }
}
