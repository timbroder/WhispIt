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
            options.promptTokens = tokenizer
                .encode(text: " " + prompt.trimmingCharacters(in: .whitespaces))
                .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
            // WhisperKit's first-token log-prob check rejects every prompted
            // decode (the first token after a prompt naturally scores low), so
            // any dictation with dictionary words came back empty. The average
            // log-prob and no-speech checks still guard against hallucinations.
            options.firstTokenLogProbThreshold = nil
        }

        let results = try await whisperKit.transcribe(audioArray: snapshot, decodeOptions: options)
        return Self.removingNonSpeechMarkers(results.map(\.text).joined(separator: " "))
    }

    private static let parenthesized = try! NSRegularExpression(pattern: #"\(([^)]*)\)"#)

    private static let nonSpeechWords: [String] = [
        "blank_audio", "blank audio", "silence", "music", "applause", "laughter",
        "laughs", "inaudible", "noise", "no speech",
    ]

    /// Strips the annotations Whisper emits for non-speech audio, such as
    /// "[BLANK_AUDIO]", "[ Silence ]" or "(music)", and tidies whitespace.
    /// Square-bracket spans are always annotations in dictation; parentheses
    /// are removed only when they contain a known non-speech word.
    static func removingNonSpeechMarkers(_ text: String) -> String {
        var result = text.replacingOccurrences(of: #"\[[^\]]*\]"#, with: " ", options: .regularExpression)
        let whole = NSRange(result.startIndex..., in: result)
        // Back to front so earlier ranges stay valid while replacing.
        for match in parenthesized.matches(in: result, range: whole).reversed() {
            guard let inner = Range(match.range(at: 1), in: result),
                  let full = Range(match.range, in: result) else { continue }
            let content = result[inner].lowercased()
            if nonSpeechWords.contains(where: { content.contains($0) }) {
                result.replaceSubrange(full, with: " ")
            }
        }
        return result
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
