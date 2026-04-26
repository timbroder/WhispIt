import SwiftUI

@main
struct WhispItApp: App {
    @StateObject private var lifecycle = AppLifecycle()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(lifecycle)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var lifecycle: AppLifecycle

    var body: some View {
        if lifecycle.hasCompletedOnboarding {
            HomeView()
        } else {
            OnboardingView()
        }
    }
}
