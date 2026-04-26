import Foundation

struct SharedState: Codable, Hashable {
    var recordingActive: Bool
    var lastInterimTranscript: String
    var lastError: String?
    var lastUpdated: Date

    init(
        recordingActive: Bool = false,
        lastInterimTranscript: String = "",
        lastError: String? = nil,
        lastUpdated: Date = Date()
    ) {
        self.recordingActive = recordingActive
        self.lastInterimTranscript = lastInterimTranscript
        self.lastError = lastError
        self.lastUpdated = lastUpdated
    }

    static let idle = SharedState()
}
