// swift-tools-version: 6.0
// Native macOS runner for the speech-engine bake-off (WhispIt-peu).
//
// The iOS simulator runs Core ML on the CPU only and can't run SpeechAnalyzer
// at all, so this package compiles the app's own engine prototypes and the
// integration tests' harness (symlinked into Sources/ASRBakeoffMac) for the
// Mac, where Core ML can use the Neural Engine and GPU. See
// docs/qa/asr-bakeoff.md for how to run it and how to read the numbers.
import Foundation
import PackageDescription

// WhisperKit ships in the Argmax Open-Source SDK since 1.0. 1.1.0+ fixes the
// empty transcripts turbo returns when a dictionary prompt is set
// (argmax-oss-swift#501), which PR #30 (WhispIt-3lu) adopts in the app.
// WHISPERKIT_0_18=1 builds against the WhisperKit 0.18 that qa/report uses.
let legacyWhisperKit = ProcessInfo.processInfo.environment["WHISPERKIT_0_18"] != nil
let whisperKit: (package: Package.Dependency, name: String) = legacyWhisperKit
    ? (.package(url: "https://github.com/argmaxinc/WhisperKit", exact: "0.18.0"), "WhisperKit")
    : (.package(url: "https://github.com/argmaxinc/argmax-oss-swift", from: "1.1.1"), "argmax-oss-swift")

let package = Package(
    name: "ASRBakeoffMac",
    platforms: [.macOS("26.0")],
    dependencies: [
        whisperKit.package,
        .package(url: "https://github.com/FluidInference/FluidAudio", .upToNextMinor(from: "0.18.4")),
    ],
    targets: [
        .executableTarget(
            name: "ASRBakeoffMac",
            dependencies: [
                .product(name: "WhisperKit", package: whisperKit.name),
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            swiftSettings: [
                // The prototypes are wrapped in `#if DEBUG`; compile them in release builds too.
                .define("DEBUG"),
                .swiftLanguageMode(.v5),
            ]
        ),
    ]
)
