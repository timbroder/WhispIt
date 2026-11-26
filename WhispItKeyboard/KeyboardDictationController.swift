import Foundation

/// Cancellable delayed work, so timeouts can be faked in tests.
protocol ScheduledWork {
    func cancel()
}

protocol KeyboardScheduler {
    @discardableResult
    func after(_ seconds: TimeInterval, _ work: @escaping @MainActor () -> Void) -> ScheduledWork
}

protocol KeyboardFeedback {
    func recordingStarted()
    func recordingStopped()
    func textInserted()
    func failed()
}

struct MainQueueScheduler: KeyboardScheduler {
    private final class Item: ScheduledWork {
        let item: DispatchWorkItem
        init(_ item: DispatchWorkItem) { self.item = item }
        func cancel() { item.cancel() }
    }

    func after(_ seconds: TimeInterval, _ work: @escaping @MainActor () -> Void) -> ScheduledWork {
        let item = DispatchWorkItem { MainActor.assumeIsolated { work() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
        return Item(item)
    }
}

/// The keyboard's half of the dictation protocol: sends start/stop to the
/// main app, mirrors its state into `KeyboardState`, inserts the result, and
/// recovers with a message when the app doesn't answer.
@MainActor
final class KeyboardDictationController {
    struct Timing {
        /// How long to wait for the app to confirm recording started.
        var startTimeout: TimeInterval = 2.5
        /// How long to wait for cleaned text after stopping.
        var processingTimeout: TimeInterval = 45
        var errorDisplay: TimeInterval = 3
        var doneFlash: TimeInterval = 0.8
        /// Errors older than this in shared state belong to a previous session.
        var staleErrorAge: TimeInterval = 5
    }

    static let appNotRespondingMessage = "Open the WhispIt app to turn on dictation."
    static let processingTimedOutMessage = "Dictation timed out. Try again."

    let state: KeyboardState
    private let ipc: IPCChannel
    private let scheduler: KeyboardScheduler
    private let feedback: KeyboardFeedback
    private let timing: Timing
    private let now: () -> Date
    private let insertText: (String) -> Void
    /// Hops an IPC callback (any thread) onto the main actor.
    private let deliver: (@escaping @MainActor () -> Void) -> Void

    private var startTimeout: ScheduledWork?
    private var processingTimeout: ScheduledWork?
    private var errorClear: ScheduledWork?
    private(set) var awaitingStart = false

    init(
        state: KeyboardState,
        ipc: IPCChannel,
        scheduler: KeyboardScheduler = MainQueueScheduler(),
        feedback: KeyboardFeedback,
        timing: Timing = Timing(),
        now: @escaping () -> Date = Date.init,
        deliver: @escaping (@escaping @MainActor () -> Void) -> Void = { work in
            DispatchQueue.main.async { MainActor.assumeIsolated { work() } }
        },
        insertText: @escaping (String) -> Void
    ) {
        self.state = state
        self.ipc = ipc
        self.scheduler = scheduler
        self.feedback = feedback
        self.timing = timing
        self.now = now
        self.deliver = deliver
        self.insertText = insertText
    }

    func activate() {
        typealias Note = WhispItConstants.DarwinNotification
        ipc.observe(Note.recordingStarted) { [weak self] in
            self?.deliver { self?.handleRecordingStarted() }
        }
        ipc.observe(Note.recordingStopped) { [weak self] in
            self?.deliver { self?.handleRecordingStopped() }
        }
        ipc.observe(Note.cleanedTextReady) { [weak self] in
            self?.deliver { self?.handleCleanedTextReady() }
        }
        ipc.observe(Note.transcriptionUpdated) { [weak self] in
            self?.deliver { self?.refreshFromSharedState() }
        }
        ipc.observe(Note.recordingFailed) { [weak self] in
            self?.deliver { self?.handleRecordingFailed() }
        }
        refreshFromSharedState(ignoringStaleError: true)
    }

    func micTapped() {
        if state.recordingActive {
            feedback.recordingStopped()
            ipc.post(WhispItConstants.DarwinNotification.recordingStopRequested)
            enterProcessing()
        } else {
            feedback.recordingStarted()
            state.lastError = nil
            awaitingStart = true
            ipc.post(WhispItConstants.DarwinNotification.recordingStartRequested)
            startTimeout?.cancel()
            startTimeout = scheduler.after(timing.startTimeout) { [weak self] in
                self?.handleStartTimeout()
            }
        }
    }

    /// Re-reads shared state, e.g. when the keyboard reappears.
    func refreshFromSharedState(ignoringStaleError: Bool = false) {
        guard var shared = try? ipc.read(SharedState.self, from: .sharedState) else { return }
        if ignoringStaleError, now().timeIntervalSince(shared.lastUpdated) > timing.staleErrorAge {
            shared.lastError = nil
        }
        state.apply(shared)
    }

    private func handleRecordingStarted() {
        awaitingStart = false
        startTimeout?.cancel()
        refreshFromSharedState()
    }

    /// The app stopped capturing (after a tap or on silence) and is working
    /// on the transcript.
    private func handleRecordingStopped() {
        guard !state.processing else { return }
        enterProcessing()
    }

    private func enterProcessing() {
        state.recordingActive = false
        state.processing = true
        processingTimeout?.cancel()
        processingTimeout = scheduler.after(timing.processingTimeout) { [weak self] in
            self?.handleProcessingTimeout()
        }
    }

    private func handleCleanedTextReady() {
        processingTimeout?.cancel()
        state.processing = false
        refreshFromSharedState()
        guard let cleaned = try? ipc.readText(from: .cleanedText), !cleaned.isEmpty else { return }
        insertText(cleaned)
        state.interimTranscript = ""
        state.showDone = true
        feedback.textInserted()
        scheduler.after(timing.doneFlash) { [weak self] in
            self?.state.showDone = false
        }
    }

    private func handleRecordingFailed() {
        awaitingStart = false
        startTimeout?.cancel()
        processingTimeout?.cancel()
        state.processing = false
        refreshFromSharedState()
        feedback.failed()
        scheduleErrorClear()
    }

    private func handleStartTimeout() {
        guard awaitingStart else { return }
        awaitingStart = false
        show(error: Self.appNotRespondingMessage)
    }

    private func handleProcessingTimeout() {
        guard state.processing else { return }
        state.processing = false
        state.recordingActive = false
        show(error: Self.processingTimedOutMessage)
    }

    private func show(error message: String) {
        state.lastError = message
        feedback.failed()
        scheduleErrorClear()
    }

    private func scheduleErrorClear() {
        errorClear?.cancel()
        errorClear = scheduler.after(timing.errorDisplay) { [weak self] in
            self?.state.lastError = nil
        }
    }
}
