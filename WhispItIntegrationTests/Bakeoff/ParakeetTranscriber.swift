import AVFoundation
import FluidAudio
import Foundation
#if canImport(WhispIt)
@testable import WhispIt
#endif

/// Speech-engine bake-off prototype (WhispIt-peu): NVIDIA Parakeet TDT 0.6B
/// (v2 English, v3 multilingual) through FluidAudio, behind `Transcribing`.
///
/// It lives in the integration-test bundle (and Scripts/asr-bakeoff-mac), not
/// the app: Xcode can't link a package in Debug only, and linking FluidAudio
/// into the app added about 30 MB to the Release binary even with every use
/// behind `#if DEBUG`. Adopting Parakeet (WhispIt-ox5) means moving this
/// into the app along with the package.
///
/// Like Whisper, audio is buffered while recording and transcribed in one
/// pass after stop. Parakeet has no prompt, so dictionary words go through
/// FluidAudio's vocabulary boosting instead: a separate 110M-parameter CTC
/// model spots the words in the audio and the rescorer swaps them into the
/// transcript where the acoustics favour them.
final class ParakeetTranscriber: Transcribing, @unchecked Sendable {
    enum Version: String, Codable {
        case v2, v3

        var fluidAudio: AsrModelVersion { self == .v2 ? .v2 : .v3 }
    }

    /// How eagerly the rescorer swaps dictionary words into the transcript.
    enum Boosting: String, Codable {
        /// FluidAudio's defaults, tuned for keyword recall.
        case recall
        /// Stricter values FluidAudio suggests for dictation, where swapping
        /// a correctly heard word costs more than a miss (FluidAudio#967).
        case dictation

        var thresholds: VocabularyBoostingSession.Thresholds {
            switch self {
            case .recall: .default
            case .dictation: .init(cbw: 0, minSimilarity: 0.7)
            }
        }
    }

    let version: Version
    let boostsVocabulary: Bool
    var boosting: Boosting
    /// Dictionary words for vocabulary boosting. Read at each `transcribe`.
    var vocabulary: () -> [String]

    /// Replacements the rescorer made in the last transcript, for the bake-off report.
    private(set) var lastReplacements: [String] = []

    private let lock = NSLock()
    private var samples: [Float] = []
    private var manager: AsrManager?
    private var ctcModels: CtcModels?
    private var boostingCache: (words: [String], boosting: Boosting, session: VocabularyBoostingSession)?

    init(
        version: Version,
        boostsVocabulary: Bool = true,
        boosting: Boosting = .dictation,
        vocabulary: @escaping () -> [String] = { [] }
    ) {
        self.version = version
        self.boostsVocabulary = boostsVocabulary
        self.boosting = boosting
        self.vocabulary = vocabulary
    }

    var isModelLoaded: Bool { lock.withLock { manager != nil } }

    /// Where FluidAudio keeps the downloaded models (Application Support).
    var modelDirectories: [URL] {
        var dirs = [AsrModels.defaultCacheDirectory(for: version.fluidAudio)]
        if boostsVocabulary { dirs.append(CtcModels.defaultCacheDirectory()) }
        return dirs
    }

    /// `folder` is the Whisper model folder; this engine ignores it and
    /// downloads its own models from Hugging Face on first use.
    func loadModel(at folder: URL) async throws {
        let models = try await AsrModels.downloadAndLoad(version: version.fluidAudio)
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        let ctc = boostsVocabulary ? try await CtcModels.downloadAndLoad() : nil
        lock.withLock {
            self.manager = manager
            self.ctcModels = ctc
        }
    }

    func reset() {
        lock.withLock { samples.removeAll() }
    }

    func appendAudio(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let chunk = UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
        lock.withLock { samples.append(contentsOf: chunk) }
    }

    func transcribe(prompt: String?) async throws -> String {
        let (manager, snapshot) = lock.withLock { (self.manager, samples) }
        guard let manager else { throw TranscriptionService.TranscriptionError.modelNotLoaded }
        lastReplacements = []
        guard !snapshot.isEmpty else { return "" }

        // FluidAudio rejects clips under 0.3 s; pad very short taps with silence.
        var audio = snapshot
        let minimum = ASRConstants.minimumRequiredSamples(forSampleRate: 16_000)
        if audio.count < minimum {
            audio += [Float](repeating: 0, count: minimum - audio.count)
        }

        var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        let result = try await manager.transcribe(audio, decoderState: &state)
        var text = result.text

        let words = vocabulary()
        if !words.isEmpty, let session = try await boostingSession(for: words),
           let rescored = await session.rescore(
               text: text, tokenTimings: result.tokenTimings ?? [], audioSamples: audio
           ),
           rescored.wasModified {
            text = rescored.text
            lastReplacements = rescored.replacements
                .filter(\.shouldReplace)
                .map { "\($0.originalWord) → \($0.replacementWord ?? "")" }
        }

        return text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Building a session tokenizes the vocabulary, so reuse it until the
    /// words or thresholds change.
    private func boostingSession(for words: [String]) async throws -> VocabularyBoostingSession? {
        guard boostsVocabulary, let ctcModels = lock.withLock({ self.ctcModels }) else { return nil }
        let boosting = self.boosting
        if let cached = boostingCache, cached.words == words, cached.boosting == boosting {
            return cached.session
        }
        let vocabulary = CustomVocabularyContext(terms: words.map { CustomVocabularyTerm(text: $0) })
        let session = try await VocabularyBoostingSession(
            vocabulary: vocabulary, ctcModels: ctcModels, thresholds: boosting.thresholds
        )
        boostingCache = (words, boosting, session)
        return session
    }
}
