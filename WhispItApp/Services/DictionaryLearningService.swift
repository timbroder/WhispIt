import Foundation

final class DictionaryLearningService {
    static let promotionThreshold = 3

    private static let candidatesDefaultsKey = "WhispIt.dictionary.candidates"
    private static let exclusions: Set<String> = [
        "i", "i've", "i'm", "i'll", "i'd",
        "ok", "okay",
        "mr", "mrs", "ms", "dr", "jr", "sr", "st"
    ]

    private let dictionary: DictionaryManager
    private let defaults: UserDefaults?

    init(
        dictionary: DictionaryManager = .shared,
        defaults: UserDefaults? = UserDefaults(suiteName: WhispItConstants.appGroupID)
    ) {
        self.dictionary = dictionary
        self.defaults = defaults
    }

    func observe(cleanedText: String) {
        let candidates = Self.extractCandidates(from: cleanedText)
        guard !candidates.isEmpty else { return }

        let existingWords = Set(dictionary.allEntries.map { $0.word.lowercased() })
        var counts = loadCandidates()

        for word in candidates {
            let key = word.lowercased()

            if existingWords.contains(key) {
                dictionary.incrementFrequency(for: word)
                counts.removeValue(forKey: key)
                continue
            }

            let nextCount = (counts[key] ?? 0) + 1
            if nextCount >= Self.promotionThreshold {
                dictionary.add(word: word, source: .automatic)
                counts.removeValue(forKey: key)
            } else {
                counts[key] = nextCount
            }
        }

        saveCandidates(counts)
    }

    static func extractCandidates(from text: String) -> [String] {
        let separators = CharacterSet.whitespacesAndNewlines
        let tokens = text.components(separatedBy: separators)
        var candidates: [String] = []
        var atSentenceStart = true

        for raw in tokens {
            let cleaned = raw.trimmingCharacters(in: .punctuationCharacters)
            defer {
                if let last = raw.last, last == "." || last == "!" || last == "?" {
                    atSentenceStart = true
                } else if !cleaned.isEmpty {
                    atSentenceStart = false
                }
            }

            guard !cleaned.isEmpty else { continue }
            guard cleaned.contains(where: \.isLetter) else { continue }
            guard !exclusions.contains(cleaned.lowercased()) else { continue }

            let isAllCaps = cleaned.count >= 2 && cleaned == cleaned.uppercased()
            let startsWithUpper = cleaned.first?.isUppercase ?? false

            if isAllCaps || (!atSentenceStart && startsWithUpper) {
                candidates.append(cleaned)
            }
        }

        return candidates
    }

    private func loadCandidates() -> [String: Int] {
        guard let data = defaults?.data(forKey: Self.candidatesDefaultsKey),
              let dict = try? JSONDecoder().decode([String: Int].self, from: data) else {
            return [:]
        }
        return dict
    }

    private func saveCandidates(_ candidates: [String: Int]) {
        guard let data = try? JSONEncoder().encode(candidates) else { return }
        defaults?.set(data, forKey: Self.candidatesDefaultsKey)
    }
}
