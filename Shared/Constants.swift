import Foundation

enum WhispItConstants {
    static let appGroupID = "group.com.whispit.shared"

    enum DarwinNotification {
        static let recordingStartRequested = "com.whispit.notification.recordingStartRequested" as CFString
        static let recordingStopRequested = "com.whispit.notification.recordingStopRequested" as CFString
        /// App → keyboard: capture is running; re-read shared state.
        static let recordingStarted = "com.whispit.notification.recordingStarted" as CFString
        /// App → keyboard: capture ended (tap or silence); transcription is running.
        static let recordingStopped = "com.whispit.notification.recordingStopped" as CFString
        static let transcriptionUpdated = "com.whispit.notification.transcriptionUpdated" as CFString
        static let cleanedTextReady = "com.whispit.notification.cleanedTextReady" as CFString
        static let recordingFailed = "com.whispit.notification.recordingFailed" as CFString
    }

    enum SharedFile: String {
        case sharedState = "shared-state.json"
        case cleanedText = "cleaned-text.txt"
        case dictionary = "dictionary.json"
    }

    static var sharedContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    static func sharedFileURL(_ file: SharedFile) -> URL? {
        sharedContainerURL?.appendingPathComponent(file.rawValue)
    }
}
