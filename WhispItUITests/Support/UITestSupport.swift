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

    /// Taps a button on a system permission alert, if one appears. Pass
    /// several labels to accept variants ("Don’t Allow" / "Don't Allow");
    /// the first one present is tapped. Permission prompts can take several
    /// seconds to appear on a loaded CI runner, hence the generous timeout.
    @discardableResult
    static func tapAlertButton(_ labels: String..., timeout: TimeInterval = 15) -> Bool {
        let alert = app.alerts.firstMatch
        guard alert.waitForExistence(timeout: timeout) else { return false }
        for label in labels {
            // System alerts can expose the same button twice in the hierarchy.
            let button = alert.buttons[label].firstMatch
            if button.waitForExistence(timeout: 1) {
                button.tap()
                return true
            }
        }
        return false
    }
}
