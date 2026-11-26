#if DEBUG
import Foundation

/// Launch-argument hooks for tests and simulator QA. Compiled out of Release.
///
///     -WhispItAudioFixture <name|path>   feed a WAV file instead of the mic
///     -WhispItModelVariant <variant>     download a smaller WhisperKit model
///     -WhispItResetState                 wipe onboarding, dictionary and shared files
///
/// Fixture names resolve to `<App Group>/Fixtures/<name>.wav`; absolute paths
/// are used as-is.
enum DebugOverrides {
    private static let defaults = UserDefaults.standard

    static var audioFixtureURL: URL? {
        guard let value = defaults.string(forKey: "WhispItAudioFixture"), !value.isEmpty else {
            return nil
        }
        let candidates: [URL?] = [
            value.hasPrefix("/") ? URL(fileURLWithPath: value) : nil,
            WhispItConstants.sharedContainerURL?
                .appending(path: "Fixtures")
                .appending(path: value.hasSuffix(".wav") ? value : "\(value).wav"),
        ]
        return candidates.compactMap { $0 }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static var modelVariant: String? {
        defaults.string(forKey: "WhispItModelVariant")
    }

    static var shouldResetState: Bool {
        ProcessInfo.processInfo.arguments.contains("-WhispItResetState")
    }

    /// Clears user state but keeps any downloaded model, so UI tests can start
    /// from a fresh install without re-downloading hundreds of MB.
    static func resetStateIfRequested() {
        guard shouldResetState else { return }
        defaults.removeObject(forKey: AppLifecycle.onboardingDoneKey)
        if let group = UserDefaults(suiteName: WhispItConstants.appGroupID) {
            group.removeObject(forKey: SettingsManager.Key.silenceTimeoutSeconds.rawValue)
            group.removeObject(forKey: DictionaryLearningService.candidatesDefaultsKey)
        }
        for file in [WhispItConstants.SharedFile.dictionary, .sharedState, .cleanedText] {
            if let url = WhispItConstants.sharedFileURL(file) {
                try? FileManager.default.removeItem(at: url)
            }
        }
        DictionaryManager.shared.reload()
    }
}
#endif
