#if DEBUG
import Foundation

/// Speech engines a debug build can run instead of WhisperKit, for the
/// WhispIt-peu bake-off. Pick one with `-WhispItASREngine <rawValue>`.
/// Release builds always use `TranscriptionService` (WhisperKit).
///
/// SpeechAnalyzer uses the system's assets, so onboarding's Whisper download
/// still runs; pair the flag with `-WhispItModelVariant openai_whisper-tiny`
/// to keep that download small. The Parakeet prototype is test-only (see
/// WhispItIntegrationTests/Bakeoff/ParakeetTranscriber.swift).
enum ASREngine: String, CaseIterable {
    case whisper
    case speechAnalyzer = "speech-analyzer"
    case speechAnalyzerBatch = "speech-analyzer-batch"

    func makeTranscriber() -> Transcribing {
        switch self {
        case .whisper: TranscriptionService()
        case .speechAnalyzer: SpeechAnalyzerTranscriber(mode: .streaming)
        case .speechAnalyzerBatch: SpeechAnalyzerTranscriber(mode: .batch)
        }
    }
}

/// Dictionary words for engines that take a word list rather than Whisper's
/// prompt sentence, most frequent first like the prompt.
enum DictionaryVocabulary {
    static func current() -> [String] {
        DictionaryPromptBuilder.words(
            from: DictionaryManager.shared.allEntries,
            maxWords: SpeechAnalyzerTranscriber.maxContextualStrings
        )
    }
}
#endif
