import Foundation
import Testing
@testable import WhispIt

@Suite("SettingsManager")
struct SettingsManagerTests {
    let isolated = IsolatedDefaults()

    @Test func silenceTimeoutDefaultsToTwoSeconds() {
        #expect(SettingsManager(defaults: isolated.defaults).silenceTimeoutSeconds == 2)
    }

    @Test(arguments: [1.0, 3.0, 5.0])
    func silenceTimeoutPersists(_ value: TimeInterval) {
        SettingsManager(defaults: isolated.defaults).silenceTimeoutSeconds = value
        #expect(SettingsManager(defaults: isolated.defaults).silenceTimeoutSeconds == value)
    }
}

@Suite("Shared models")
struct SharedModelTests {
    @Test func sharedStateRoundTripsThroughISO8601JSON() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let state = SharedState(
            recordingActive: true,
            lastInterimTranscript: "hello",
            lastError: "boom",
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let decoded = try decoder.decode(SharedState.self, from: encoder.encode(state))
        #expect(decoded == state)
    }

    @Test func idleStateIsNotRecordingAndHasNoError() {
        #expect(!SharedState.idle.recordingActive)
        #expect(SharedState.idle.lastError == nil)
        #expect(SharedState.idle.lastInterimTranscript.isEmpty)
    }

    @Test func dictionaryEntryRoundTrips() throws {
        let entry = DictionaryEntry(word: "Swift", dateAdded: Date(timeIntervalSince1970: 0), source: .automatic, frequency: 3)
        let decoded = try JSONDecoder().decode(DictionaryEntry.self, from: JSONEncoder().encode(entry))
        #expect(decoded == entry)
    }
}

/// Exercises the real App Group container through the test host app.
@Suite("IPCManager shared files", .serialized)
struct IPCManagerTests {
    @Test func appGroupContainerIsAvailableToTheApp() {
        #expect(WhispItConstants.sharedContainerURL != nil)
    }

    @Test func sharedStateRoundTrips() throws {
        let state = SharedState(recordingActive: true, lastInterimTranscript: "partial",
                                lastUpdated: Date(timeIntervalSince1970: 1_700_000_000))
        try IPCManager.shared.write(state, to: .sharedState)
        let read = try IPCManager.shared.read(SharedState.self, from: .sharedState)
        #expect(read == state)
        try IPCManager.shared.write(SharedState.idle, to: .sharedState)
    }

    @Test func textRoundTripsIncludingUnicodeAndNewlines() throws {
        let text = "Café — naïve résumé 👋\nSecond paragraph."
        try IPCManager.shared.writeText(text, to: .cleanedText)
        #expect(try IPCManager.shared.readText(from: .cleanedText) == text)
    }

    @Test func darwinNotificationsReachObserversInProcess() async {
        let name = "com.whispit.notification.test.\(UUID().uuidString)" as CFString
        let received = LockedFlag()
        IPCManager.shared.observe(name) { received.set() }
        defer { IPCManager.shared.removeObserver(name) }
        IPCManager.shared.post(name)
        #expect(await waitUntil { received.value })
    }
}

final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false
    var value: Bool { lock.withLock { _value } }
    func set() { lock.withLock { _value = true } }
}
