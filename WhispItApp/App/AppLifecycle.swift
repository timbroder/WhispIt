import AVFoundation
import FoundationModels
import Foundation
import SwiftUI

@MainActor
final class AppLifecycle: ObservableObject {
    enum BootstrapState: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    @Published var hasCompletedOnboarding: Bool
    @Published var bootstrap: BootstrapState = .idle
    @Published var modelDownloadProgress: Double = 0
    @Published var isDownloadingModel: Bool = false
    @Published var microphoneAuthorized: Bool
    /// The user said no; the system won't prompt again, only Settings can fix it.
    @Published var microphoneDenied: Bool

    nonisolated static let onboardingDoneKey = "WhispIt.hasCompletedOnboarding"

    private let modelDownload = ModelDownloadService()
    private let coordinator: DictationPipelineCoordinator
    private let backgroundAudio: KeepAliveSession

    init(
        coordinator: DictationPipelineCoordinator = .shared,
        backgroundAudio: KeepAliveSession = BackgroundAudioSessionManager.shared
    ) {
        self.coordinator = coordinator
        self.backgroundAudio = backgroundAudio
        #if DEBUG
        DebugOverrides.resetStateIfRequested()
        #endif
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Self.onboardingDoneKey)
        ModelDownloadService.excludeExistingModelsFromBackup()
        microphoneAuthorized = AVAudioApplication.shared.recordPermission == .granted
        microphoneDenied = AVAudioApplication.shared.recordPermission == .denied
    }

    func refreshMicrophonePermission() {
        let permission = AVAudioApplication.shared.recordPermission
        microphoneAuthorized = permission == .granted
        microphoneDenied = permission == .denied
    }

    var hasModelDownloaded: Bool { modelDownload.storedModelURL != nil }

    var appleIntelligenceStatus: SystemLanguageModel.Availability {
        SystemLanguageModel.default.availability
    }

    func requestMicrophonePermission() async -> Bool {
        if AVAudioApplication.shared.recordPermission == .granted {
            microphoneAuthorized = true
            return true
        }
        let granted = await AVAudioApplication.requestRecordPermission()
        microphoneAuthorized = granted
        microphoneDenied = !granted
        return granted
    }

    func downloadModelIfNeeded() async {
        if let url = modelDownload.storedModelURL {
            await loadModel(at: url)
            return
        }

        isDownloadingModel = true
        modelDownloadProgress = 0
        do {
            let url = try await modelDownload.download { [weak self] progress in
                Task { @MainActor in self?.modelDownloadProgress = progress }
            }
            isDownloadingModel = false
            await loadModel(at: url)
        } catch {
            isDownloadingModel = false
            PipelineLog.logger.error("Model download failed: \(String(describing: error), privacy: .public)")
            bootstrap = .failed(Self.userMessage(forDownloadError: error))
        }
    }

    func bootstrapIfReady() async {
        #if DEBUG
        if DebugOverrides.skipBootstrap { return }
        #endif
        guard hasCompletedOnboarding, let url = modelDownload.storedModelURL else { return }
        await loadModel(at: url)
    }

    func loadModel(at url: URL) async {
        // Finishing onboarding shows Home, whose .task calls bootstrapIfReady()
        // right after onboarding already loaded the model; don't load twice.
        if bootstrap == .loading { return }
        if coordinator.isModelLoaded {
            try? backgroundAudio.start()
            coordinator.startObserving()
            bootstrap = .ready
            return
        }
        PipelineLog.logger.notice("Loading Whisper model \(url.lastPathComponent, privacy: .public)")
        bootstrap = .loading
        do {
            try await coordinator.loadWhisperModel(at: url)
            try backgroundAudio.start()
            coordinator.startObserving()
            bootstrap = .ready
        } catch {
            PipelineLog.logger.error("Model load failed: \(String(describing: error), privacy: .public)")
            bootstrap = .failed("The speech model couldn't be loaded. Try restarting WhispIt; if it keeps failing, reinstall to download it again.")
        }
    }

    nonisolated static func userMessage(forDownloadError error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return "The download didn't finish. Check your internet connection and tap Retry."
        }
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileWriteOutOfSpaceError {
            return "There isn't enough free space. WhispIt needs about 1 GB of free space for the speech model."
        }
        return "The speech model couldn't be downloaded. Tap Retry to try again."
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: Self.onboardingDoneKey)
        hasCompletedOnboarding = true
    }
}
