import AVFoundation
import Foundation
import Testing
@testable import WhispIt

// Speech-engine bake-off (WhispIt-peu). Opt-in, because the suites download
// about 2 GB of models and run for many minutes. Run one engine per
// xcodebuild invocation so memory numbers aren't polluted by the others:
//
//     TEST_RUNNER_WHISPIT_BAKEOFF=1 xcodebuild test -project WhispIt.xcodeproj \
//       -scheme WhispItApp -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
//       -only-testing:WhispItIntegrationTests/ParakeetV2Bakeoff
//
// Each suite prints one `BAKEOFF_RESULT {json}` line per engine; the results
// in docs/qa/asr-bakeoff.md come from those lines.

extension Bakeoff {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["WHISPIT_BAKEOFF"] != nil
    }

    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    /// Fixture audio in the pipeline's 16 kHz mono format.
    static func audio(_ name: String) throws -> AVAudioPCMBuffer {
        try whisperAudio(try #require(Fixture(rawValue: name), "unknown fixture \(name)"))
    }

    static func whisper(_ variant: String) -> EngineUnderTest {
        .whisper(variant: variant) {
            let caches = try FileManager.default.url(
                for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            ).appending(path: "IntegrationModels")
            return try await ModelDownloadService().download(variant: variant, into: caches, remember: false)
        }
    }

    /// The engine must transcribe clean synthetic speech reasonably.
    static func checkSanity(_ result: BakeoffResult) {
        #expect(result.overallWER < 0.35, "overall WER \(result.overallWER)")
        for run in result.accuracy {
            #expect(!run.text.isEmpty, "\(run.fixture) came back empty")
        }
    }

    static func measure(_ engine: EngineUnderTest) async throws {
        checkSanity(try await BakeoffRunner.run(engine, audio: audio))
    }
}

// One suite per engine so each can run in its own process (clean memory numbers).

@Suite("Bake-off: WhisperKit large-v3 turbo 632 MB", .enabled(if: Bakeoff.isEnabled), .timeLimit(.minutes(60)))
struct WhisperTurboBakeoff {
    @Test func measure() async throws {
        try await Bakeoff.measure(Bakeoff.whisper("openai_whisper-large-v3-v20240930_turbo_632MB"))
    }
}

/// The current shipping default (about 1.5 GB), for reference against the 632 MB build.
@Suite("Bake-off: WhisperKit large-v3 turbo full", .enabled(if: Bakeoff.isEnabled), .timeLimit(.minutes(60)))
struct WhisperTurboFullBakeoff {
    @Test func measure() async throws {
        try await Bakeoff.measure(Bakeoff.whisper(ModelDownloadService.defaultVariant))
    }
}

/// What the rest of the integration suite runs, for scale.
@Suite("Bake-off: WhisperKit base.en", .enabled(if: Bakeoff.isEnabled), .timeLimit(.minutes(30)))
struct WhisperBaseBakeoff {
    @Test func measure() async throws {
        try await Bakeoff.measure(Bakeoff.whisper(ModelStore.variant))
    }
}

/// The iOS 27.2 simulator reports the dictation assets as installed but
/// offers no audio format (its GeneralASR asset fetch fails), and
/// `SpeechTranscriber.isAvailable` is false there. Run this suite on a
/// device, or use Scripts/asr-bakeoff-mac on a Mac.
@Suite(
    "Bake-off: SpeechAnalyzer DictationTranscriber",
    .enabled(if: Bakeoff.isEnabled),
    .disabled(if: Bakeoff.isSimulator, "SpeechAnalyzer has no usable assets in the iOS simulator"),
    .timeLimit(.minutes(30))
)
struct SpeechAnalyzerBakeoff {
    @Test func measureStreaming() async throws {
        try await Bakeoff.measure(.speechAnalyzer(mode: .streaming))
    }

    /// Same model, analyzed only after stop: isolates what streaming buys.
    @Test func measureBatch() async throws {
        try await Bakeoff.measure(.speechAnalyzer(mode: .batch))
    }
}

@Suite("Bake-off: Parakeet TDT 0.6B v2", .enabled(if: Bakeoff.isEnabled), .timeLimit(.minutes(60)))
struct ParakeetV2Bakeoff {
    @Test func measure() async throws {
        try await Bakeoff.measure(.parakeet(.v2))
    }

    /// FluidAudio's default (recall-tuned) boosting, against the stricter
    /// dictation thresholds the prototype uses by default.
    @Test func measureRecallBoosting() async throws {
        try await Bakeoff.measure(.parakeet(.v2, boosting: .recall))
    }
}

@Suite("Bake-off: Parakeet TDT 0.6B v3", .enabled(if: Bakeoff.isEnabled), .timeLimit(.minutes(60)))
struct ParakeetV3Bakeoff {
    @Test func measure() async throws {
        try await Bakeoff.measure(.parakeet(.v3))
    }
}

/// Hermetic checks of the harness itself; run with the rest of the integration suite.
@Suite("Bake-off harness")
struct BakeoffHarnessTests {
    @Test func werIgnoresCasePunctuationHesitationsAndDigits() {
        let score = WordErrorRate.score(
            reference: "Um, let's meet at four o'clock.",
            hypothesis: "Let's meet at 4 o'clock"
        )
        #expect(score.errors == 0)
        #expect(score.referenceWords == 5)
    }

    @Test func werCountsSubstitutionsInsertionsAndDeletions() {
        // send→sent and today→to are substitutions; "day" and "now" are insertions.
        let score = WordErrorRate.score(reference: "send the report today", hypothesis: "sent the report to day now")
        #expect(score.errors == 4)
        #expect(score.referenceWords == 4)
        #expect(WordErrorRate.score(reference: "a b c", hypothesis: "a c").errors == 1)
    }

    @Test func chunksCoverTheWholeBuffer() throws {
        let audio = try Bakeoff.audio("fillers")
        let chunks = audio.chunks(of: 1_600)
        #expect(chunks.map(\.frameLength).reduce(0, +) == audio.frameLength)
        #expect(chunks.dropLast().allSatisfy { $0.frameLength == 1_600 })
    }

    @Test(arguments: Fixture.allCases)
    func everyFixtureHasAScript(_ fixture: Fixture) throws {
        let script = try #require(Bakeoff.scripts[fixture.rawValue])
        #expect(fixture == .silence ? script.isEmpty : WordErrorRate.normalize(script).count >= 5)
    }

    @Test func medianOfOddAndEvenCounts() {
        #expect(median([3, 1, 2]) == 2)
        #expect(median([4, 1, 3, 2]) == 2.5)
    }
}
