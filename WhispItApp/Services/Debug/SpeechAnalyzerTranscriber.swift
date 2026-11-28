#if DEBUG
import AVFoundation
import Foundation
import Speech

/// Speech-engine bake-off prototype (WhispIt-peu): Apple's on-device
/// `SpeechAnalyzer` with `DictationTranscriber`, behind `Transcribing`.
/// Select it with `-WhispItASREngine speech-analyzer`. Release builds never
/// compile it.
///
/// In `.streaming` mode audio goes to the analyzer while the user is still
/// talking, so `transcribe` only finalizes the tail of the recording. In
/// `.batch` mode audio is buffered and analyzed after stop, like Whisper.
///
/// Dictionary words become `AnalysisContext.contextualStrings`. The context
/// has to be in place before analysis starts, so the words come from
/// `vocabulary` when a recording's first buffer arrives, not from the
/// `prompt` passed to `transcribe` (that is Whisper's prompt format).
final class SpeechAnalyzerTranscriber: Transcribing, @unchecked Sendable {
    enum Mode: String { case streaming, batch }

    enum SpeechAnalyzerError: Error {
        case unsupportedLocale(String)
        case assetsUnsupported
        case noCompatibleAudioFormat
        case converterUnavailable
    }

    /// What `loadModel` found and did, for the bake-off report.
    struct InstallReport: Codable {
        var locale: String
        var statusBefore: String
        /// An `AssetInstallationRequest` was needed (and ran).
        var installRequestRan: Bool
        /// That request's `progress.totalUnitCount`.
        var installUnitCount: Int64?
        var installSeconds: Double
        var analyzerFormat: String
    }

    /// Apple documents contextual strings as a short list; keep it bounded.
    static let maxContextualStrings = 100

    let mode: Mode
    let requestedLocale: Locale
    /// Dictionary words for the next recording. Read on its first buffer.
    var vocabulary: () -> [String]
    private(set) var installReport: InstallReport?

    private let lock = NSLock()
    private var locale: Locale?
    private var analyzerFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var warmAnalyzer: SpeechAnalyzer?
    private var session: Session?
    private var pending: [AVAudioPCMBuffer] = []
    private var loaded = false

    private struct Session {
        let analyzer: SpeechAnalyzer
        let input: AsyncStream<AnalyzerInput>.Continuation
        let results: Task<String, Error>
    }

    init(
        mode: Mode = .streaming,
        locale: Locale = Locale(identifier: "en-US"),
        vocabulary: @escaping () -> [String] = DictionaryVocabulary.current
    ) {
        self.mode = mode
        self.requestedLocale = locale
        self.vocabulary = vocabulary
    }

    var isModelLoaded: Bool { lock.withLock { loaded } }

    /// `folder` is the Whisper model folder; this engine ignores it and uses
    /// the system-managed assets from `AssetInventory` instead.
    func loadModel(at folder: URL) async throws {
        let clock = ContinuousClock()
        let started = clock.now

        guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: requestedLocale) else {
            throw SpeechAnalyzerError.unsupportedLocale(requestedLocale.identifier)
        }
        let module = Self.makeModule(locale: locale)

        let before = await AssetInventory.status(forModules: [module])
        guard before != .unsupported else { throw SpeechAnalyzerError.assetsUnsupported }
        var request: AssetInstallationRequest?
        if before != .installed {
            if await !AssetInventory.reservedLocales.contains(locale) {
                _ = try? await AssetInventory.reserve(locale: locale)
            }
            request = try await AssetInventory.assetInstallationRequest(supporting: [module])
            try await request?.downloadAndInstall()
        }

        // Pitfall: buffers in any other format are accepted but silently
        // produce no results, so every buffer is converted to this format.
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
            throw SpeechAnalyzerError.noCompatibleAudioFormat
        }
        guard let converter = AVAudioConverter(from: AudioCaptureService.whisperFormat, to: format) else {
            throw SpeechAnalyzerError.converterUnavailable
        }

        // Load the model now so the first dictation doesn't pay for it.
        // `.processLifetime` keeps it resident for later analyzers too.
        let warm = SpeechAnalyzer(modules: [module], options: Self.options)
        try await warm.prepareToAnalyze(in: format)

        lock.withLock {
            self.locale = locale
            self.analyzerFormat = format
            self.converter = converter
            self.warmAnalyzer = warm
            self.loaded = true
        }
        installReport = InstallReport(
            locale: locale.identifier,
            statusBefore: String(describing: before),
            installRequestRan: request != nil,
            installUnitCount: request?.progress.totalUnitCount,
            installSeconds: (clock.now - started).seconds,
            analyzerFormat: "\(format.sampleRate) Hz, \(format.channelCount) ch, \(format.commonFormat.rawValue)"
        )
    }

    func reset() {
        let stale: Session? = lock.withLock {
            let stale = session
            session = nil
            pending.removeAll()
            converter?.reset()
            return stale
        }
        guard let stale else { return }
        stale.input.finish()
        stale.results.cancel()
        Task { await stale.analyzer.cancelAndFinishNow() }
    }

    func appendAudio(_ buffer: AVAudioPCMBuffer) {
        lock.withLock {
            guard loaded, let converted = convert(buffer) else { return }
            switch mode {
            case .batch:
                pending.append(converted)
            case .streaming:
                if session == nil { session = makeSession() }
                session?.input.yield(AnalyzerInput(buffer: converted))
            }
        }
    }

    func transcribe(prompt: String?) async throws -> String {
        let active: Session? = try lock.withLock {
            guard loaded else { throw TranscriptionService.TranscriptionError.modelNotLoaded }
            if mode == .batch, !pending.isEmpty {
                let batch = makeSession()
                for buffer in pending { batch?.input.yield(AnalyzerInput(buffer: buffer)) }
                pending.removeAll()
                return batch
            }
            let active = session
            session = nil
            return active
        }
        guard let active else { return "" }

        active.input.finish()
        try await active.analyzer.finalizeAndFinishThroughEndOfInput()
        let text = try await active.results.value
        return text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Internals (call with `lock` held)

    private func makeSession() -> Session? {
        guard let locale else { return nil }
        let module = Self.makeModule(locale: locale)
        let context = AnalysisContext()
        let words = Array(vocabulary().prefix(Self.maxContextualStrings))
        if !words.isEmpty {
            context.contextualStrings[.general] = words
        }
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        // This initializer starts analysis on `stream` straight away.
        let analyzer = SpeechAnalyzer(
            inputSequence: stream,
            modules: [module],
            options: Self.options,
            analysisContext: context
        )
        let results = Task { () throws -> String in
            var text = ""
            for try await result in module.results where result.isFinal {
                text += String(result.text.characters)
            }
            return text
        }
        return Session(analyzer: analyzer, input: continuation, results: results)
    }

    private func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter, let format = analyzerFormat, buffer.frameLength > 0 else { return nil }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if supplied {
                // More input will come with the next buffer; keep the
                // converter's resampling state instead of ending the stream.
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, error == nil, output.frameLength > 0 else { return nil }
        return output
    }

    private static let options = SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .processLifetime)

    private static func makeModule(locale: Locale) -> DictationTranscriber {
        DictationTranscriber(
            locale: locale,
            contentHints: [],
            transcriptionOptions: [.punctuation],
            reportingOptions: [],
            attributeOptions: []
        )
    }
}

private extension Duration {
    var seconds: Double {
        let parts = components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}
#endif
