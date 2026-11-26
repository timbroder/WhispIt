import AVFoundation
import Foundation
import Testing
@testable import WhispIt

@Suite("WhisperKit transcription (base.en)", .serialized, .timeLimit(.minutes(15)))
struct TranscriptionIntegrationTests {
    func transcribe(_ fixture: Fixture, prompt: String? = nil) async throws -> String {
        let transcriber = try await ModelStore.shared.loadedTranscriber()
        transcriber.reset()
        transcriber.appendAudio(try whisperAudio(fixture))
        return try await transcriber.transcribe(prompt: prompt)
    }

    @Test func modelDownloadsAndLoads() async throws {
        let transcriber = try await ModelStore.shared.loadedTranscriber()
        #expect(transcriber.isModelLoaded)
    }

    @Test func transcribesTheFillerSentence() async throws {
        let text = try await transcribe(.fillers)
        print("[fillers] \(text)")
        for word in ["ship", "build", "friday"] {
            #expect(Transcript.contains(text, word), "missing \"\(word)\" in: \(text)")
        }
    }

    @Test func transcribesTheSelfCorrection() async throws {
        let text = try await transcribe(.selfCorrection)
        print("[self-correction] \(text)")
        #expect(Transcript.contains(text, "meet"))
        #expect(Transcript.contains(text, "tomorrow"))
    }

    @Test func transcribesALongPassage() async throws {
        let text = try await transcribe(.longPassage)
        print("[long-passage] \(Transcript.words(text).count) words")
        #expect(Transcript.words(text).count > 80)
        #expect(Transcript.contains(text, "keyboard"))
        #expect(Transcript.contains(text, "thursday"))
    }

    /// Regression (H12): dictionary words are passed as Whisper's prompt to
    /// bias spelling; the prompt used to empty the transcript entirely.
    @Test func dictionaryPromptHelpsProperNouns() async throws {
        let names = ["kubernetes", "anthropic", "priyanka"]
        let plain = try await transcribe(.properNouns)
        let prompt = DictionaryPromptBuilder.prompt(from: [
            DictionaryEntry(word: "Kubernetes", source: .manual),
            DictionaryEntry(word: "Anthropic", source: .manual),
            DictionaryEntry(word: "Priyanka", source: .manual),
        ])
        let biased = try await transcribe(.properNouns, prompt: prompt)
        let plainHits = names.filter { Transcript.contains(plain, $0) }.count
        let biasedHits = names.filter { Transcript.contains(biased, $0) }.count
        print("[proper-nouns] plain=\(plainHits)/3 \"\(plain)\"")
        print("[proper-nouns] biased=\(biasedHits)/3 \"\(biased)\"")
        #expect(biasedHits >= plainHits)
        #expect(biasedHits >= 2)
        #expect(!Transcript.contains(biased, "vocabulary"), "prompt text leaked into the transcript")
    }

    /// Whisper emits non-speech markers like "[BLANK_AUDIO]" for silence.
    @Test func silenceProducesNoWords() async throws {
        let text = try await transcribe(.silence)
        print("[silence] \"\(text)\"")
        withKnownIssue("H6: silence transcribes as \"[BLANK_AUDIO]\"") {
            #expect(text.isEmpty, "got \"\(text)\"")
        }
    }

    @Test func silenceWithDictionaryPromptProducesNoWords() async throws {
        let prompt = DictionaryPromptBuilder.prompt(from: [DictionaryEntry(word: "Kubernetes", source: .manual)])
        let text = try await transcribe(.silence, prompt: prompt)
        print("[silence+prompt] \"\(text)\"")
        #expect(text.isEmpty, "got \"\(text)\"")
    }

    /// Regression (H12): with a dictionary, ordinary speech still transcribes.
    @Test(arguments: [Fixture.fillers, .selfCorrection, .longPassage])
    func dictionaryPromptDoesNotBlankOrdinarySpeech(_ fixture: Fixture) async throws {
        let prompt = DictionaryPromptBuilder.prompt(from: [
            DictionaryEntry(word: "Kubernetes", source: .manual),
            DictionaryEntry(word: "Priyanka", source: .automatic),
        ])
        let text = try await transcribe(fixture, prompt: prompt)
        print("[\(fixture.rawValue)+prompt] \(text.prefix(80))")
        #expect(Transcript.words(text).count >= 5, "got \"\(text)\"")
        #expect(!Transcript.contains(text, "kubernetes"), "prompt words leaked into unrelated speech")
    }

    @Test func noAudioReturnsEmpty() async throws {
        let transcriber = try await ModelStore.shared.loadedTranscriber()
        transcriber.reset()
        #expect(try await transcriber.transcribe(prompt: nil) == "")
    }
}
