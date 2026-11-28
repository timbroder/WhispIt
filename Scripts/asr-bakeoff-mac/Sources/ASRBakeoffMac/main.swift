import AVFoundation
import Foundation
import WhisperKit

// Native macOS runner for the speech-engine bake-off (WhispIt-peu).
//
//     cd Scripts/asr-bakeoff-mac
//     swift run -c release ASRBakeoffMac <engine>
//
// Run one engine per process so memory numbers stay separate. Prints the
// same `BAKEOFF_RESULT {json}` line as WhispItIntegrationTests/Bakeoff.
//
// Models: WhisperKit variants go to ~/Library/Caches/WhispItBakeoff;
// FluidAudio keeps Parakeet in ~/Library/Application Support/FluidAudio;
// SpeechAnalyzer uses the system's dictation assets.

let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent() // ASRBakeoffMac
    .deletingLastPathComponent() // Sources
    .deletingLastPathComponent() // asr-bakeoff-mac
    .deletingLastPathComponent() // Scripts
    .deletingLastPathComponent()
let fixtures = repoRoot.appending(path: "WhispItIntegrationTests/Fixtures")

let whisperCache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    .appending(path: "WhispItBakeoff")

func whisper(_ variant: String) -> EngineUnderTest {
    .whisper(variant: variant) {
        try FileManager.default.createDirectory(at: whisperCache, withIntermediateDirectories: true)
        return try await WhisperKit.download(variant: variant, downloadBase: whisperCache, useBackgroundSession: false)
    }
}

let engines: [String: () -> EngineUnderTest] = [
    "whisper-turbo-632": { whisper("openai_whisper-large-v3-v20240930_turbo_632MB") },
    "whisper-turbo": { whisper("openai_whisper-large-v3-v20240930_turbo") },
    "whisper-base": { whisper("openai_whisper-base.en") },
    "speech-analyzer": { .speechAnalyzer(mode: .streaming) },
    "speech-analyzer-batch": { .speechAnalyzer(mode: .batch) },
    "parakeet-v2": { .parakeet(.v2) },
    "parakeet-v2-recall": { .parakeet(.v2, boosting: .recall) },
    "parakeet-v3": { .parakeet(.v3) },
]

/// Loads a fixture WAV as 16 kHz mono float, the pipeline's format.
func loadFixture(_ name: String) throws -> AVAudioPCMBuffer {
    let file = try AVAudioFile(forReading: fixtures.appending(path: "\(name).wav"))
    let target = AudioCaptureService.whisperFormat
    guard let source = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
          let converter = AVAudioConverter(from: file.processingFormat, to: target) else {
        throw CocoaError(.fileReadCorruptFile)
    }
    try file.read(into: source)
    let capacity = AVAudioFrameCount(Double(source.frameLength) * target.sampleRate / file.processingFormat.sampleRate) + 4_096
    guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
        throw CocoaError(.fileReadCorruptFile)
    }
    var consumed = false
    var error: NSError?
    _ = converter.convert(to: output, error: &error) { _, status in
        if consumed { status.pointee = .endOfStream; return nil }
        consumed = true
        status.pointee = .haveData
        return source
    }
    if let error { throw error }
    return output
}

let arguments = CommandLine.arguments.dropFirst()
guard let name = arguments.first, let make = engines[name] else {
    print("usage: ASRBakeoffMac <\(engines.keys.sorted().joined(separator: "|"))>")
    exit(2)
}

do {
    let result = try await BakeoffRunner.run(make(), audio: loadFixture)
    print("overall WER \(result.overallWER), proper nouns \(result.properNounsPlain)/3 → \(result.properNounsBiased)/3")
} catch {
    print("BAKEOFF_ERROR \(name): \(error)")
    exit(1)
}
