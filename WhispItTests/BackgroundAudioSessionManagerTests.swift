import AVFoundation
import Foundation
import Testing
@testable import WhispIt

/// Uses a real AVAudioEngine with a playback-only session (the production
/// play-and-record session needs a live microphone, which CI simulators
/// don't have). The restart logic under test is the same.
@Suite("BackgroundAudioSessionManager", .serialized)
struct BackgroundAudioSessionManagerTests {
    static func playbackSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)
    }

    func makeManager() -> (BackgroundAudioSessionManager, AVAudioEngine) {
        let engine = AVAudioEngine()
        return (BackgroundAudioSessionManager(engine: engine, configureSession: Self.playbackSession), engine)
    }

    @Test func startRunsTheEngine() throws {
        let (manager, _) = makeManager()
        try manager.start()
        defer { manager.stop() }
        #expect(manager.isEngineRunning)
        #expect(manager.isActive)
    }

    @Test func startIsIdempotent() throws {
        let (manager, _) = makeManager()
        try manager.start()
        try manager.start()
        defer { manager.stop() }
        #expect(manager.isActive)
    }

    /// Regression (H3): after iOS stops the engine for an interruption, the
    /// coordinator calls start() when it ends. That used to be a no-op
    /// because a stale `isActive` flag was still true.
    @Test func startRestartsAfterTheSystemStopsTheEngine() throws {
        let (manager, _) = makeManager()
        try manager.start()
        defer { manager.stop() }
        manager.simulateSystemStop()
        #expect(!manager.isActive)
        try manager.start()
        #expect(manager.isEngineRunning)
        #expect(manager.isActive)
    }

    /// Regression (H3): a route change stops the engine and posts a
    /// configuration-change notification; the keep-alive restarts itself.
    @Test func configurationChangeRestartsTheEngine() async throws {
        let (manager, engine) = makeManager()
        try manager.start()
        defer { manager.stop() }
        manager.simulateSystemStop()
        NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: engine)
        #expect(await waitUntil { manager.isActive })
    }

    @Test func configurationChangeAfterStopDoesNotRestart() async throws {
        let (manager, engine) = makeManager()
        try manager.start()
        manager.stop()
        NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: engine)
        try await Task.sleep(for: .milliseconds(200))
        #expect(!manager.isActive)
    }

    /// The old implementation re-attached the player on every start, which
    /// raises an Objective-C exception on the second attach.
    @Test func canStartAgainAfterStop() throws {
        let (manager, _) = makeManager()
        try manager.start()
        manager.stop()
        try manager.start()
        defer { manager.stop() }
        #expect(manager.isActive)
    }
}
