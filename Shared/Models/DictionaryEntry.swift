import Foundation

struct DictionaryEntry: Codable, Identifiable, Hashable {
    let id: UUID
    let word: String
    let dateAdded: Date
    let source: EntrySource
    var frequency: Int

    enum EntrySource: String, Codable, CaseIterable {
        case automatic
        case manual
    }

    init(
        id: UUID = UUID(),
        word: String,
        dateAdded: Date = Date(),
        source: EntrySource,
        frequency: Int = 1
    ) {
        self.id = id
        self.word = word
        self.dateAdded = dateAdded
        self.source = source
        self.frequency = frequency
    }
}
