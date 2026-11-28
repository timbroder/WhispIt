import AVFoundation
import Darwin
import Foundation
#if canImport(WhispIt)
@testable import WhispIt
#endif

// Speech-engine bake-off (WhispIt-peu): the measurement harness.
//
// This file has no XCTest/Testing dependency so it compiles both into
// WhispItIntegrationTests (iOS simulator or device) and into the native macOS
// runner in Scripts/asr-bakeoff-mac, which symlinks it together with the
// prototype engines. See docs/qa/asr-bakeoff.md.

enum Bakeoff {
    /// Names in the proper-nouns fixture (the existing integration tests' set).
    static let properNouns = ["Kubernetes", "Anthropic", "Priyanka"]

    /// Rarer names and brand words in the names fixture, where a strong
    /// engine still needs the dictionary.
    static let names = ["Siobhan", "Saoirse", "Tuist", "Nguyen", "WhispIt"]

    /// An ordinary word in the names fixture that sounds like a dictionary
    /// word ("Tuist"). Biasing must leave it alone.
    static let decoy = "twist"

    /// The dictionary for every biased run: all eight words at once, as a
    /// user's dictionary would hold many words that aren't in a given sentence.
    static let vocabulary = properNouns + names

    /// Fixtures with speech, scored for word accuracy.
    static let speechFixtures = ["fillers", "proper-nouns", "self-correction", "pause", "long-passage"]

    /// Fixtures that never mention the vocabulary: biasing must not inject it.
    static let leakFixtures = ["fillers", "self-correction", "long-passage"]

    static let latencyFixtures = ["fillers", "long-passage"]
    static let latencyRuns = 3

    /// What each fixture says. Mirrors Scripts/make-audio-fixtures.sh; keep in sync.
    static let scripts: [String: String] = [
        "fillers": "Um, so, basically I think we should, uh, ship the new build on Friday, you know.",
        "proper-nouns": "Please send the Kubernetes report to Anthropic and Priyanka by Thursday.",
        "self-correction": "Let's meet at three, no wait, let's meet at four o'clock tomorrow.",
        "silence": "",
        "pause": "This is the first part. This sentence comes after a long pause.",
        "names": "Ask Siobhan and Saoirse to send the Tuist config to Nguyen, and add a twist of lime for the WhispIt demo.",
        "long-passage": """
            Good morning everyone. I wanted to give a quick update on the project before our planning meeting. \
            Over the last two weeks the team finished the onboarding flow, wired up the keyboard extension, and fixed several bugs \
            in the audio pipeline. We also started measuring latency from the moment you stop speaking to the moment text appears, \
            and right now it sits at around two seconds on recent phones. Next sprint we plan to focus on tone adaptation for \
            different apps, a symbols keyboard, and better error messages when the main app is not running. If you have feedback \
            on priorities, please add it to the planning document by Wednesday afternoon so we can review it together on Thursday. \
            Thanks, and have a great rest of your week.
            """,
    ]
}

// MARK: - Word error rate

/// Word error rate after the usual normalization (lowercase, no punctuation
/// or apostrophes, small numbers spelled out, hesitation sounds dropped from
/// both sides, as Whisper's English normalizer does).
enum WordErrorRate {
    struct Score: Codable {
        var errors: Int
        var referenceWords: Int
        var rate: Double { referenceWords == 0 ? 0 : Double(errors) / Double(referenceWords) }
    }

    static let hesitations: Set<String> = ["um", "uh", "uhm", "umm", "er", "erm", "ah", "hmm", "mm", "mhm"]

    static let numberWords: [String: String] = [
        "0": "zero", "1": "one", "2": "two", "3": "three", "4": "four", "5": "five", "6": "six",
        "7": "seven", "8": "eight", "9": "nine", "10": "ten", "11": "eleven", "12": "twelve",
    ]

    static func normalize(_ text: String) -> [String] {
        text.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "'", with: "")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !hesitations.contains($0) && $0 != "00" }
            .map { numberWords[$0] ?? $0 }
    }

    static func score(reference: String, hypothesis: String) -> Score {
        let ref = normalize(reference)
        let hyp = normalize(hypothesis)
        guard !ref.isEmpty else { return Score(errors: hyp.count, referenceWords: 0) }
        var previous = Array(0...hyp.count)
        for i in 1...ref.count {
            var current = [i] + Array(repeating: 0, count: hyp.count)
            for j in stride(from: 1, through: hyp.count, by: 1) {
                let substitution = previous[j - 1] + (ref[i - 1] == hyp[j - 1] ? 0 : 1)
                current[j] = min(substitution, previous[j] + 1, current[j - 1] + 1)
            }
            previous = current
        }
        return Score(errors: previous[hyp.count], referenceWords: ref.count)
    }

    static func contains(_ text: String, word: String) -> Bool {
        normalize(text).contains(word.lowercased())
    }
}

// MARK: - Memory, disk, timing

enum ProcessMemory {
    /// The footprint iOS's memory limits are enforced against (what Xcode's
    /// memory gauge shows), in bytes.
    static var footprint: UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }
}

/// Samples the process footprint every 20 ms on a background thread.
final class PeakMemorySampler: @unchecked Sendable {
    private let lock = NSLock()
    private var peak: UInt64
    private var running = true

    init() {
        peak = ProcessMemory.footprint
        Thread.detachNewThread { [self] in
            while lock.withLock({ running }) {
                let now = ProcessMemory.footprint
                lock.withLock { peak = max(peak, now) }
                Thread.sleep(forTimeInterval: 0.02)
            }
        }
    }

    /// Stops sampling and returns the peak footprint in bytes.
    func stop() -> UInt64 {
        lock.withLock {
            running = false
            peak = max(peak, ProcessMemory.footprint)
            return peak
        }
    }
}

func megabytes(_ bytes: UInt64) -> Double { (Double(bytes) / 1_048_576 * 10).rounded() / 10 }

func directoryBytes(_ url: URL) -> UInt64 {
    guard let enumerator = FileManager.default.enumerator(
        at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]
    ) else { return 0 }
    var total: UInt64 = 0
    for case let file as URL in enumerator {
        let values = try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
        if values?.isRegularFile == true { total += UInt64(values?.totalFileAllocatedSize ?? 0) }
    }
    return total
}

extension Duration {
    var milliseconds: Double {
        let parts = components
        return (Double(parts.seconds) * 1000 + Double(parts.attoseconds) / 1e15).rounded()
    }
}

func median(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    guard !sorted.isEmpty else { return 0 }
    return sorted.count % 2 == 1
        ? sorted[sorted.count / 2]
        : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
}

extension AVAudioPCMBuffer {
    /// Splits a mono float buffer into mic-sized chunks.
    func chunks(of frames: AVAudioFrameCount) -> [AVAudioPCMBuffer] {
        guard let source = floatChannelData?[0] else { return [self] }
        var result: [AVAudioPCMBuffer] = []
        var offset: AVAudioFrameCount = 0
        while offset < frameLength {
            let count = min(frames, frameLength - offset)
            guard let chunk = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count),
                  let target = chunk.floatChannelData?[0] else { break }
            target.update(from: source.advanced(by: Int(offset)), count: Int(count))
            chunk.frameLength = count
            result.append(chunk)
            offset += count
        }
        return result
    }
}

private func sysctlString(_ name: String) -> String {
    var size = 0
    sysctlbyname(name, nil, &size, nil, 0)
    guard size > 0 else { return "?" }
    var value = [CChar](repeating: 0, count: size)
    sysctlbyname(name, &value, &size, nil, 0)
    return String(cString: value)
}

var hostDescription: String {
    let os = ProcessInfo.processInfo.operatingSystemVersionString
    #if targetEnvironment(simulator)
    let model = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "?"
    return "iOS simulator \(model) on \(sysctlString("machdep.cpu.brand_string")) (CPU only), \(os)"
    #elseif os(macOS)
    return "macOS native, \(sysctlString("hw.model")) \(sysctlString("machdep.cpu.brand_string")), \(os)"
    #else
    return "iOS device \(sysctlString("hw.machine")), \(os)"
    #endif
}

// MARK: - Engines

/// One candidate engine, adapted to the harness.
struct EngineUnderTest {
    let name: String
    let transcriber: Transcribing
    /// Audio is analyzed while it arrives, so latency runs feed it in real time.
    let streams: Bool
    /// Points the engine at a word list (or none) for the next transcription.
    let setVocabulary: ([String]) -> Void
    /// The `prompt` argument for `transcribe`: Whisper's sentence, or nil.
    let prompt: ([String]) -> String?
    /// The folder handed to `loadModel(at:)` (downloads it if needed).
    let modelFolder: () async throws -> URL
    /// Model bytes on disk after loading, or nil when the OS manages them.
    let diskBytes: () -> UInt64?
    /// A fresh, unloaded instance of the same engine, to time a relaunch.
    let makeFresh: () -> Transcribing
    /// Engine-specific notes for the report (install status, replacements…).
    var notes: () -> [String: String] = { [:] }

    /// WhisperKit with the dictionary passed as Whisper's prompt, as shipped.
    static func whisper(variant: String, folder: @escaping () async throws -> URL) -> EngineUnderTest {
        let cache = FolderCache(fetch: folder)
        return EngineUnderTest(
            name: "whisperkit \(variant)",
            transcriber: TranscriptionService(),
            streams: false,
            setVocabulary: { _ in },
            prompt: { words in
                DictionaryPromptBuilder.prompt(from: words.map { DictionaryEntry(word: $0, source: .manual) })
            },
            modelFolder: { try await cache.url() },
            diskBytes: { cache.cached.map(directoryBytes) },
            makeFresh: { TranscriptionService() }
        )
    }

    static func speechAnalyzer(mode: SpeechAnalyzerTranscriber.Mode) -> EngineUnderTest {
        let words = WordBox()
        let transcriber = SpeechAnalyzerTranscriber(mode: mode, vocabulary: { words.value })
        return EngineUnderTest(
            name: "speechanalyzer dictation (\(mode.rawValue))",
            transcriber: transcriber,
            streams: mode == .streaming,
            setVocabulary: { words.value = $0 },
            prompt: { _ in nil },
            modelFolder: { FileManager.default.temporaryDirectory },
            diskBytes: { nil },
            makeFresh: { SpeechAnalyzerTranscriber(mode: mode, vocabulary: { [] }) },
            notes: {
                guard let report = transcriber.installReport,
                      let data = try? JSONEncoder().encode(report) else { return [:] }
                return ["install": String(decoding: data, as: UTF8.self)]
            }
        )
    }

    static func parakeet(
        _ version: ParakeetTranscriber.Version,
        boosting: ParakeetTranscriber.Boosting = .dictation
    ) -> EngineUnderTest {
        let words = WordBox()
        let transcriber = ParakeetTranscriber(version: version, boosting: boosting, vocabulary: { words.value })
        return EngineUnderTest(
            name: "parakeet-tdt-0.6b-\(version.rawValue) (\(boosting.rawValue) boosting)",
            transcriber: transcriber,
            streams: false,
            setVocabulary: { words.value = $0 },
            prompt: { _ in nil },
            modelFolder: { FileManager.default.temporaryDirectory },
            diskBytes: { transcriber.modelDirectories.map(directoryBytes).reduce(0, +) },
            makeFresh: { ParakeetTranscriber(version: version, vocabulary: { [] }) },
            notes: { ["replacements": transcriber.lastReplacements.joined(separator: "; ")] }
        )
    }
}

final class WordBox: @unchecked Sendable {
    private let lock = NSLock()
    private var words: [String] = []
    var value: [String] {
        get { lock.withLock { words } }
        set { lock.withLock { words = newValue } }
    }
}

/// Fetches (downloads) a model folder once.
final class FolderCache: @unchecked Sendable {
    private let fetch: () async throws -> URL
    private(set) var cached: URL?

    init(fetch: @escaping () async throws -> URL) { self.fetch = fetch }

    func url() async throws -> URL {
        if let cached { return cached }
        let url = try await fetch()
        cached = url
        return url
    }
}

// MARK: - Results

struct BakeoffResult: Codable {
    struct FixtureRun: Codable {
        var fixture: String
        var text: String
        var errors: Int
        var referenceWords: Int
        var wer: Double
        var stopToTextMs: Double
    }

    struct LatencyRun: Codable {
        var fixture: String
        var audioSeconds: Double
        var mode: String
        var runsMs: [Double]
        var medianMs: Double
    }

    var engine: String
    var host: String
    var downloadAndLoadSeconds: Double = 0
    var relaunchLoadSeconds: Double?
    var diskMB: Double?
    var footprintBeforeLoadMB: Double = 0
    var footprintAfterLoadMB: Double = 0
    var peakDuringLoadMB: Double = 0
    var peakDuringTranscriptionMB: Double = 0
    var accuracy: [FixtureRun] = []
    var overallWER: Double = 0
    var properNounsPlain: Int = 0
    var properNounsBiased: Int = 0
    var properNounsBiasedText: String = ""
    var properNounsBiasedWER: Double = 0
    var namesPlain: Int = 0
    var namesBiased: Int = 0
    var namesPlainText: String = ""
    var namesBiasedText: String = ""
    var decoyKeptPlain = false
    var decoyKeptBiased = false
    var vocabularyLeaks: [String] = []
    var biasedLeakWER: Double = 0
    var silenceText: String = ""
    var silenceBiasedText: String = ""
    var latency: [LatencyRun] = []
    var notes: [String: String] = [:]
}

// MARK: - Runner

/// Runs one engine through every measurement and prints a `BAKEOFF_RESULT`
/// line. It asserts nothing: a candidate that hallucinates on silence is a
/// finding, not a broken build. Callers add their own sanity checks.
enum BakeoffRunner {
    typealias AudioLoader = (_ fixture: String) throws -> AVAudioPCMBuffer

    static func run(_ engine: EngineUnderTest, audio: AudioLoader) async throws -> BakeoffResult {
        var result = BakeoffResult(engine: engine.name, host: hostDescription)
        let clock = ContinuousClock()
        let transcriber = engine.transcriber
        let log = { (line: String) in print("[bakeoff \(engine.name)] \(line)") }

        // Load: cold download-and-load time and memory.
        let folder = try await engine.modelFolder()
        result.footprintBeforeLoadMB = megabytes(ProcessMemory.footprint)
        let loadSampler = PeakMemorySampler()
        let loadStart = clock.now
        try await transcriber.loadModel(at: folder)
        result.downloadAndLoadSeconds = (clock.now - loadStart).milliseconds / 1000
        result.peakDuringLoadMB = megabytes(loadSampler.stop())
        result.footprintAfterLoadMB = megabytes(ProcessMemory.footprint)
        result.diskMB = engine.diskBytes().map(megabytes)
        log("loaded in \(result.downloadAndLoadSeconds) s")

        // Warm-up so later timings measure steady state, not first-run compilation.
        _ = try await transcribe(engine, "fillers", audio: audio)

        let sampler = PeakMemorySampler()

        // Word accuracy, no vocabulary.
        var errors = 0, words = 0
        for fixture in Bakeoff.speechFixtures {
            let (text, elapsed) = try await transcribe(engine, fixture, audio: audio)
            let score = WordErrorRate.score(reference: Bakeoff.scripts[fixture] ?? "", hypothesis: text)
            errors += score.errors
            words += score.referenceWords
            result.accuracy.append(.init(
                fixture: fixture, text: text, errors: score.errors,
                referenceWords: score.referenceWords, wer: score.rate, stopToTextMs: elapsed.milliseconds
            ))
            log("\(fixture) wer=\(score.rate) \"\(text)\"")
        }
        result.overallWER = words == 0 ? 0 : Double(errors) / Double(words)

        // Proper nouns with and without the dictionary.
        let hits = { (text: String, words: [String]) in
            words.filter { WordErrorRate.contains(text, word: $0) }.count
        }
        let plain = result.accuracy.first { $0.fixture == "proper-nouns" }?.text ?? ""
        result.properNounsPlain = hits(plain, Bakeoff.properNouns)
        let (biased, _) = try await transcribe(engine, "proper-nouns", vocabulary: Bakeoff.vocabulary, audio: audio)
        result.properNounsBiased = hits(biased, Bakeoff.properNouns)
        result.properNounsBiasedText = biased
        result.properNounsBiasedWER = WordErrorRate.score(
            reference: Bakeoff.scripts["proper-nouns"] ?? "", hypothesis: biased
        ).rate
        for (key, value) in engine.notes() { result.notes["properNouns.\(key)"] = value }
        log("proper nouns plain=\(result.properNounsPlain)/3 biased=\(result.properNounsBiased)/3 \"\(biased)\"")

        // Rarer names, and the decoy that must survive biasing.
        result.namesPlainText = try await transcribe(engine, "names", audio: audio).text
        result.namesPlain = hits(result.namesPlainText, Bakeoff.names)
        result.decoyKeptPlain = WordErrorRate.contains(result.namesPlainText, word: Bakeoff.decoy)
        result.namesBiasedText = try await transcribe(engine, "names", vocabulary: Bakeoff.vocabulary, audio: audio).text
        result.namesBiased = hits(result.namesBiasedText, Bakeoff.names)
        result.decoyKeptBiased = WordErrorRate.contains(result.namesBiasedText, word: Bakeoff.decoy)
        for (key, value) in engine.notes() { result.notes["names.\(key)"] = value }
        log("names plain=\(result.namesPlain)/5 \"\(result.namesPlainText)\"")
        log("names biased=\(result.namesBiased)/5 decoy kept=\(result.decoyKeptBiased) \"\(result.namesBiasedText)\"")

        // The dictionary must not leak into speech that never mentions it.
        var leakErrors = 0, leakWords = 0
        for fixture in Bakeoff.leakFixtures {
            let (text, _) = try await transcribe(engine, fixture, vocabulary: Bakeoff.vocabulary, audio: audio)
            let score = WordErrorRate.score(reference: Bakeoff.scripts[fixture] ?? "", hypothesis: text)
            leakErrors += score.errors
            leakWords += score.referenceWords
            for word in Bakeoff.vocabulary where WordErrorRate.contains(text, word: word) {
                result.vocabularyLeaks.append("\(fixture): \(word)")
            }
        }
        result.biasedLeakWER = leakWords == 0 ? 0 : Double(leakErrors) / Double(leakWords)

        // Silence, with and without the dictionary.
        result.silenceText = try await transcribe(engine, "silence", audio: audio).text
        result.silenceBiasedText = try await transcribe(
            engine, "silence", vocabulary: Bakeoff.vocabulary, audio: audio
        ).text
        log("silence \"\(result.silenceText)\" biased \"\(result.silenceBiasedText)\"")

        // Stop-to-text latency: time from the last audio to the final text.
        // Streaming engines get the audio in real time, as from the mic, so
        // their work overlaps the recording the way it would in the app.
        for fixture in Bakeoff.latencyFixtures {
            let audioSeconds = Double(try audio(fixture).frameLength) / 16_000
            var runs: [Double] = []
            for _ in 0..<Bakeoff.latencyRuns {
                let (_, elapsed) = try await transcribe(engine, fixture, realTime: engine.streams, audio: audio)
                runs.append(elapsed.milliseconds)
            }
            result.latency.append(.init(
                fixture: fixture, audioSeconds: (audioSeconds * 10).rounded() / 10,
                mode: engine.streams ? "streamed in real time" : "batch after stop",
                runsMs: runs, medianMs: median(runs)
            ))
            log("latency \(fixture) \(runs) ms")
        }
        result.peakDuringTranscriptionMB = megabytes(sampler.stop())

        // Load again from the cache: what each app launch pays once models exist.
        let fresh = engine.makeFresh()
        let relaunchStart = clock.now
        try await fresh.loadModel(at: folder)
        result.relaunchLoadSeconds = (clock.now - relaunchStart).milliseconds / 1000

        for (key, value) in engine.notes() { result.notes[key] = value }
        let json = String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
        print("BAKEOFF_RESULT \(json)")
        return result
    }

    static func transcribe(
        _ engine: EngineUnderTest,
        _ fixture: String,
        vocabulary: [String] = [],
        realTime: Bool = false,
        audio: AudioLoader
    ) async throws -> (text: String, elapsed: Duration) {
        let transcriber = engine.transcriber
        engine.setVocabulary(vocabulary)
        transcriber.reset()
        let buffer = try audio(fixture)
        if realTime {
            for chunk in buffer.chunks(of: 1_600) { // 100 ms, like mic taps
                transcriber.appendAudio(chunk)
                try await Task.sleep(for: .milliseconds(100))
            }
        } else {
            transcriber.appendAudio(buffer)
        }
        let clock = ContinuousClock()
        let start = clock.now
        let text = try await transcriber.transcribe(prompt: engine.prompt(vocabulary))
        return (text, clock.now - start)
    }
}
