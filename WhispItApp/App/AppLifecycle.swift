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

    private static let onboardingDoneKey = "WhispIt.hasCompletedOnboarding"

    private let modelDownload = ModelDownloadService()
    private let coordinator = DictationPipelineCoordinator.shared
    private let backgroundAudio = BackgroundAudioSessionManager.shared

    init() {
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Self.onboardingDoneKey)
        microphoneAuthorized = AVAudioApplication.shared.recordPermission == .granted
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
            bootstrap = .failed(String(describing: error))
        }
    }

    func bootstrapIfReady() async {
        guard hasCompletedOnboarding, let url = modelDownload.storedModelURL else { return }
        await loadModel(at: url)
    }

    private func loadModel(at url: URL) async {
        bootstrap = .loading
        do {
            try await coordinator.loadWhisperModel(at: url)
            try backgroundAudio.start()
            coordinator.startObserving()
            bootstrap = .ready
        } catch {
            bootstrap = .failed(String(describing: error))
        }
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: Self.onboardingDoneKey)
        hasCompletedOnboarding = true
    }
}
