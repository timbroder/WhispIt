import AVFoundation
import Foundation

final class DictationPipelineCoordinator {
    static let shared = DictationPipelineCoordinator()

    private let queue = DispatchQueue(label: "com.whispit.pipeline")

    private let audioCapture = AudioCaptureService()
    private let transcription = TranscriptionService()
    private let cleanup = CleanupService()
    private let learning = DictionaryLearningService()
    private let interruption = AudioInterruptionHandler()
    private let backgroundSession = BackgroundAudioSessionManager.shared

    private var vad = VoiceActivityDetector()
    private var consumerTask: Task<Void, Never>?
    private var isRecording = false
    private var didStartObserving = false

    private init() {}

    var isModelLoaded: Bool { transcription.isModelLoaded }

    func loadWhisperModel(at folder: URL) async throws {
        try await transcription.loadModel(at: folder)
    }

    func startObserving() {
        guard !didStartObserving else { return }
        didStartObserving = true

        IPCManager.shared.observe(WhispItConstants.DarwinNotification.recordingStartRequested) { [weak self] in
            self?.queue.async { self?.handleStartRequested() }
        }
        IPCManager.shared.observe(WhispItConstants.DarwinNotification.recordingStopRequested) { [weak self] in
            self?.queue.async { self?.handleStopRequested() }
        }

        interruption.onInterruptionBegan = { [weak self] in
            self?.queue.async { self?.handleInterruption() }
        }
        interruption.onInterruptionEnded = { [weak self] _ in
            try? self?.backgroundSession.start()
        }
        interruption.start()
    }

    private func handleStartRequested() {
        guard !isRecording else { return }
        guard transcription.isModelLoaded else {
            writeError("WhisperKit model not loaded")
            return
        }

        isRecording = true
        transcription.reset()

        let detector = VoiceActivityDetector()
        detector.onSilenceTimeout = { [weak self] in
            self?.queue.async { self?.handleStopRequested() }
        }
        vad = detector

        let state = SharedState(recordingActive: true)
        try? IPCManager.shared.write(state, to: .sharedState)

        do {
            let stream = try audioCapture.start()
            consumerTask = Task { [weak self, detector] in
                guard let self else { return }
                for await buffer in stream {
                    self.transcription.appendAudio(buffer)
                    detector.feed(buffer)
                }
            }
        } catch {
            isRecording = false
            writeError(String(describing: error))
            IPCManager.shared.post(WhispItConstants.DarwinNotification.recordingFailed)
        }
    }

    private func handleStopRequested() {
        guard isRecording else { return }
        isRecording = false
        audioCapture.stop()
        consumerTask?.cancel()
        consumerTask = nil

        Task { await self.finalize() }
    }

    private func handleInterruption() {
        guard isRecording else { return }
        isRecording = false
        audioCapture.stop()
        consumerTask?.cancel()
        consumerTask = nil
        writeError("Recording interrupted")
        IPCManager.shared.post(WhispItConstants.DarwinNotification.recordingFailed)
    }

    private func finalize() async {
        let entries = DictionaryManager.shared.allEntries
        let prompt = DictionaryPromptBuilder.prompt(from: entries)

        do {
            let raw = try await transcription.transcribe(prompt: prompt)

            guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                writeError("No speech detected")
                IPCManager.shared.post(WhispItConstants.DarwinNotification.recordingFailed)
                return
            }

            let cleaned: String
            if cleanup.isAvailable {
                do {
                    cleaned = try await cleanup.clean(raw)
                } catch {
                    cleaned = raw
                }
            } else {
                cleaned = raw
            }

            learning.observe(cleanedText: cleaned)

            try? IPCManager.shared.writeText(cleaned, to: .cleanedText)

            let state = SharedState(recordingActive: false, lastInterimTranscript: "")
            try? IPCManager.shared.write(state, to: .sharedState)
            IPCManager.shared.post(WhispItConstants.DarwinNotification.cleanedTextReady)
        } catch {
            writeError(String(describing: error))
            IPCManager.shared.post(WhispItConstants.DarwinNotification.recordingFailed)
        }
    }

    private func writeError(_ message: String) {
        let state = SharedState(
            recordingActive: false,
            lastInterimTranscript: "",
            lastError: message
        )
        try? IPCManager.shared.write(state, to: .sharedState)
    }
}
