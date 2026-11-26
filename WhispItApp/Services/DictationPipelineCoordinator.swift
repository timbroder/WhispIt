import AVFoundation
import Foundation

// Thread safety: every mutable property except `didStartObserving` is read and
// written only on `queue` (a serial queue). `didStartObserving` is touched only by
// `startObserving()`, which AppLifecycle calls on the main actor. `finalize()` runs
// off-queue but uses only immutable (`let`) services. Keep new mutable state on
// `queue` to preserve this invariant.
final class DictationPipelineCoordinator: @unchecked Sendable {
    static let shared = DictationPipelineCoordinator()

    private let queue = DispatchQueue(label: "com.whispit.pipeline")

    private let audioCapture: AudioCaptureService
    private let transcription: Transcribing
    private let cleanup: TextCleaning
    private let dictionary: DictionaryManager
    private let learning: DictionaryLearningService
    private let interruption: AudioInterruptionHandler
    private let backgroundSession: KeepAliveSession
    private let ipc: IPCChannel
    private let makeDetector: () -> VoiceActivityDetector

    private var vad: VoiceActivityDetector
    private var consumerTask: Task<Void, Never>?
    private var isRecording = false
    private var isFinalizing = false
    private var didStartObserving = false

    init(
        audioCapture: AudioCaptureService = AudioCaptureService(),
        transcription: Transcribing = TranscriptionService(),
        cleanup: TextCleaning = CleanupService(),
        dictionary: DictionaryManager = .shared,
        learning: DictionaryLearningService? = nil,
        interruption: AudioInterruptionHandler = AudioInterruptionHandler(),
        backgroundSession: KeepAliveSession = BackgroundAudioSessionManager.shared,
        ipc: IPCChannel = IPCManager.shared,
        makeDetector: @escaping () -> VoiceActivityDetector = { VoiceActivityDetector() }
    ) {
        self.audioCapture = audioCapture
        self.transcription = transcription
        self.cleanup = cleanup
        self.dictionary = dictionary
        self.learning = learning ?? DictionaryLearningService(dictionary: dictionary)
        self.interruption = interruption
        self.backgroundSession = backgroundSession
        self.ipc = ipc
        self.makeDetector = makeDetector
        self.vad = makeDetector()
    }

    var isModelLoaded: Bool { transcription.isModelLoaded }

    func loadWhisperModel(at folder: URL) async throws {
        try await transcription.loadModel(at: folder)
    }

    func startObserving() {
        guard !didStartObserving else { return }
        didStartObserving = true

        ipc.observe(WhispItConstants.DarwinNotification.recordingStartRequested) { [weak self] in
            self?.queue.async { self?.handleStartRequested() }
        }
        ipc.observe(WhispItConstants.DarwinNotification.recordingStopRequested) { [weak self] in
            self?.queue.async { self?.handleStopRequested() }
        }

        interruption.onInterruptionBegan = { [weak self] in
            self?.queue.async { self?.handleInterruption() }
        }
        interruption.onInterruptionEnded = { [weak self] _ in
            try? self?.backgroundSession.start()
        }
        interruption.onRouteChanged = { [weak self] reason in
            if reason == .oldDeviceUnavailable {
                self?.queue.async { self?.handleInterruption() }
            }
        }
        interruption.start()
    }

    /// Blocks until all work already queued on the pipeline queue has run.
    /// Test hook; does not wait for an in-flight `finalize()`.
    func drainQueue() {
        queue.sync {}
    }

    private func handleStartRequested() {
        if isRecording {
            // The keyboard lost track (e.g. it was reloaded mid-recording).
            // Tell it again instead of silently ignoring the tap.
            PipelineLog.logger.info("Start while recording; re-announcing")
            ipc.post(WhispItConstants.DarwinNotification.recordingStarted)
            return
        }
        guard !isFinalizing else {
            PipelineLog.logger.info("Start ignored while finalizing")
            return
        }
        guard transcription.isModelLoaded else {
            PipelineLog.logger.error("Start rejected: model not loaded")
            writeError("Speech model is still loading. Open WhispIt and try again.")
            ipc.post(WhispItConstants.DarwinNotification.recordingFailed)
            return
        }

        isRecording = true
        transcription.reset()

        let detector = makeDetector()
        detector.onSilenceTimeout = { [weak self] in
            PipelineLog.logger.info("Silence timeout")
            self?.queue.async { self?.handleStopRequested() }
        }
        vad = detector

        let state = SharedState(recordingActive: true)
        try? ipc.write(state, to: .sharedState)

        do {
            let stream = try audioCapture.start()
            PipelineLog.logger.info("Recording started")
            ipc.post(WhispItConstants.DarwinNotification.recordingStarted)
            consumerTask = Task { [weak self, detector] in
                guard let self else { return }
                for await buffer in stream {
                    self.transcription.appendAudio(buffer)
                    detector.feed(buffer)
                }
            }
        } catch {
            isRecording = false
            PipelineLog.logger.error("Audio capture failed: \(String(describing: error), privacy: .public)")
            writeError(String(describing: error))
            ipc.post(WhispItConstants.DarwinNotification.recordingFailed)
        }
    }

    private func handleStopRequested() {
        guard isRecording else { return }
        isRecording = false
        isFinalizing = true
        audioCapture.stop()
        consumerTask?.cancel()
        consumerTask = nil
        PipelineLog.logger.info("Recording stopped; finalizing")

        Task {
            await self.finalize()
            self.queue.async { self.isFinalizing = false }
        }
    }

    private func handleInterruption() {
        guard isRecording else { return }
        isRecording = false
        audioCapture.stop()
        consumerTask?.cancel()
        consumerTask = nil
        PipelineLog.logger.notice("Recording interrupted")
        writeError("Recording interrupted")
        ipc.post(WhispItConstants.DarwinNotification.recordingFailed)
    }

    private func finalize() async {
        let clock = ContinuousClock()
        let started = clock.now
        let signpostID = PipelineLog.signposter.makeSignpostID()
        let interval = PipelineLog.signposter.beginInterval("Finalize", id: signpostID)
        defer { PipelineLog.signposter.endInterval("Finalize", interval) }

        let entries = dictionary.allEntries
        let prompt = DictionaryPromptBuilder.prompt(from: entries)

        do {
            let raw = try await transcription.transcribe(prompt: prompt)
            let transcribed = clock.now

            guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                PipelineLog.logger.notice("No speech detected")
                writeError("No speech detected")
                ipc.post(WhispItConstants.DarwinNotification.recordingFailed)
                return
            }

            let cleaned: String
            var cleanupOutcome = "skipped"
            if cleanup.isAvailable {
                do {
                    cleaned = try await cleanup.clean(raw)
                    cleanupOutcome = "ok"
                } catch {
                    cleaned = raw
                    cleanupOutcome = "failed(\(String(describing: error)))"
                }
            } else {
                cleaned = raw
            }
            let cleanedAt = clock.now

            learning.observe(cleanedText: cleaned)

            try? ipc.writeText(cleaned, to: .cleanedText)

            let state = SharedState(recordingActive: false, lastInterimTranscript: "")
            try? ipc.write(state, to: .sharedState)
            ipc.post(WhispItConstants.DarwinNotification.cleanedTextReady)

            PipelineLog.logger.info("""
                Finalize done total=\(PipelineLog.milliseconds(clock.now - started))ms \
                transcribe=\(PipelineLog.milliseconds(transcribed - started))ms \
                cleanup=\(PipelineLog.milliseconds(cleanedAt - transcribed))ms \
                cleanupOutcome=\(cleanupOutcome, privacy: .public) \
                rawChars=\(raw.count) cleanedChars=\(cleaned.count)
                """)
        } catch {
            PipelineLog.logger.error("Transcription failed: \(String(describing: error), privacy: .public)")
            writeError(String(describing: error))
            ipc.post(WhispItConstants.DarwinNotification.recordingFailed)
        }
    }

    private func writeError(_ message: String) {
        let state = SharedState(
            recordingActive: false,
            lastInterimTranscript: "",
            lastError: message
        )
        try? ipc.write(state, to: .sharedState)
    }
}
