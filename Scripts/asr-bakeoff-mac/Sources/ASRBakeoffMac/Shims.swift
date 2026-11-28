import AVFoundation
import Foundation

// Stand-ins for the iOS app types the symlinked engine sources refer to.
// Keep them identical in shape to the originals.

/// WhispItApp/Services/PipelineProtocols.swift
protocol Transcribing: AnyObject {
    var isModelLoaded: Bool { get }
    func loadModel(at folder: URL) async throws
    func reset()
    func appendAudio(_ buffer: AVAudioPCMBuffer)
    func transcribe(prompt: String?) async throws -> String
}

extension TranscriptionService: Transcribing {}

/// WhispItApp/Services/AudioCaptureService.swift: the pipeline's audio format.
enum AudioCaptureService {
    static let whisperFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false
    )!
}

/// WhispItApp/Services/Debug/ASREngine.swift: the app reads the user's
/// dictionary here; the runner sets words per run instead.
enum DictionaryVocabulary {
    static func current() -> [String] { [] }
}
