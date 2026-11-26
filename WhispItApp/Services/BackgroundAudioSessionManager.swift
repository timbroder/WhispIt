import AVFoundation
import Foundation

/// Keeps the main app alive in the background by playing silence, so the
/// keyboard extension can trigger recordings at any time.
///
/// iOS stops the engine on its own when an interruption begins (phone call,
/// Siri) and when the audio route changes (`AVAudioEngineConfigurationChange`).
/// `start()` is therefore keyed off whether the engine is actually running,
/// not off a flag, and route changes restart it automatically.
final class BackgroundAudioSessionManager {
    static let shared: BackgroundAudioSessionManager = {
        #if DEBUG
        // Fixture runs never touch the mic, so keep the app alive with a
        // playback-only session. Lets simulator QA run the full keyboard
        // loop on hosts where the simulator has no microphone access.
        if DebugOverrides.audioFixtureURL != nil {
            return BackgroundAudioSessionManager(configureSession: {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
                try session.setActive(true)
            })
        }
        #endif
        return BackgroundAudioSessionManager()
    }()

    enum BackgroundAudioError: Error {
        case audioFormatUnavailable
        case engineFailedToStart(Error)
    }

    private let engine: AVAudioEngine
    private let configureSession: () throws -> Void
    private let player = AVAudioPlayerNode()
    private let lock = NSLock()
    private var isPlayerAttached = false
    private var wantsToRun = false
    private var configurationObserver: NSObjectProtocol?

    /// Whether the keep-alive engine is currently producing (silent) audio.
    var isActive: Bool { engine.isRunning && player.isPlaying }

    static func configureSharedSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.mixWithOthers, .allowBluetoothHFP, .defaultToSpeaker]
        )
        try session.setActive(true, options: [])
    }

    /// - Parameter configureSession: sets up the audio session before the
    ///   engine starts. Tests pass a playback-only configuration.
    init(
        engine: AVAudioEngine = AVAudioEngine(),
        configureSession: @escaping () throws -> Void = BackgroundAudioSessionManager.configureSharedSession
    ) {
        self.engine = engine
        self.configureSession = configureSession
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            self?.handleConfigurationChange()
        }
    }

    deinit {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
    }

    /// Starts (or restarts) the keep-alive engine. Safe to call repeatedly.
    func start() throws {
        lock.lock()
        defer { lock.unlock() }
        wantsToRun = true
        guard !isActive else { return }

        try configureSession()

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 44_100,
            channels: 1,
            interleaved: false
        ) else {
            throw BackgroundAudioError.audioFormatUnavailable
        }

        let frameCount: AVAudioFrameCount = 44_100
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw BackgroundAudioError.audioFormatUnavailable
        }
        buffer.frameLength = frameCount

        if !isPlayerAttached {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            isPlayerAttached = true
        }

        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                throw BackgroundAudioError.engineFailedToStart(error)
            }
        }

        player.stop()
        player.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
        player.volume = 0
        player.play()
        PipelineLog.logger.info("Keep-alive audio running")
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        wantsToRun = false
        player.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func handleConfigurationChange() {
        let shouldRestart = lock.withLock { wantsToRun }
        guard shouldRestart else { return }
        PipelineLog.logger.notice("Audio configuration changed; restarting keep-alive")
        do {
            try start()
        } catch {
            PipelineLog.logger.error("Keep-alive restart failed: \(String(describing: error), privacy: .public)")
        }
    }

    #if DEBUG
    /// Test hook: what iOS does to the engine when an interruption begins.
    func simulateSystemStop() {
        player.stop()
        engine.stop()
    }

    var isEngineRunning: Bool { engine.isRunning }
    #endif
}
