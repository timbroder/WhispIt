import AVFoundation
import Foundation

/// Something that produces raw input audio buffers (the microphone in
/// production, a file in debug/test builds). `AudioCaptureService` converts
/// whatever this delivers to Whisper's 16 kHz mono format.
protocol AudioInputSource: AnyObject {
    /// Format of the buffers passed to `start`'s handler. Read right before `start`.
    var format: AVAudioFormat { get }
    func start(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws
    func stop()
}

final class MicrophoneInputSource: AudioInputSource {
    private let engine = AVAudioEngine()

    var format: AVAudioFormat { engine.inputNode.outputFormat(forBus: 0) }

    func start(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
        let inputNode = engine.inputNode
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            onBuffer(buffer)
        }
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw error
        }
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}

final class AudioCaptureService {
    enum AudioCaptureError: Error {
        case alreadyRecording
        case unsupportedInputFormat
        case engineFailedToStart(Error)
    }

    static let whisperFormat: AVAudioFormat = {
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!
    }()

    private let source: AudioInputSource
    private var converter: AVAudioConverter?
    private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private(set) var isRecording = false

    init(source: AudioInputSource? = nil) {
        self.source = source ?? Self.defaultSource()
    }

    private static func defaultSource() -> AudioInputSource {
        #if DEBUG
        if let url = DebugOverrides.audioFixtureURL,
           let fileSource = try? FileAudioInputSource(url: url) {
            PipelineLog.logger.notice("Using audio fixture \(url.lastPathComponent, privacy: .public)")
            return fileSource
        }
        #endif
        return MicrophoneInputSource()
    }

    func start() throws -> AsyncStream<AVAudioPCMBuffer> {
        guard !isRecording else { throw AudioCaptureError.alreadyRecording }

        let inputFormat = source.format

        guard let converter = AVAudioConverter(from: inputFormat, to: Self.whisperFormat) else {
            throw AudioCaptureError.unsupportedInputFormat
        }
        self.converter = converter

        let stream = AsyncStream<AVAudioPCMBuffer>(bufferingPolicy: .unbounded) { continuation in
            self.continuation = continuation
        }

        do {
            try source.start { [weak self] buffer in
                self?.process(buffer: buffer)
            }
        } catch {
            self.continuation?.finish()
            self.continuation = nil
            self.converter = nil
            throw AudioCaptureError.engineFailedToStart(error)
        }

        isRecording = true
        return stream
    }

    func stop() {
        guard isRecording else { return }
        source.stop()
        continuation?.finish()
        continuation = nil
        converter = nil
        isRecording = false
    }

    func process(buffer: AVAudioPCMBuffer) {
        guard let converter, let continuation else { return }

        let ratio = Self.whisperFormat.sampleRate / buffer.format.sampleRate
        let estimatedFrames = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(
            pcmFormat: Self.whisperFormat,
            frameCapacity: estimatedFrames
        ) else { return }

        // Report `.noDataNow` (not `.endOfStream`) once this buffer is used:
        // end-of-stream permanently finishes the converter, after which every
        // later buffer converts to nothing. The converter stays alive for the
        // whole recording so its resampler state carries across buffers.
        var sourceConsumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if sourceConsumed {
                status.pointee = .noDataNow
                return nil
            }
            sourceConsumed = true
            status.pointee = .haveData
            return buffer
        }

        guard error == nil, output.frameLength > 0 else { return }
        continuation.yield(output)
    }
}
