import AVFoundation
import Foundation

final class VoiceActivityDetector {
    var silenceThreshold: Float = 0.01
    var silenceTimeout: TimeInterval

    var onSilenceTimeout: (() -> Void)?

    private var lastVoiceTimestamp: Date?
    private var hasFired = false
    private let voiceLock = NSLock()
    private var _heardVoice = false

    /// Whether any buffer since the last reset was loud enough to be speech.
    /// Read from the pipeline queue while `feed` runs on the capture task.
    var heardVoice: Bool { voiceLock.withLock { _heardVoice } }
    private let now: () -> Date

    init(
        silenceTimeout: TimeInterval = SettingsManager.shared.silenceTimeoutSeconds,
        now: @escaping () -> Date = Date.init
    ) {
        self.silenceTimeout = silenceTimeout
        self.now = now
    }

    func reset() {
        lastVoiceTimestamp = nil
        hasFired = false
        voiceLock.withLock { _heardVoice = false }
    }

    func feed(_ buffer: AVAudioPCMBuffer) {
        let level = Self.rms(of: buffer)
        let now = now()

        if level >= silenceThreshold {
            voiceLock.withLock { _heardVoice = true }
            lastVoiceTimestamp = now
            hasFired = false
            return
        }

        guard !hasFired else { return }

        if let last = lastVoiceTimestamp {
            if now.timeIntervalSince(last) >= silenceTimeout {
                hasFired = true
                onSilenceTimeout?()
            }
        } else {
            lastVoiceTimestamp = now
        }
    }

    static func rms(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }

        var sumOfSquares: Float = 0
        for i in 0..<frameLength {
            let sample = channelData[i]
            sumOfSquares += sample * sample
        }
        return sqrtf(sumOfSquares / Float(frameLength))
    }
}
