import AVFoundation
import Foundation
import Testing
@testable import WhispIt

private typealias Note = WhispItConstants.DarwinNotification

/// The real pipeline end to end: a fixture plays through the real converter
/// at real-time pace, WhisperKit transcribes, Foundation Models cleans, and
/// the result is published for the keyboard. Only the IPC transport is fake.
@Suite("Dictation pipeline end to end", .serialized, .timeLimit(.minutes(15)))
struct PipelineIntegrationTests {
    struct Run {
        let ipc = CapturingIPC()
        let coordinator: DictationPipelineCoordinator
        let source: FileAudioInputSource
        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)

        init(_ fixture: Fixture, silenceTimeout: TimeInterval = 2) async throws {
            source = try FileAudioInputSource(url: fixture.url, realTime: true, maxTrailingSilence: 15)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let dictionary = DictionaryManager(fileURL: tempDir.appending(path: "dictionary.json"))
            coordinator = DictationPipelineCoordinator(
                audioCapture: AudioCaptureService(source: source),
                transcription: try await ModelStore.shared.loadedTranscriber(),
                cleanup: CleanupService(),
                dictionary: dictionary,
                learning: DictionaryLearningService(dictionary: dictionary, defaults: UserDefaults(suiteName: UUID().uuidString)),
                ipc: ipc,
                makeDetector: { VoiceActivityDetector(silenceTimeout: silenceTimeout) }
            )
            coordinator.startObserving()
        }

        func start() {
            ipc.simulate(Note.recordingStartRequested)
            coordinator.drainQueue()
        }

        func stop() {
            ipc.simulate(Note.recordingStopRequested)
            coordinator.drainQueue()
        }

        func waitForResult(timeout: Duration = .seconds(90)) async -> Bool {
            await waitUntil(timeout: timeout) {
                ipc.didPost(Note.cleanedTextReady) || ipc.didPost(Note.recordingFailed)
            }
        }
    }

    @Test func silenceAutoStopDeliversCleanedText() async throws {
        let run = try await Run(.fillers)
        let clock = ContinuousClock()
        let started = clock.now
        run.start()
        #expect(run.ipc.didPost(Note.recordingStarted))
        #expect(await run.waitForResult())
        let elapsed = clock.now - started
        let text = try #require(run.ipc.texts.last, "no text; posts: \(run.ipc.posts)")
        print("[pipeline fillers] \(elapsed) → \(text)")
        #expect(run.ipc.didPost(Note.cleanedTextReady))
        #expect(Transcript.contains(text, "friday"))
        if appleIntelligenceAvailable {
            #expect(!Transcript.contains(text, "um"))
        }
        #expect(run.ipc.lastState?.recordingActive == false)
    }

    @Test func manualStopMidSentenceStillTranscribes() async throws {
        let run = try await Run(.longPassage, silenceTimeout: 30)
        run.start()
        try await Task.sleep(for: .seconds(6))
        let stopClock = ContinuousClock()
        let stopped = stopClock.now
        run.stop()
        #expect(await run.waitForResult())
        let latency = stopClock.now - stopped
        let text = try #require(run.ipc.texts.last)
        print("[pipeline manual stop] stop→result \(latency) → \(text)")
        #expect(Transcript.contains(text, "morning") || Transcript.contains(text, "update"))
        #expect(!Transcript.contains(text, "thursday"), "should only contain the first ~6 s")
    }

    @Test func pauseLongerThanTimeoutEndsTheRecording() async throws {
        let run = try await Run(.pause, silenceTimeout: 2)
        run.start()
        #expect(await run.waitForResult())
        let text = try #require(run.ipc.texts.last)
        print("[pipeline pause 2s] \(text)")
        #expect(Transcript.contains(text, "first"))
        #expect(!Transcript.contains(text, "after"))
    }

    @Test func longerTimeoutKeepsRecordingThroughThePause() async throws {
        let run = try await Run(.pause, silenceTimeout: 5)
        run.start()
        #expect(await run.waitForResult())
        let text = try #require(run.ipc.texts.last)
        print("[pipeline pause 5s] \(text)")
        #expect(Transcript.contains(text, "first"))
        #expect(Transcript.contains(text, "after"))
    }

    /// Regression (H6) with the real model: a silent recording inserts nothing.
    @Test func silentRecordingInsertsNothing() async throws {
        let run = try await Run(.silence, silenceTimeout: 2)
        run.start()
        #expect(await run.waitForResult())
        print("[pipeline silence] posts=\(run.ipc.posts) texts=\(run.ipc.texts)")
        #expect(run.ipc.texts.isEmpty, "inserted: \(run.ipc.texts)")
        #expect(run.ipc.didPost(Note.recordingFailed))
    }
}
