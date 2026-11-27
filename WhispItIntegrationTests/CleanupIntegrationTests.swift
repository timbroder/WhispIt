import Foundation
import FoundationModels
import Testing
@testable import WhispIt

@Suite(
    "Foundation Models cleanup",
    .serialized,
    .enabled(if: appleIntelligenceAvailable, "Apple Intelligence is not available on this Mac"),
    .timeLimit(.minutes(5))
)
struct CleanupIntegrationTests {
    let cleanup = CleanupService()

    init() async {
        await FoundationModelsWarmup.shared.ensure()
    }

    @Test func removesFillerWordsAndKeepsMeaning() async throws {
        let raw = "um so basically I think we should uh ship the new build on Friday you know"
        let cleaned = try await cleanup.clean(raw)
        print("[cleanup fillers] \(cleaned)")
        for filler in ["um", "uh", "basically"] {
            #expect(!Transcript.contains(cleaned, filler), "\"\(filler)\" survived: \(cleaned)")
        }
        #expect(!cleaned.lowercased().contains("you know"))
        for word in ["ship", "build", "friday"] {
            #expect(Transcript.contains(cleaned, word), "lost \"\(word)\": \(cleaned)")
        }
    }

    @Test func addsPunctuationAndCapitalization() async throws {
        let cleaned = try await cleanup.clean("can you send me the report by thursday thanks")
        print("[cleanup punctuation] \(cleaned)")
        #expect(cleaned.first?.isUppercase == true)
        #expect(cleaned.contains(where: { ".?!".contains($0) }))
    }

    @Test func doesNotAnswerQuestionsInTheDictation() async throws {
        // A dictated question must be cleaned, not answered by the model.
        let raw = "what is the capital of france"
        let cleaned = try await cleanup.clean(raw)
        print("[cleanup question] \(cleaned)")
        #expect(!Transcript.contains(cleaned, "paris"), "model answered instead of cleaning: \(cleaned)")
        #expect(Transcript.contains(cleaned, "france"))
    }

    /// Cleanup must not summarize: a real ~130-word dictation keeps nearly all
    /// of its content words.
    @Test func longDictationIsNotSummarized() async throws {
        let raw = "good morning everyone I wanted to give a quick update on the project before our planning meeting over the last two weeks the team finished the onboarding flow wired up the keyboard extension and fixed several bugs in the audio pipeline we also started measuring latency from the moment you stop speaking to the moment text appears and right now it sits at around two seconds on recent phones next sprint we plan to focus on tone adaptation for different apps a symbols keyboard and better error messages when the main app is not running if you have feedback on priorities please add it to the planning document by wednesday afternoon so we can review it together on thursday thanks and have a great rest of your week"
        let cleaned = try await cleanup.clean(raw)
        let rawWords = Transcript.words(raw).count
        let cleanedWords = Transcript.words(cleaned).count
        print("[cleanup long dictation] \(rawWords) → \(cleanedWords) words")
        #expect(Double(cleanedWords) >= Double(rawWords) * 0.85, "summarized: \(cleaned)")
        for word in ["onboarding", "latency", "symbols", "wednesday", "thursday"] {
            #expect(Transcript.contains(cleaned, word), "dropped \"\(word)\"")
        }
    }

    @Test func emptyInputReturnsEmpty() async throws {
        #expect(try await cleanup.clean("   ") == "")
    }

    /// H10: a long dictation can exceed the on-device model's context window.
    /// The pipeline falls back to raw text when cleanup throws (unit-tested);
    /// this records whether and how it throws.
    @Test func veryLongInputEitherCleansOrThrowsContextError() async throws {
        let paragraph = "so basically we finished the onboarding flow and um wired up the keyboard extension and fixed several bugs in the audio pipeline and uh started measuring latency "
        let raw = String(repeating: paragraph, count: 40)
        do {
            let cleaned = try await cleanup.clean(raw)
            print("[cleanup long] ok, \(raw.count) → \(cleaned.count) chars")
            #expect(!cleaned.isEmpty)
        } catch let error as LanguageModelSession.GenerationError {
            print("[cleanup long] threw \(error)")
            if case .exceededContextWindowSize = error {} else {
                Issue.record("Unexpected generation error: \(error)")
            }
        }
    }
}
