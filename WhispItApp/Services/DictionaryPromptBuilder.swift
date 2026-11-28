import Foundation

enum DictionaryPromptBuilder {
    static func prompt(from entries: [DictionaryEntry], maxWords: Int = 50) -> String? {
        let words = Self.words(from: entries, maxWords: maxWords)
        guard !words.isEmpty else { return nil }
        return "Vocabulary: " + words.joined(separator: ", ") + "."
    }

    /// The dictionary words to bias recognition towards, most frequent first.
    static func words(from entries: [DictionaryEntry], maxWords: Int = 50) -> [String] {
        entries
            .sorted { $0.frequency > $1.frequency }
            .prefix(maxWords)
            .map(\.word)
    }
}
