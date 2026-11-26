import AVFoundation
import Foundation
@testable import WhispIt

/// A unique temporary directory, removed when the value is deinitialized.
final class TemporaryDirectory {
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory
            .appending(path: "WhispItTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func file(_ name: String) -> URL { url.appending(path: name) }

    deinit { try? FileManager.default.removeItem(at: url) }
}

/// An isolated `UserDefaults` suite, removed when deinitialized.
final class IsolatedDefaults {
    let suiteName = "WhispItTests-\(UUID().uuidString)"
    let defaults: UserDefaults

    init() { defaults = UserDefaults(suiteName: suiteName)! }

    deinit { defaults.removePersistentDomain(forName: suiteName) }
}

enum AudioFactory {
    /// A non-interleaved Float32 buffer filled with a sine wave (or silence
    /// when `amplitude` is 0).
    static func buffer(
        sampleRate: Double = 48_000,
        channels: AVAudioChannelCount = 2,
        frames: AVAudioFrameCount = 1_024,
        amplitude: Float = 0.5,
        frequency: Double = 440,
        startFrame: Int = 0
    ) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: false
        )!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for channel in 0..<Int(channels) {
            let data = buffer.floatChannelData![channel]
            for i in 0..<Int(frames) {
                let t = Double(startFrame + i) / sampleRate
                data[i] = amplitude * Float(sin(2 * .pi * frequency * t))
            }
        }
        return buffer
    }

    static func silence(
        sampleRate: Double = 48_000,
        channels: AVAudioChannelCount = 2,
        frames: AVAudioFrameCount = 1_024
    ) -> AVAudioPCMBuffer {
        buffer(sampleRate: sampleRate, channels: channels, frames: frames, amplitude: 0)
    }
}

/// Polls `condition` until it is true or `timeout` elapses.
func waitUntil(
    timeout: Duration = .seconds(2),
    _ condition: () -> Bool
) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}
