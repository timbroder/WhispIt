import XCTest

extension XCUIApplication {
    /// Launches from a clean slate (keeps any downloaded model).
    static func fresh(_ extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-WhispItResetState"] + extraArguments
        return app
    }

    /// Launches straight to Home, skipping onboarding and model loading.
    static func onboarded(_ extraArguments: [String] = []) -> XCUIApplication {
        fresh(["-WhispIt.hasCompletedOnboarding", "YES", "-WhispItSkipBootstrap"] + extraArguments)
    }

    /// Scrolls until `element` is hittable (landscape / large text layouts).
    func scrollTo(_ element: XCUIElement, maxSwipes: Int = 6) {
        var swipes = 0
        while !element.isHittable && swipes < maxSwipes {
            swipeUp()
            swipes += 1
        }
    }
}

enum Springboard {
    static let app = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    /// Taps a button on a system permission alert, if one appears.
    @discardableResult
    static func tapAlertButton(_ label: String, timeout: TimeInterval = 5) -> Bool {
        // System alerts can expose the same button twice in the hierarchy.
        let button = app.alerts.buttons[label].firstMatch
        guard button.waitForExistence(timeout: timeout) else { return false }
        button.tap()
        return true
    }
}
