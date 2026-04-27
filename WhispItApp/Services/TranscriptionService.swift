import AVFoundation
import Foundation
import WhisperKit

final class TranscriptionService {
    enum TranscriptionError: Error {
        case modelNotLoaded
    }

    private var whisperKit: WhisperKit?
    private var samples: [Float] = []
    private let samplesLock = NSLock()
    private(set) var isModelLoaded = false

    func loadModel(at folder: URL) async throws {
        let config = WhisperKitConfig(
            modelFolder: folder.path,
            load: true,
            download: false
        )
        whisperKit = try await WhisperKit(config)
        isModelLoaded = true
    }

    func reset() {
        samplesLock.lock()
        samples.removeAll()
        samplesLock.unlock()
    }

    func appendAudio(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        let chunk = Array(UnsafeBufferPointer(start: channelData, count: frameLength))
        samplesLock.lock()
        samples.append(contentsOf: chunk)
        samplesLock.unlock()
    }

    private func snapshotSamples() -> [Float] {
        samplesLock.lock()
        defer { samplesLock.unlock() }
        return samples
    }

    func transcribe(prompt: String? = nil) async throws -> String {
        guard let whisperKit else { throw TranscriptionError.modelNotLoaded }

        let snapshot = snapshotSamples()
        guard !snapshot.isEmpty else { return "" }

        var options = DecodingOptions()
        if let prompt, !prompt.isEmpty, let tokenizer = whisperKit.tokenizer {
            options.promptTokens = tokenizer.encode(text: prompt)
        }

        let results = try await whisperKit.transcribe(audioArray: snapshot, decodeOptions: options)
        return results
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
