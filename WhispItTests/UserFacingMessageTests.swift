import Foundation
import FoundationModels
import Testing
@testable import WhispIt

/// Regression (U1): users see plain-language messages, not Swift enum or
/// error descriptions.
@Suite("User-facing messages")
@MainActor
struct UserFacingMessageTests {
    @Test(arguments: [
        SystemLanguageModel.Availability.UnavailableReason.deviceNotEligible,
        .appleIntelligenceNotEnabled,
        .modelNotReady,
    ])
    func appleIntelligenceReasonsAreReadable(_ reason: SystemLanguageModel.Availability.UnavailableReason) {
        let message = OnboardingView.describe(reason)
        #expect(!message.contains(String(describing: reason)))
        #expect(message.first?.isUppercase == true)
        #expect(message.hasSuffix("."))
    }

    @Test func offlineDownloadExplainsConnection() {
        let error = URLError(.notConnectedToInternet)
        #expect(AppLifecycle.userMessage(forDownloadError: error).contains("internet connection"))
    }

    @Test func fullDiskExplainsSpace() {
        let error = CocoaError(.fileWriteOutOfSpace)
        #expect(AppLifecycle.userMessage(forDownloadError: error).contains("1 GB"))
    }

    @Test func unknownErrorsStayGeneric() {
        struct Weird: Error {}
        let message = AppLifecycle.userMessage(forDownloadError: Weird())
        #expect(!message.contains("Weird"))
        #expect(message.contains("Retry"))
    }
}
