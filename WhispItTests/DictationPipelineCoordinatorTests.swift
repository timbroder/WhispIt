import AVFoundation
import Foundation
import Testing
@testable import WhispIt

private typealias Note = WhispItConstants.DarwinNotification

@Suite("DictationPipelineCoordinator")
struct DictationPipelineCoordinatorTests {

    // MARK: Happy path

    @Test func startWritesRecordingStateAndStartsCapture() {
        let h = PipelineHarness()
        h.requestStart()
        #expect(h.ipc.lastState?.recordingActive == true)
        #expect(h.source.isStarted)
        #expect(h.transcriber.resetCount == 1)
    }

    /// Regression (H1): the keyboard only re-reads shared state when it gets a
    /// Darwin notification. Without one it never learns recording started,
    /// so its mic button keeps sending "start" and tapping can't stop.
    @Test func startNotifiesTheKeyboard() {
        let h = PipelineHarness()
        h.requestStart()
        #expect(h.ipc.didPost(Note.recordingStarted))
        #expect(h.ipc.lastState?.recordingActive == true)
    }

    @Test func failedAudioStartDoesNotAnnounceRecording() {
        struct NoMic: Error {}
        let h = PipelineHarness()
        h.source.startError = NoMic()
        h.requestStart()
        #expect(!h.ipc.didPost(Note.recordingStarted))
    }

    @Test func startWhileRecordingReannouncesSoKeyboardCanResync() {
        let h = PipelineHarness()
        h.requestStart()
        h.requestStart()
        let announcements = h.ipc.posts.filter { $0 == Note.recordingStarted as String }
        #expect(announcements.count == 2)
        #expect(h.source.startCount == 1)
    }

    @Test func audioReachesTheTranscriber() async {
        let h = PipelineHarness()
        h.requestStart()
        for i in 0..<10 { h.source.deliver(AudioFactory.buffer(startFrame: i * 1_024)) }
        #expect(await waitUntil { h.transcriber.framesReceived > 0 })
    }

    @Test func stopProducesCleanedTextForTheKeyboard() async {
        let h = PipelineHarness()
        h.transcriber.result = .success("um so the raw text")
        h.requestStart()
        h.requestStop()
        #expect(await h.waitForResult())
        #expect(h.ipc.didPost(Note.cleanedTextReady))
        #expect(!h.ipc.didPost(Note.recordingFailed))
        #expect(h.ipc.texts == ["Cleaned: um so the raw text"])
        #expect(h.ipc.lastState?.recordingActive == false)
        #expect(h.ipc.lastState?.lastError == nil)
        #expect(h.source.stopCount == 1)
    }

    /// Regression (U4): the keyboard learns capture ended before the result.
    @Test(arguments: [false, true])
    func stopAnnouncesProcessing(bySilence: Bool) async {
        let h = PipelineHarness(silenceTimeout: bySilence ? 0.2 : 60)
        h.requestStart()
        await h.speak()
        if bySilence {
            _ = await waitUntil(timeout: .seconds(2)) {
                h.source.deliver(AudioFactory.silence())
                return h.ipc.didPost(Note.recordingStopped)
            }
        } else {
            h.requestStop()
        }
        #expect(h.ipc.didPost(Note.recordingStopped))
        let stoppedIndex = h.ipc.posts.firstIndex(of: Note.recordingStopped as String)
        #expect(await h.waitForResult())
        let resultIndex = h.ipc.posts.firstIndex(of: Note.cleanedTextReady as String)
        if let stoppedIndex, let resultIndex { #expect(stoppedIndex < resultIndex) }
    }

    @Test func dictionaryWordsArePassedAsThePrompt() async throws {
        let h = PipelineHarness()
        h.dictionary.add(word: "Kubernetes", source: .manual)
        h.requestStart()
        h.requestStop()
        #expect(await h.waitForResult())
        let prompt = try #require(h.transcriber.prompts.first ?? nil)
        #expect(prompt.contains("Kubernetes"))
    }

    @Test func cleanedTextFeedsDictionaryLearning() async {
        let h = PipelineHarness()
        h.cleaner.transform = { _ in "ping Priyanka now" }
        for _ in 0..<3 {
            h.requestStart()
            h.requestStop()
            #expect(await h.waitUntilIdleAfterResult())
        }
        #expect(h.dictionary.allEntries.map(\.word) == ["Priyanka"])
    }

    // MARK: Cleanup fallbacks

    @Test func cleanupFailureFallsBackToRawText() async {
        struct Guardrail: Error {}
        let h = PipelineHarness()
        h.transcriber.result = .success("raw words")
        h.cleaner.transform = { _ in throw Guardrail() }
        h.requestStart()
        await h.speak()
        h.requestStop()
        #expect(await h.waitForResult())
        #expect(h.ipc.texts == ["raw words"])
    }

    @Test func unavailableAppleIntelligenceInsertsRawText() async {
        let h = PipelineHarness()
        h.transcriber.result = .success("raw words")
        h.cleaner.isAvailable = false
        h.requestStart()
        await h.speak()
        h.requestStop()
        #expect(await h.waitForResult())
        #expect(h.ipc.texts == ["raw words"])
    }

    // MARK: Failure paths

    @Test(arguments: ["", "   ", "\n"])
    func emptyTranscriptReportsNoSpeech(_ transcript: String) async {
        let h = PipelineHarness()
        h.transcriber.result = .success(transcript)
        h.requestStart()
        h.requestStop()
        #expect(await h.waitForResult())
        #expect(h.ipc.didPost(Note.recordingFailed))
        #expect(h.ipc.texts.isEmpty)
        #expect(h.ipc.lastState?.lastError == "No speech detected")
    }

    /// Regression (H6): Whisper hallucinates short phrases on silent audio. If
    /// the recording never contained speech, nothing should be inserted.
    @Test func silentRecordingDoesNotInsertHallucinatedText() async {
        let h = PipelineHarness()
        h.transcriber.result = .success("Thank you.")
        h.requestStart()
        for _ in 0..<20 { h.source.deliver(AudioFactory.silence()) }
        _ = await waitUntil { h.transcriber.framesReceived > 0 }
        h.requestStop()
        #expect(await h.waitForResult())
        #expect(h.ipc.texts.isEmpty)
        #expect(h.ipc.didPost(Note.recordingFailed))
        #expect(h.ipc.lastState?.lastError == "No speech detected")
    }

    @Test func shortAnswerAfterRealSpeechIsInserted() async {
        let h = PipelineHarness()
        h.transcriber.result = .success("Yes.")
        h.cleaner.isAvailable = false
        h.requestStart()
        await h.speak()
        h.requestStop()
        #expect(await h.waitForResult())
        #expect(h.ipc.texts == ["Yes."])
    }

    /// A soft speaker may never cross the VAD threshold; real sentences from a
    /// "quiet" recording must still be inserted.
    @Test func longTranscriptFromQuietRecordingIsKept() async {
        let h = PipelineHarness()
        h.transcriber.result = .success("please call me back after lunch")
        h.cleaner.isAvailable = false
        h.requestStart()
        for _ in 0..<5 { h.source.deliver(AudioFactory.buffer(amplitude: 0.005)) }
        _ = await waitUntil { h.transcriber.framesReceived > 0 }
        h.requestStop()
        #expect(await h.waitForResult())
        #expect(h.ipc.texts == ["please call me back after lunch"])
    }

    @Test func transcriptionErrorIsReported() async {
        struct DecodeFailed: Error {}
        let h = PipelineHarness()
        h.transcriber.result = .failure(DecodeFailed())
        h.requestStart()
        h.requestStop()
        #expect(await h.waitForResult())
        #expect(h.ipc.didPost(Note.recordingFailed))
        #expect(h.ipc.lastState?.lastError?.isEmpty == false)
    }

    @Test func startWithoutModelReportsErrorAndDoesNotRecord() {
        let h = PipelineHarness()
        h.transcriber.isModelLoaded = false
        h.requestStart()
        #expect(!h.source.isStarted)
        #expect(h.ipc.lastState?.lastError?.contains("Open WhispIt") == true)
    }

    /// Regression (H4): the keyboard must hear about the failure.
    @Test func startWithoutModelTellsTheKeyboard() {
        let h = PipelineHarness()
        h.transcriber.isModelLoaded = false
        h.requestStart()
        #expect(h.ipc.didPost(Note.recordingFailed))
        #expect(!h.ipc.didPost(Note.recordingStarted))
    }

    @Test func audioStartFailureReportsAndAllowsRetry() {
        struct NoMic: Error {}
        let h = PipelineHarness()
        h.source.startError = NoMic()
        h.requestStart()
        #expect(h.ipc.didPost(Note.recordingFailed))
        #expect(h.ipc.lastState?.recordingActive == false)
        h.source.startError = nil
        h.requestStart()
        #expect(h.source.isStarted)
    }

    // MARK: State machine

    @Test func secondStartWhileRecordingIsIgnored() {
        let h = PipelineHarness()
        h.requestStart()
        h.requestStart()
        #expect(h.source.startCount == 1)
    }

    @Test func stopWithoutStartDoesNothing() {
        let h = PipelineHarness()
        h.requestStop()
        #expect(h.ipc.posts.isEmpty)
        #expect(h.ipc.states.isEmpty)
    }

    @Test func startWhileFinalizingIsIgnored() async {
        let h = PipelineHarness()
        let gate = AsyncGate()
        h.cleaner.transform = { raw in gate.waitBlocking(); return raw }
        h.requestStart()
        h.requestStop()
        _ = await waitUntil { h.transcriber.prompts.count == 1 }
        h.requestStart()
        #expect(h.source.startCount == 1)
        gate.open()
        #expect(await h.waitForResult())
    }

    @Test func canDictateAgainAfterFinishing() async {
        let h = PipelineHarness()
        h.requestStart()
        h.requestStop()
        #expect(await h.waitUntilIdleAfterResult())
        h.requestStart()
        #expect(h.source.startCount == 2)
    }

    @Test func silenceTimeoutStopsRecording() async {
        let h = PipelineHarness(silenceTimeout: 0.2)
        h.requestStart()
        h.source.deliver(AudioFactory.buffer())
        // Like a real mic, keep delivering (silent) buffers until the VAD fires.
        // Regression (H2): the VAD only sees converted audio.
        let stopped = await waitUntil(timeout: .seconds(2)) {
            h.source.deliver(AudioFactory.silence())
            return h.ipc.didPost(Note.cleanedTextReady)
        }
        #expect(stopped)
    }

    // MARK: Interruptions

    @Test func interruptionStopsRecordingAndReportsFailure() async {
        let h = PipelineHarness()
        h.requestStart()
        h.interruption.onInterruptionBegan?()
        h.coordinator.drainQueue()
        #expect(h.ipc.didPost(Note.recordingFailed))
        #expect(h.ipc.lastState?.lastError == "Recording interrupted")
        #expect(h.source.stopCount == 1)
    }

    @Test func headphonesUnpluggedStopsRecording() {
        let h = PipelineHarness()
        h.requestStart()
        h.interruption.onRouteChanged?(.oldDeviceUnavailable)
        h.coordinator.drainQueue()
        #expect(h.ipc.didPost(Note.recordingFailed))
    }

    @Test func otherRouteChangesKeepRecording() {
        let h = PipelineHarness()
        h.requestStart()
        h.interruption.onRouteChanged?(.newDeviceAvailable)
        h.coordinator.drainQueue()
        #expect(!h.ipc.didPost(Note.recordingFailed))
        #expect(h.source.isStarted)
    }

    @Test func interruptionEndRestartsKeepAliveSession() {
        let h = PipelineHarness()
        h.interruption.onInterruptionEnded?(true)
        #expect(h.keepAlive.startCount == 1)
    }
}

extension PipelineHarness {
    /// Waits for a result and for the coordinator to leave the finalizing state.
    func waitUntilIdleAfterResult() async -> Bool {
        let before = ipc.posts.filter {
            $0 == Note.cleanedTextReady as String || $0 == Note.recordingFailed as String
        }.count
        let gotResult = await waitUntil(timeout: .seconds(3)) {
            ipc.posts.filter {
                $0 == Note.cleanedTextReady as String || $0 == Note.recordingFailed as String
            }.count > before
        }
        // isFinalizing is cleared on the queue right after the post.
        try? await Task.sleep(for: .milliseconds(50))
        coordinator.drainQueue()
        return gotResult
    }
}

/// A one-shot gate a synchronous closure can block on.
final class AsyncGate: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    func waitBlocking() { _ = semaphore.wait(timeout: .now() + 5) }
    func open() { semaphore.signal() }
}
