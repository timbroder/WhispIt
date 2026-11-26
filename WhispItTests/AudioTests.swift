import AVFoundation
import Foundation
import Testing
@testable import WhispIt

@Suite("VoiceActivityDetector")
struct VoiceActivityDetectorTests {
    /// A clock the test advances by hand.
    final class FakeClock: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 1_000)
        func advance(_ seconds: TimeInterval) { now += seconds }
    }

    let clock = FakeClock()
    let speech = AudioFactory.buffer(channels: 1, amplitude: 0.5)
    let quiet = AudioFactory.silence(channels: 1)

    func makeDetector(timeout: TimeInterval = 2) -> (VoiceActivityDetector, () -> Int) {
        let detector = VoiceActivityDetector(silenceTimeout: timeout, now: { [clock] in clock.now })
        var fired = 0
        detector.onSilenceTimeout = { fired += 1 }
        return (detector, { fired })
    }

    @Test func rmsOfSineIsAmplitudeOverRootTwo() {
        let rms = VoiceActivityDetector.rms(of: AudioFactory.buffer(channels: 1, frames: 48_000, amplitude: 0.5))
        #expect(abs(rms - 0.5 / sqrt(2)) < 0.001)
        #expect(VoiceActivityDetector.rms(of: quiet) == 0)
    }

    @Test func firesAfterSilenceFollowingSpeech() {
        let (detector, fired) = makeDetector()
        detector.feed(speech)
        clock.advance(1.9)
        detector.feed(quiet)
        #expect(fired() == 0)
        clock.advance(0.2)
        detector.feed(quiet)
        #expect(fired() == 1)
    }

    @Test func firesOnlyOncePerSilence() {
        let (detector, fired) = makeDetector()
        detector.feed(speech)
        for _ in 0..<10 {
            clock.advance(1)
            detector.feed(quiet)
        }
        #expect(fired() == 1)
    }

    @Test func speechReArmsTheDetector() {
        let (detector, fired) = makeDetector()
        detector.feed(speech)
        clock.advance(3)
        detector.feed(quiet)
        detector.feed(speech)
        clock.advance(3)
        detector.feed(quiet)
        #expect(fired() == 2)
    }

    @Test func pureSilenceFiresTimeoutAfterFirstBuffer() {
        let (detector, fired) = makeDetector()
        detector.feed(quiet)
        clock.advance(2.5)
        detector.feed(quiet)
        #expect(fired() == 1)
    }

    @Test func intermittentSpeechKeepsRecording() {
        let (detector, fired) = makeDetector()
        for _ in 0..<20 {
            detector.feed(speech)
            clock.advance(1.5)
            detector.feed(quiet)
        }
        #expect(fired() == 0)
    }
}

@Suite("AudioCaptureService conversion")
struct AudioCaptureConversionTests {
    /// Starts capture on a stub source, delivers `buffers`, stops, and returns
    /// every converted 16 kHz buffer the stream produced.
    func convert(_ buffers: [AVAudioPCMBuffer], source: StubAudioSource) async throws -> [AVAudioPCMBuffer] {
        let service = AudioCaptureService(source: source)
        let stream = try service.start()
        for buffer in buffers { source.deliver(buffer) }
        service.stop()
        var output: [AVAudioPCMBuffer] = []
        for await buffer in stream { output.append(buffer) }
        return output
    }

    func micBuffers(count: Int, sampleRate: Double = 48_000, channels: AVAudioChannelCount = 2) -> [AVAudioPCMBuffer] {
        (0..<count).map {
            AudioFactory.buffer(sampleRate: sampleRate, channels: channels, frames: 1_024, startFrame: $0 * 1_024)
        }
    }

    @Test func outputIsWhisperFormat() async throws {
        let output = try await convert(micBuffers(count: 3), source: StubAudioSource())
        let first = try #require(output.first)
        #expect(first.format.sampleRate == 16_000)
        #expect(first.format.channelCount == 1)
        #expect(first.format.commonFormat == .pcmFormatFloat32)
    }

    /// Regression (H2): every input buffer must keep producing audio. 100 × 1024 frames at
    /// 48 kHz is ~2.13 s, which should yield ~34,133 frames at 16 kHz.
    @Test(arguments: [(48_000.0, AVAudioChannelCount(2)), (44_100.0, AVAudioChannelCount(1))])
    func longRecordingsKeepEveryBuffer(sampleRate: Double, channels: AVAudioChannelCount) async throws {
        let source = StubAudioSource(sampleRate: sampleRate, channels: channels)
        let output = try await convert(micBuffers(count: 100, sampleRate: sampleRate, channels: channels), source: source)
        let produced = output.reduce(0) { $0 + Int($1.frameLength) }
        let expected = Int(Double(100 * 1_024) * 16_000 / sampleRate)
        #expect(abs(produced - expected) < expected / 20, "produced \(produced) of ~\(expected) frames")
    }

    @Test func convertedAudioKeepsItsEnergy() async throws {
        let output = try await convert(micBuffers(count: 50), source: StubAudioSource())
        let levels = output.map(VoiceActivityDetector.rms(of:))
        let quietBuffers = levels.filter { $0 < 0.01 }.count
        #expect(output.count >= 45, "got \(output.count) buffers")
        #expect(quietBuffers == 0)
    }

    @Test func startTwiceThrows() throws {
        let service = AudioCaptureService(source: StubAudioSource())
        _ = try service.start()
        #expect(throws: AudioCaptureService.AudioCaptureError.self) { _ = try service.start() }
        service.stop()
    }

    @Test func sourceStartFailureIsReportedAndResets() throws {
        struct Boom: Error {}
        let source = StubAudioSource()
        source.startError = Boom()
        let service = AudioCaptureService(source: source)
        #expect(throws: AudioCaptureService.AudioCaptureError.self) { _ = try service.start() }
        #expect(!service.isRecording)
        source.startError = nil
        _ = try service.start()
        #expect(service.isRecording)
        service.stop()
    }

    @Test func stopIsIdempotentAndStopsSource() throws {
        let source = StubAudioSource()
        let service = AudioCaptureService(source: source)
        _ = try service.start()
        service.stop()
        service.stop()
        #expect(source.stopCount == 1)
        #expect(!service.isRecording)
    }
}
