import AVFoundation
import Foundation

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

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private(set) var isRecording = false

    func start() throws -> AsyncStream<AVAudioPCMBuffer> {
        guard !isRecording else { throw AudioCaptureError.alreadyRecording }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard let converter = AVAudioConverter(from: inputFormat, to: Self.whisperFormat) else {
            throw AudioCaptureError.unsupportedInputFormat
        }
        self.converter = converter

        let stream = AsyncStream<AVAudioPCMBuffer>(bufferingPolicy: .unbounded) { continuation in
            self.continuation = continuation
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer: buffer)
        }

        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
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
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation?.finish()
        continuation = nil
        converter = nil
        isRecording = false
    }

    private func process(buffer: AVAudioPCMBuffer) {
        guard let converter, let continuation else { return }

        let ratio = Self.whisperFormat.sampleRate / buffer.format.sampleRate
        let estimatedFrames = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(
            pcmFormat: Self.whisperFormat,
            frameCapacity: estimatedFrames
        ) else { return }

        var sourceConsumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if sourceConsumed {
                status.pointee = .endOfStream
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
