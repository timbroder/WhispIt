import AVFoundation
import Foundation

final class BackgroundAudioSessionManager {
    static let shared = BackgroundAudioSessionManager()

    enum BackgroundAudioError: Error {
        case audioFormatUnavailable
        case engineFailedToStart(Error)
    }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private(set) var isActive = false

    private init() {}

    func start() throws {
        guard !isActive else { return }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.mixWithOthers, .allowBluetooth, .defaultToSpeaker]
        )
        try session.setActive(true, options: [])

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 44_100,
            channels: 1,
            interleaved: false
        ) else {
            throw BackgroundAudioError.audioFormatUnavailable
        }

        let frameCount: AVAudioFrameCount = 44_100
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw BackgroundAudioError.audioFormatUnavailable
        }
        buffer.frameLength = frameCount

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
        } catch {
            throw BackgroundAudioError.engineFailedToStart(error)
        }

        player.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
        player.volume = 0
        player.play()

        isActive = true
    }

    func stop() {
        guard isActive else { return }
        player.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        isActive = false
    }
}
