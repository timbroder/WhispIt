import Foundation

struct TranscriptionResult: Codable, Hashable {
    let raw: String
    let cleaned: String
    let timestamp: Date

    init(raw: String, cleaned: String, timestamp: Date = Date()) {
        self.raw = raw
        self.cleaned = cleaned
        self.timestamp = timestamp
    }
}
