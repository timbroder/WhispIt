import Foundation
import os

/// Logging for the dictation pipeline. Never logs transcript text: only
/// lengths, states and timings.
enum PipelineLog {
    static let subsystem = "com.whispit.app"
    static let logger = Logger(subsystem: subsystem, category: "pipeline")
    static let signposter = OSSignposter(subsystem: subsystem, category: "pipeline")

    static func milliseconds(_ duration: Duration) -> Int {
        let (seconds, attoseconds) = duration.components
        return Int(seconds * 1_000 + attoseconds / 1_000_000_000_000_000)
    }
}
