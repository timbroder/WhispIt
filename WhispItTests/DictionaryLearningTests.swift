import Foundation
import Testing
@testable import WhispIt

@Suite("DictionaryLearningService.extractCandidates")
struct CandidateExtractionTests {
    func candidates(_ text: String) -> [String] {
        DictionaryLearningService.extractCandidates(from: text)
    }

    @Test func capitalizedWordMidSentenceIsACandidate() {
        #expect(candidates("send the report to Priyanka today") == ["Priyanka"])
    }

    @Test func firstWordOfASentenceIsNotACandidate() {
        #expect(candidates("Hello there. Goodbye now") == [])
    }

    @Test(arguments: ["Done! Next", "Really? Yes", "Fine. Okay then"])
    func sentenceEndingPunctuationResetsSentenceStart(_ text: String) {
        #expect(candidates(text).isEmpty)
    }

    @Test func acronymsCountEvenAtSentenceStart() {
        #expect(candidates("NASA launched it with the ESA") == ["NASA", "ESA"])
    }

    @Test func pronounIIsNeverACandidate() {
        #expect(candidates("so I think I can").isEmpty)
    }

    /// Regression (L1): single letters were learned and added to the prompt.
    @Test(arguments: ["plan B is fine", "take vitamin C daily", "row A seat"])
    func singleCapitalLettersAreNotLearned(_ text: String) {
        #expect(candidates(text).isEmpty)
    }

    @Test func twoLetterAcronymsAreStillLearned() {
        #expect(candidates("ping the QA team and HR") == ["QA", "HR"])
    }

    @Test(arguments: ["I", "OK", "Ok", "Mr", "Dr", "I'm", "I'll"])
    func commonWordsAreExcluded(_ word: String) {
        #expect(candidates("well \(word) then").isEmpty)
    }

    @Test func surroundingPunctuationIsStripped() {
        #expect(candidates("thanks to Anthropic, and (Kubernetes).") == ["Anthropic", "Kubernetes"])
    }

    @Test func numbersAndSymbolsAreIgnored() {
        #expect(candidates("we shipped 2024 builds — 100%") == [])
    }

    @Test func emptyTextHasNoCandidates() {
        #expect(candidates("") == [])
        #expect(candidates("   \n ") == [])
    }
}

@Suite("DictionaryLearningService.observe")
struct DictionaryLearningTests {
    let tempDir = TemporaryDirectory()
    let isolated = IsolatedDefaults()
    let dictionary: DictionaryManager
    let service: DictionaryLearningService

    init() {
        dictionary = DictionaryManager(fileURL: tempDir.file("dictionary.json"))
        service = DictionaryLearningService(dictionary: dictionary, defaults: isolated.defaults)
    }

    @Test func wordIsLearnedAfterThreeSightings() throws {
        service.observe(cleanedText: "ping Priyanka now")
        service.observe(cleanedText: "ask Priyanka later")
        #expect(dictionary.allEntries.isEmpty)
        service.observe(cleanedText: "thanks Priyanka")
        let entry = try #require(dictionary.allEntries.first)
        #expect(entry.word == "Priyanka")
        #expect(entry.source == .automatic)
    }

    @Test func sightingsPersistAcrossServiceInstances() {
        service.observe(cleanedText: "ping Priyanka now")
        service.observe(cleanedText: "ping Priyanka again")
        let restarted = DictionaryLearningService(dictionary: dictionary, defaults: isolated.defaults)
        restarted.observe(cleanedText: "and Priyanka once more")
        #expect(dictionary.allEntries.map(\.word) == ["Priyanka"])
    }

    @Test func knownWordsBumpFrequencyInsteadOfCounting() throws {
        dictionary.add(word: "Kubernetes", source: .manual)
        service.observe(cleanedText: "deploy to Kubernetes today")
        let entry = try #require(dictionary.allEntries.first)
        #expect(entry.frequency == 2)
        #expect(dictionary.allEntries.count == 1)
    }

    @Test func casingVariantsCountAsTheSameWord() {
        service.observe(cleanedText: "use the Swift compiler")
        service.observe(cleanedText: "use SWIFT today")
        service.observe(cleanedText: "learn Swift")
        #expect(dictionary.allEntries.count == 1)
    }
}

@Suite("DictionaryPromptBuilder")
struct DictionaryPromptBuilderTests {
    func entry(_ word: String, _ frequency: Int) -> DictionaryEntry {
        DictionaryEntry(word: word, source: .manual, frequency: frequency)
    }

    @Test func emptyDictionaryProducesNoPrompt() {
        #expect(DictionaryPromptBuilder.prompt(from: []) == nil)
    }

    @Test func wordsAreOrderedByFrequency() {
        let prompt = DictionaryPromptBuilder.prompt(from: [entry("Rare", 1), entry("Common", 9), entry("Mid", 4)])
        #expect(prompt == "Vocabulary: Common, Mid, Rare.")
    }

    @Test func promptIsCappedAtMaxWords() throws {
        let entries = (0..<80).map { entry("Word\($0)", $0) }
        let prompt = try #require(DictionaryPromptBuilder.prompt(from: entries))
        let words = prompt
            .replacingOccurrences(of: "Vocabulary: ", with: "")
            .dropLast()
            .components(separatedBy: ", ")
        #expect(words.count == 50)
        #expect(words.first == "Word79")
    }

    /// Engines that take a word list (the bake-off prototypes) get the same
    /// words, in the same order, as Whisper's prompt.
    @Test func wordListMatchesThePrompt() {
        let entries = [entry("Rare", 1), entry("Common", 9), entry("Mid", 4)]
        #expect(DictionaryPromptBuilder.words(from: entries) == ["Common", "Mid", "Rare"])
        #expect(DictionaryPromptBuilder.words(from: entries, maxWords: 2) == ["Common", "Mid"])
        #expect(DictionaryPromptBuilder.words(from: []).isEmpty)
    }
}

#if DEBUG
@Suite("ASREngine debug override")
struct ASREngineTests {
    @Test func everyEngineBuildsATranscriber() {
        #expect(ASREngine.whisper.makeTranscriber() is TranscriptionService)
        #expect(ASREngine.speechAnalyzer.makeTranscriber() is SpeechAnalyzerTranscriber)
        #expect((ASREngine.speechAnalyzerBatch.makeTranscriber() as? SpeechAnalyzerTranscriber)?.mode == .batch)
    }

    @Test(arguments: ASREngine.allCases)
    func prototypesStartUnloaded(_ engine: ASREngine) {
        #expect(!engine.makeTranscriber().isModelLoaded)
    }

    /// Without the launch argument the shipping engine is used.
    @Test func defaultIsWhisperKit() {
        #expect(DebugOverrides.asrEngine == nil)
        #expect(DictationPipelineCoordinator.makeTranscriber() is TranscriptionService)
    }
}
#endif
