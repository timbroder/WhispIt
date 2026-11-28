import Foundation
import Testing
@testable import WhispIt

@Suite("AppLifecycle model loading")
@MainActor
struct AppLifecycleTests {
    let harness = PipelineHarness()
    let keepAlive = StubKeepAlive()
    let folder = FileManager.default.temporaryDirectory

    func makeLifecycle() -> AppLifecycle {
        AppLifecycle(coordinator: harness.coordinator, backgroundAudio: keepAlive)
    }

    @Test func firstLoadLoadsTheModelAndStartsKeepAlive() async {
        harness.transcriber.isModelLoaded = false
        let lifecycle = makeLifecycle()
        await lifecycle.loadModel(at: folder)
        #expect(harness.transcriber.loadCount == 1)
        #expect(lifecycle.bootstrap == .ready)
        #expect(keepAlive.startCount == 1)
    }

    /// Regression (H7): finishing onboarding showed Home, whose .task loaded
    /// the speech model a second time.
    @Test func secondLoadIsSkipped() async {
        harness.transcriber.isModelLoaded = false
        let lifecycle = makeLifecycle()
        await lifecycle.loadModel(at: folder)
        await lifecycle.loadModel(at: folder)
        #expect(harness.transcriber.loadCount == 1)
        #expect(lifecycle.bootstrap == .ready)
    }

    @Test func alreadyLoadedModelStillEnsuresKeepAlive() async {
        harness.transcriber.isModelLoaded = true
        let lifecycle = makeLifecycle()
        await lifecycle.loadModel(at: folder)
        #expect(harness.transcriber.loadCount == 0)
        #expect(keepAlive.startCount == 1)
        #expect(lifecycle.bootstrap == .ready)
    }
}
