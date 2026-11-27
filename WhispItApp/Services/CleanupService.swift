import FoundationModels
import Foundation

final class CleanupService {
    enum CleanupError: Error {
        case appleIntelligenceUnavailable(SystemLanguageModel.Availability.UnavailableReason)
    }

    @Generable
    struct CleanedTranscript {
        let text: String
    }

    private static let instructions = """
    You are a dictation cleanup assistant. Clean up raw voice transcriptions:
    - Remove filler words (um, uh, like, you know, so, basically)
    - Remove false starts and self-corrections (keep only the corrected version)
    - Fix grammar and punctuation
    - Maintain the speaker's intended meaning exactly
    - Do NOT add, embellish, or change the meaning
    - Format appropriately (paragraph breaks for long passages)
    Output only the cleaned text in the `text` field. No commentary.
    """

    private let lock = NSLock()
    private var preparedSession: LanguageModelSession?

    var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    /// Creates the next dictation's session and prewarms the on-device model.
    /// The first cleanup after launch took ~8 s cold in the simulator.
    func prepare() {
        guard isAvailable else { return }
        let session = makeSession()
        session.prewarm()
        lock.withLock { preparedSession = session }
    }

    private func makeSession() -> LanguageModelSession {
        LanguageModelSession(model: SystemLanguageModel.default, instructions: Self.instructions)
    }

    /// Hands out the prewarmed session once; each dictation gets a fresh one so
    /// earlier transcripts never leak into the context.
    private func takeSession() -> LanguageModelSession {
        let prepared = lock.withLock { () -> LanguageModelSession? in
            defer { preparedSession = nil }
            return preparedSession
        }
        return prepared ?? makeSession()
    }

    func clean(_ raw: String) async throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let model = SystemLanguageModel.default
        if case .unavailable(let reason) = model.availability {
            throw CleanupError.appleIntelligenceUnavailable(reason)
        }

        let session = takeSession()
        let response = try await session.respond(to: trimmed, generating: CleanedTranscript.self)
        return response.content.text
    }
}
