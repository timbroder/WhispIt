import AVFoundation
import Foundation

final class VoiceActivityDetector {
    var silenceThreshold: Float = 0.01
    var silenceTimeout: TimeInterval

    var onSilenceTimeout: (() -> Void)?

    private var lastVoiceTimestamp: Date?
    private var hasFired = false

    init(silenceTimeout: TimeInterval = SettingsManager.shared.silenceTimeoutSeconds) {
        self.silenceTimeout = silenceTimeout
    }

    func reset() {
        lastVoiceTimestamp = nil
        hasFired = false
    }

    func feed(_ buffer: AVAudioPCMBuffer) {
        let level = Self.rms(of: buffer)
        let now = Date()

        if level >= silenceThreshold {
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
