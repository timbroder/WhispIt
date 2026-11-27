import Foundation
import Testing

private typealias Note = WhispItConstants.DarwinNotification

/// Shared state the "app" has written, plus what the keyboard posted.
final class FakeAppChannel: IPCChannel, @unchecked Sendable {
    var sharedState: SharedState?
    var cleanedText: String?
    private(set) var posts: [String] = []
    private var handlers: [String: () -> Void] = [:]

    func post(_ name: CFString) { posts.append(name as String) }
    func observe(_ name: CFString, handler: @escaping () -> Void) { handlers[name as String] = handler }
    func write<T: Encodable>(_ value: T, to file: WhispItConstants.SharedFile) throws {}
    func writeText(_ text: String, to file: WhispItConstants.SharedFile) throws {}
    func read<T: Decodable>(_ type: T.Type, from file: WhispItConstants.SharedFile) throws -> T {
        guard let state = sharedState as? T else { throw CocoaError(.fileNoSuchFile) }
        return state
    }
    func readText(from file: WhispItConstants.SharedFile) throws -> String {
        guard let cleanedText else { throw CocoaError(.fileNoSuchFile) }
        return cleanedText
    }

    /// The app posting a notification to the keyboard.
    func appPosts(_ name: CFString) { handlers[name as String]?() }
    func posted(_ name: CFString) -> Int { posts.filter { $0 == name as String }.count }
}

/// Runs scheduled work only when the test advances time.
final class ManualScheduler: KeyboardScheduler, @unchecked Sendable {
    final class Work: ScheduledWork {
        let due: TimeInterval
        let action: @MainActor () -> Void
        var cancelled = false
        init(due: TimeInterval, action: @escaping @MainActor () -> Void) { self.due = due; self.action = action }
        func cancel() { cancelled = true }
    }

    private(set) var now: TimeInterval = 0
    private var pending: [Work] = []

    func after(_ seconds: TimeInterval, _ work: @escaping @MainActor () -> Void) -> ScheduledWork {
        let item = Work(due: now + seconds, action: work)
        pending.append(item)
        return item
    }

    @MainActor
    func advance(_ seconds: TimeInterval) {
        now += seconds
        let due = pending.filter { !$0.cancelled && $0.due <= now }
        pending.removeAll { $0.cancelled || $0.due <= now }
        due.forEach { $0.action() }
    }
}

final class RecordingFeedback: KeyboardFeedback, @unchecked Sendable {
    private(set) var events: [String] = []
    func recordingStarted() { events.append("start") }
    func recordingStopped() { events.append("stop") }
    func textInserted() { events.append("inserted") }
    func failed() { events.append("failed") }
}

@MainActor
struct KeyboardHarness {
    let app = FakeAppChannel()
    let scheduler = ManualScheduler()
    let feedback = RecordingFeedback()
    let state = KeyboardState()
    let clock = Clock()
    let inserted = Inserted()
    let controller: KeyboardDictationController

    final class Clock: @unchecked Sendable { var now = Date(timeIntervalSince1970: 10_000) }
    final class Inserted: @unchecked Sendable { var texts: [String] = [] }

    init(initialState: SharedState? = nil, fullAccess: Bool = true) {
        app.sharedState = initialState
        controller = KeyboardDictationController(
            state: state,
            ipc: app,
            scheduler: scheduler,
            feedback: feedback,
            now: { [clock] in clock.now },
            hasFullAccess: { fullAccess },
            deliver: { work in MainActor.assumeIsolated { work() } },
            insertText: { [inserted] in inserted.texts.append($0) }
        )
        controller.activate()
    }

    /// The app confirming capture started.
    func appStartsRecording() {
        app.sharedState = SharedState(recordingActive: true, lastUpdated: clock.now)
        app.appPosts(Note.recordingStarted)
    }

    func appStopsRecording() {
        app.sharedState = SharedState(recordingActive: false, lastUpdated: clock.now)
        app.appPosts(Note.recordingStopped)
    }

    func appDelivers(_ text: String) {
        app.cleanedText = text
        app.sharedState = SharedState(recordingActive: false, lastUpdated: clock.now)
        app.appPosts(Note.cleanedTextReady)
    }

    func appFails(_ message: String) {
        app.sharedState = SharedState(recordingActive: false, lastError: message, lastUpdated: clock.now)
        app.appPosts(Note.recordingFailed)
    }
}

@Suite("KeyboardDictationController")
@MainActor
struct KeyboardDictationControllerTests {

    // MARK: Full loop (H1)

    @Test func firstTapRequestsStart() {
        let h = KeyboardHarness()
        h.controller.micTapped()
        #expect(h.app.posted(Note.recordingStartRequested) == 1)
        #expect(h.feedback.events == ["start"])
    }

    /// Regression (H1): once the app confirms, the second tap must stop.
    @Test func secondTapAfterAppConfirmsRequestsStop() {
        let h = KeyboardHarness()
        h.controller.micTapped()
        h.appStartsRecording()
        #expect(h.state.recordingActive)
        h.controller.micTapped()
        #expect(h.app.posted(Note.recordingStopRequested) == 1)
        #expect(h.app.posted(Note.recordingStartRequested) == 1)
        #expect(h.state.processing)
    }

    @Test func cleanedTextIsInsertedWithDoneFlash() {
        let h = KeyboardHarness()
        h.controller.micTapped()
        h.appStartsRecording()
        h.controller.micTapped()
        h.appDelivers("Ship it on Friday.")
        #expect(h.inserted.texts == ["Ship it on Friday."])
        #expect(!h.state.processing)
        #expect(!h.state.recordingActive)
        #expect(h.state.showDone)
        h.scheduler.advance(1)
        #expect(!h.state.showDone)
        #expect(h.feedback.events == ["start", "stop", "inserted"])
    }

    @Test func emptyCleanedTextInsertsNothing() {
        let h = KeyboardHarness()
        h.controller.micTapped()
        h.appStartsRecording()
        h.controller.micTapped()
        h.appDelivers("")
        #expect(h.inserted.texts.isEmpty)
        #expect(!h.state.processing)
    }

    @Test func silenceAutoStopStillDeliversText() {
        let h = KeyboardHarness()
        h.controller.micTapped()
        h.appStartsRecording()
        // No second tap: the app's VAD ended the recording.
        h.appDelivers("Auto stopped.")
        #expect(h.inserted.texts == ["Auto stopped."])
        #expect(!h.state.recordingActive)
    }

    /// Regression (U4): on silence auto-stop the keyboard used to keep showing
    /// "Listening…" with a stop button until the result arrived.
    @Test func autoStopSwitchesToProcessing() {
        let h = KeyboardHarness()
        h.controller.micTapped()
        h.appStartsRecording()
        h.appStopsRecording()
        #expect(h.state.processing)
        #expect(!h.state.recordingActive, "red ring and stop icon go away")
        h.appDelivers("Done.")
        #expect(!h.state.processing)
        #expect(h.inserted.texts == ["Done."])
    }

    @Test func autoStopProcessingTimesOut() {
        let h = KeyboardHarness()
        h.controller.micTapped()
        h.appStartsRecording()
        h.appStopsRecording()
        h.scheduler.advance(46)
        #expect(!h.state.processing)
        #expect(h.state.lastError == KeyboardDictationController.processingTimedOutMessage)
    }

    @Test func tapStopClearsRecordingStateImmediately() {
        let h = KeyboardHarness()
        h.controller.micTapped()
        h.appStartsRecording()
        h.controller.micTapped()
        #expect(!h.state.recordingActive)
        #expect(h.state.processing)
        // The app's own stop notification doesn't restart anything.
        h.appStopsRecording()
        #expect(h.state.processing)
        #expect(h.app.posted(Note.recordingStopRequested) == 1)
    }

    // MARK: Full Access (H5)

    /// Regression (H5): without Full Access dictation can't work; the user
    /// used to get the misleading "open the app" timeout instead.
    @Test func withoutFullAccessExplainsHowToEnableIt() {
        let h = KeyboardHarness(fullAccess: false)
        h.controller.micTapped()
        #expect(h.app.posts.isEmpty, "nothing is sent to the app")
        #expect(h.state.lastError == KeyboardDictationController.fullAccessRequiredMessage)
        #expect(!h.controller.awaitingStart)
        #expect(h.feedback.events == ["failed"])
        h.scheduler.advance(3)
        #expect(h.state.lastError == nil)
    }

    @Test func fullAccessMessageFitsTheBanner() {
        #expect(KeyboardDictationController.fullAccessRequiredMessage.count <= 90)
    }

    // MARK: App not answering (H4)

    /// Regression (H4): with the main app not running, the tap must not
    /// silently do nothing.
    @Test func startTimesOutWithOpenAppMessage() {
        let h = KeyboardHarness()
        h.controller.micTapped()
        h.scheduler.advance(2)
        #expect(h.state.lastError == nil)
        h.scheduler.advance(1)
        #expect(h.state.lastError == KeyboardDictationController.appNotRespondingMessage)
        #expect(!h.controller.awaitingStart)
        #expect(h.feedback.events.last == "failed")
        h.scheduler.advance(3)
        #expect(h.state.lastError == nil, "error clears itself")
    }

    @Test func confirmationCancelsStartTimeout() {
        let h = KeyboardHarness()
        h.controller.micTapped()
        h.appStartsRecording()
        h.scheduler.advance(10)
        #expect(h.state.lastError == nil)
        #expect(h.state.recordingActive)
    }

    @Test func appFailureIsShownAndCancelsTimeout() {
        let h = KeyboardHarness()
        h.controller.micTapped()
        h.appFails("Speech model is still loading. Open WhispIt and try again.")
        #expect(h.state.lastError?.contains("still loading") == true)
        h.scheduler.advance(2.9)
        #expect(h.state.lastError?.contains("still loading") == true, "not replaced by the timeout message")
        h.scheduler.advance(0.2)
        #expect(h.state.lastError == nil)
    }

    @Test func processingTimesOutAndRecovers() {
        let h = KeyboardHarness()
        h.controller.micTapped()
        h.appStartsRecording()
        h.controller.micTapped()
        h.scheduler.advance(46)
        #expect(!h.state.processing)
        #expect(!h.state.recordingActive)
        #expect(h.state.lastError == KeyboardDictationController.processingTimedOutMessage)
        // And the next tap starts a fresh recording.
        h.controller.micTapped()
        #expect(h.app.posted(Note.recordingStartRequested) == 2)
    }

    @Test func resultBeforeTimeoutCancelsProcessingTimeout() {
        let h = KeyboardHarness()
        h.controller.micTapped()
        h.appStartsRecording()
        h.controller.micTapped()
        h.appDelivers("Done.")
        h.scheduler.advance(60)
        #expect(h.state.lastError == nil)
    }

    @Test func failureDuringProcessingClearsSpinner() {
        let h = KeyboardHarness()
        h.controller.micTapped()
        h.appStartsRecording()
        h.controller.micTapped()
        h.appFails("No speech detected")
        #expect(!h.state.processing)
        #expect(h.state.lastError == "No speech detected")
    }

    @Test func newTapClearsPreviousError() {
        let h = KeyboardHarness()
        h.controller.micTapped()
        h.appFails("No speech detected")
        h.controller.micTapped()
        #expect(h.state.lastError == nil)
    }

    // MARK: Opening the keyboard (H11)

    /// Regression (H11): an error from an earlier session isn't re-shown.
    @Test func staleErrorIsIgnoredOnOpen() {
        let old = Date(timeIntervalSince1970: 10_000 - 60)
        let h = KeyboardHarness(initialState: SharedState(lastError: "No speech detected", lastUpdated: old))
        #expect(h.state.lastError == nil)
    }

    @Test func freshErrorIsShownOnOpen() {
        let recent = Date(timeIntervalSince1970: 10_000 - 1)
        let h = KeyboardHarness(initialState: SharedState(lastError: "Recording interrupted", lastUpdated: recent))
        #expect(h.state.lastError == "Recording interrupted")
    }

    @Test func reopeningMidRecordingShowsRecording() {
        let h = KeyboardHarness(initialState: SharedState(recordingActive: true, lastUpdated: Date(timeIntervalSince1970: 9_000)))
        #expect(h.state.recordingActive)
        h.controller.micTapped()
        #expect(h.app.posted(Note.recordingStopRequested) == 1)
    }

    @Test func missingSharedStateLeavesKeyboardIdle() {
        let h = KeyboardHarness(initialState: nil)
        #expect(!h.state.recordingActive)
        #expect(h.state.lastError == nil)
    }
}
