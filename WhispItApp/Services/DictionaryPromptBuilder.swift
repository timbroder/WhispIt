import Foundation

enum DictionaryPromptBuilder {
    static func prompt(from entries: [DictionaryEntry], maxWords: Int = 50) -> String? {
        let words = entries
            .sorted { $0.frequency > $1.frequency }
            .prefix(maxWords)
            .map(\.word)

        guard !words.isEmpty else { return nil }
        return "Vocabulary: " + words.joined(separator: ", ") + "."
    }
}
