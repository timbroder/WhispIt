import AVFoundation
import Foundation
@testable import WhispIt

/// Captures everything the coordinator sends to the keyboard.
final class StubIPC: IPCChannel, @unchecked Sendable {
    private let lock = NSLock()
    private var _posts: [String] = []
    private var _states: [SharedState] = []
    private var _texts: [String] = []
    private var handlers: [String: () -> Void] = [:]

    var posts: [String] { lock.withLock { _posts } }
    var states: [SharedState] { lock.withLock { _states } }
    var texts: [String] { lock.withLock { _texts } }
    var lastState: SharedState? { states.last }

    func post(_ name: CFString) {
        lock.withLock { _posts.append(name as String) }
    }

    func observe(_ name: CFString, handler: @escaping () -> Void) {
        lock.withLock { handlers[name as String] = handler }
    }

    func write<T: Encodable>(_ value: T, to file: WhispItConstants.SharedFile) throws {
        guard let state = value as? SharedState else { return }
        lock.withLock { _states.append(state) }
    }

    func writeText(_ text: String, to file: WhispItConstants.SharedFile) throws {
        lock.withLock { _texts.append(text) }
    }

    func read<T: Decodable>(_ type: T.Type, from file: WhispItConstants.SharedFile) throws -> T {
        guard let state = lastState as? T else { throw CocoaError(.fileNoSuchFile) }
        return state
    }

    func readText(from file: WhispItConstants.SharedFile) throws -> String {
        guard let text = texts.last else { throw CocoaError(.fileNoSuchFile) }
        return text
    }

    /// Delivers a notification as if the keyboard had posted it.
    func simulate(_ name: CFString) {
        let handler = lock.withLock { handlers[name as String] }
        handler?()
    }

    func didPost(_ name: CFString) -> Bool { posts.contains(name as String) }
}

final class StubTranscriber: Transcribing, @unchecked Sendable {
    private let lock = NSLock()
    var isModelLoaded = true
    var result: Result<String, Error> = .success("um so the raw text")
    private var _prompts: [String?] = []
    private var _framesReceived = 0
    private var _resetCount = 0

    var prompts: [String?] { lock.withLock { _prompts } }
    var framesReceived: Int { lock.withLock { _framesReceived } }
    var resetCount: Int { lock.withLock { _resetCount } }

    func loadModel(at folder: URL) async throws { isModelLoaded = true }
    func reset() { lock.withLock { _resetCount += 1; _framesReceived = 0 } }
    func appendAudio(_ buffer: AVAudioPCMBuffer) {
        lock.withLock { _framesReceived += Int(buffer.frameLength) }
    }
    func transcribe(prompt: String?) async throws -> String {
        lock.withLock { _prompts.append(prompt) }
        return try result.get()
    }
}

final class StubCleaner: TextCleaning, @unchecked Sendable {
    var isAvailable = true
    var transform: (String) throws -> String = { "Cleaned: \($0)" }
    func clean(_ raw: String) async throws -> String { try transform(raw) }
}

final class StubKeepAlive: KeepAliveSession, @unchecked Sendable {
    private(set) var startCount = 0
    func start() throws { startCount += 1 }
}

/// An input source the test drives by hand.
final class StubAudioSource: AudioInputSource, @unchecked Sendable {
    let format: AVAudioFormat
    private let lock = NSLock()
    private var handler: ((AVAudioPCMBuffer) -> Void)?
    var startError: Error?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    init(sampleRate: Double = 48_000, channels: AVAudioChannelCount = 2) {
        format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: false
        )!
    }

    var isStarted: Bool { lock.withLock { handler != nil } }

    func start(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
        if let startError { throw startError }
        lock.withLock { handler = onBuffer; startCount += 1 }
    }

    func stop() { lock.withLock { handler = nil; stopCount += 1 } }

    func deliver(_ buffer: AVAudioPCMBuffer) {
        let handler = lock.withLock { self.handler }
        handler?(buffer)
    }
}

/// Builds a coordinator wired entirely to stubs and temp storage.
struct PipelineHarness {
    let ipc = StubIPC()
    let transcriber = StubTranscriber()
    let cleaner = StubCleaner()
    let keepAlive = StubKeepAlive()
    let source = StubAudioSource()
    let interruption = AudioInterruptionHandler()
    let tempDir = TemporaryDirectory()
    let defaults = IsolatedDefaults()
    let dictionary: DictionaryManager
    let coordinator: DictationPipelineCoordinator

    init(silenceTimeout: TimeInterval = 60) {
        dictionary = DictionaryManager(fileURL: tempDir.file("dictionary.json"))
        coordinator = DictationPipelineCoordinator(
            audioCapture: AudioCaptureService(source: source),
            transcription: transcriber,
            cleanup: cleaner,
            dictionary: dictionary,
            learning: DictionaryLearningService(dictionary: dictionary, defaults: defaults.defaults),
            interruption: interruption,
            backgroundSession: keepAlive,
            ipc: ipc,
            makeDetector: { VoiceActivityDetector(silenceTimeout: silenceTimeout) }
        )
        coordinator.startObserving()
    }

    func requestStart() {
        ipc.simulate(WhispItConstants.DarwinNotification.recordingStartRequested)
        coordinator.drainQueue()
    }

    func requestStop() {
        ipc.simulate(WhispItConstants.DarwinNotification.recordingStopRequested)
        coordinator.drainQueue()
    }

    /// Waits for the pipeline to post either result notification.
    func waitForResult(timeout: Duration = .seconds(3)) async -> Bool {
        await waitUntil(timeout: timeout) {
            ipc.didPost(WhispItConstants.DarwinNotification.cleanedTextReady)
                || ipc.didPost(WhispItConstants.DarwinNotification.recordingFailed)
        }
    }
}
