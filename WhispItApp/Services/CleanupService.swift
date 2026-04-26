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

    var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    func clean(_ raw: String) async throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let model = SystemLanguageModel.default
        if case .unavailable(let reason) = model.availability {
            throw CleanupError.appleIntelligenceUnavailable(reason)
        }

        let session = LanguageModelSession(model: model, instructions: Self.instructions)
        let response = try await session.respond(to: trimmed, generating: CleanedTranscript.self)
        return response.content.text
    }
}
