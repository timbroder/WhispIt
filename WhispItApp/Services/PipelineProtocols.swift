import AVFoundation
import Foundation

/// Seams between `DictationPipelineCoordinator` and the heavyweight services
/// it drives, so the coordinator's state machine can be tested with stubs.

protocol Transcribing: AnyObject {
    var isModelLoaded: Bool { get }
    func loadModel(at folder: URL) async throws
    func reset()
    func appendAudio(_ buffer: AVAudioPCMBuffer)
    func transcribe(prompt: String?) async throws -> String
}

protocol TextCleaning: AnyObject {
    var isAvailable: Bool { get }
    func clean(_ raw: String) async throws -> String
}

protocol KeepAliveSession: AnyObject {
    func start() throws
}

extension TranscriptionService: Transcribing {}
extension CleanupService: TextCleaning {}
extension BackgroundAudioSessionManager: KeepAliveSession {}
