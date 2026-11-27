import AVFoundation
import Foundation
import Testing
@testable import WhispIt

/// Downloads (once) and loads a small WhisperKit model for the whole test run.
/// The production app uses large-v3 turbo; integration tests use base.en so a
/// run takes minutes, not an hour, while still exercising the real pipeline.
actor ModelStore {
    static let shared = ModelStore()
    static let variant = "openai_whisper-base.en"

    private var transcriber: TranscriptionService?
    private var folder: URL?

    func modelFolder() async throws -> URL {
        if let folder { return folder }
        let caches = try FileManager.default.url(
            for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ).appending(path: "IntegrationModels")
        let url = try await ModelDownloadService().download(
            variant: Self.variant, into: caches, remember: false
        )
        folder = url
        return url
    }

    /// A loaded transcriber shared across tests (loading costs seconds).
    func loadedTranscriber() async throws -> TranscriptionService {
        if let transcriber { return transcriber }
        let service = TranscriptionService()
        try await service.loadModel(at: modelFolder())
        transcriber = service
        return service
    }
}

enum Transcript {
    /// Lowercased words with punctuation removed, for keyword assertions.
    static func words(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    static func contains(_ text: String, _ word: String) -> Bool {
        words(text).contains(word.lowercased())
    }
}

/// Loads a fixture already converted to Whisper's 16 kHz mono format.
func whisperAudio(_ fixture: Fixture) throws -> AVAudioPCMBuffer {
    try FileAudioInputSource.load(url: fixture.url, as: AudioCaptureService.whisperFormat)
}

/// Captures what the pipeline sends to the keyboard.
final class CapturingIPC: IPCChannel, @unchecked Sendable {
    private let lock = NSLock()
    private var _posts: [String] = []
    private var _states: [SharedState] = []
    private var _texts: [String] = []
    private var handlers: [String: () -> Void] = [:]

    var posts: [String] { lock.withLock { _posts } }
    var texts: [String] { lock.withLock { _texts } }
    var lastState: SharedState? { lock.withLock { _states.last } }

    func post(_ name: CFString) { lock.withLock { _posts.append(name as String) } }
    func observe(_ name: CFString, handler: @escaping () -> Void) { lock.withLock { handlers[name as String] = handler } }
    func write<T: Encodable>(_ value: T, to file: WhispItConstants.SharedFile) throws {
        if let state = value as? SharedState { lock.withLock { _states.append(state) } }
    }
    func writeText(_ text: String, to file: WhispItConstants.SharedFile) throws { lock.withLock { _texts.append(text) } }
    func read<T: Decodable>(_ type: T.Type, from file: WhispItConstants.SharedFile) throws -> T {
        guard let value = lastState as? T else { throw CocoaError(.fileNoSuchFile) }
        return value
    }
    func readText(from file: WhispItConstants.SharedFile) throws -> String {
        guard let text = texts.last else { throw CocoaError(.fileNoSuchFile) }
        return text
    }
    func simulate(_ name: CFString) {
        let handler = lock.withLock { handlers[name as String] }
        handler?()
    }
    func didPost(_ name: CFString) -> Bool { posts.contains(name as String) }
}

func waitUntil(timeout: Duration, _ condition: () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(50))
    }
    return condition()
}

let appleIntelligenceAvailable = CleanupService().isAvailable

/// On some hosts the first Foundation Models request in a fresh process
/// fails while model assets load (WhispIt-enu). Cleanup suites call this so
/// they measure the prompt, not the host. Runs once per process.
actor FoundationModelsWarmup {
    static let shared = FoundationModelsWarmup()
    private var done = false

    func ensure() async {
        guard !done else { return }
        done = true
        _ = try? await CleanupService().clean("hello there")
    }
}
