import Foundation
import Testing
@testable import WhispIt

/// Regression (H13): cleanup keeps only the corrected version. Before the
/// prompt change 5 of 12 runs kept the retracted word (one produced
/// "three or four o'clock"); after it, 12 of 12 passed.
@Suite("Self-correction cleanup", .serialized,
       .enabled(if: appleIntelligenceAvailable, "Apple Intelligence is not available on this Mac"))
struct SelfCorrectionTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let raw: String
        let keep: String
        let drop: String
        var testDescription: String { raw }
    }

    static let cases: [Case] = [
        Case(raw: "let's meet at three no wait let's meet at four o'clock tomorrow", keep: "four", drop: "three"),
        Case(raw: "please send the file to john i mean sarah before lunch", keep: "sarah", drop: "john"),
        Case(raw: "the ticket costs fifty sorry sixty dollars", keep: "sixty", drop: "fifty"),
        Case(raw: "we should ship on tuesday actually no make that wednesday", keep: "wednesday", drop: "tuesday"),
    ]

    init() async {
        await FoundationModelsWarmup.shared.ensure()
    }

    @Test(arguments: cases)
    func keepsOnlyTheCorrectedVersion(_ c: Case) async throws {
        let cleaned = try await CleanupService().clean(c.raw)
        let numbers = ["three": "3", "four": "4", "fifty": "50", "sixty": "60"]
        func mentions(_ word: String) -> Bool {
            Transcript.contains(cleaned, word) || numbers[word].map { cleaned.contains($0) } == true
        }
        print("[self-correction] \(c.raw) → \(cleaned)")
        #expect(mentions(c.keep), "lost the correction: \(cleaned)")
        #expect(!mentions(c.drop), "kept the retracted word: \(cleaned)")
    }
}
