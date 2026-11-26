#if DEBUG
import AVFoundation
import Foundation

/// Debug/test stand-in for the microphone. Plays an audio file into the
/// capture pipeline in microphone-shaped buffers (48 kHz stereo Float32,
/// 100 ms each), then keeps delivering silence the way a quiet room would,
/// so voice-activity detection and the real converter path are exercised.
final class FileAudioInputSource: AudioInputSource {
    static let micFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 48_000,
        channels: 2,
        interleaved: false
    )!

    enum FileSourceError: Error {
        case unreadable
        case conversionFailed
    }

    let format: AVAudioFormat = FileAudioInputSource.micFormat

    private let audio: AVAudioPCMBuffer
    private let chunkFrames: AVAudioFrameCount = 4_800
    private let realTime: Bool
    private let maxTrailingSilence: TimeInterval
    private let queue = DispatchQueue(label: "com.whispit.file-audio")
    private var timer: DispatchSourceTimer?
    private var position: AVAudioFramePosition = 0
    private var silenceFramesSent: AVAudioFramePosition = 0
    private var onBuffer: ((AVAudioPCMBuffer) -> Void)?

    /// - Parameters:
    ///   - realTime: deliver at wall-clock pace (needed for VAD). When false,
    ///     the file is delivered as fast as possible, followed by no silence.
    ///   - maxTrailingSilence: stop delivering silence after this long.
    init(url: URL, realTime: Bool = true, maxTrailingSilence: TimeInterval = 30) throws {
        self.realTime = realTime
        self.maxTrailingSilence = maxTrailingSilence
        self.audio = try Self.load(url: url, as: Self.micFormat)
    }

    /// Total length of the file audio, in seconds.
    var duration: TimeInterval {
        Double(audio.frameLength) / format.sampleRate
    }

    func start(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
        queue.sync {
            self.onBuffer = onBuffer
            self.position = 0
            self.silenceFramesSent = 0
        }

        if !realTime {
            queue.async { [weak self] in
                guard let self else { return }
                while let chunk = self.nextFileChunk() {
                    self.onBuffer?(chunk)
                }
            }
            return
        }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        let interval = Double(chunkFrames) / format.sampleRate
        timer.schedule(deadline: .now(), repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        queue.sync {
            timer?.cancel()
            timer = nil
            onBuffer = nil
        }
    }

    private func tick() {
        if let chunk = nextFileChunk() {
            onBuffer?(chunk)
            return
        }
        let maxSilenceFrames = AVAudioFramePosition(maxTrailingSilence * format.sampleRate)
        guard silenceFramesSent < maxSilenceFrames,
              let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else {
            return
        }
        silence.frameLength = chunkFrames // zero-filled on allocation
        silenceFramesSent += AVAudioFramePosition(chunkFrames)
        onBuffer?(silence)
    }

    private func nextFileChunk() -> AVAudioPCMBuffer? {
        let remaining = AVAudioFramePosition(audio.frameLength) - position
        guard remaining > 0 else { return nil }
        let count = AVAudioFrameCount(min(AVAudioFramePosition(chunkFrames), remaining))
        guard let chunk = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count),
              let src = audio.floatChannelData,
              let dst = chunk.floatChannelData else { return nil }
        for channel in 0..<Int(format.channelCount) {
            dst[channel].update(from: src[channel].advanced(by: Int(position)), count: Int(count))
        }
        chunk.frameLength = count
        position += AVAudioFramePosition(count)
        return chunk
    }

    /// Reads the whole file and converts it to `format` in one pass.
    static func load(url: URL, as format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let file = try AVAudioFile(forReading: url)
        let fileFormat = file.processingFormat
        guard let fileBuffer = AVAudioPCMBuffer(
            pcmFormat: fileFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        ) else { throw FileSourceError.unreadable }
        try file.read(into: fileBuffer)

        guard let converter = AVAudioConverter(from: fileFormat, to: format) else {
            throw FileSourceError.conversionFailed
        }
        let ratio = format.sampleRate / fileFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(fileBuffer.frameLength) * ratio) + 4_096
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw FileSourceError.conversionFailed
        }

        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .endOfStream
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return fileBuffer
        }
        if let error { throw error }
        guard status != .error else { throw FileSourceError.conversionFailed }
        return output
    }
}
#endif
