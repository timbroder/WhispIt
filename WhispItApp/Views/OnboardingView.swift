import FoundationModels
import SwiftUI
import UIKit

struct OnboardingView: View {
    @EnvironmentObject var lifecycle: AppLifecycle
    @Environment(\.scenePhase) private var scenePhase
    @State private var step: Step = .welcome

    enum Step: Int {
        case welcome
        case microphone
        case modelDownload
        case appleIntelligence
        case keyboardSetup
    }

    var body: some View {
        ScrollIfNeeded {
            VStack {
                switch step {
                case .welcome: welcomeStep
                case .microphone: microphoneStep
                case .modelDownload: modelDownloadStep
                case .appleIntelligence: appleIntelligenceStep
                case .keyboardSetup: keyboardSetupStep
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: scenePhase) { _, phase in
            // Returning from Settings after granting the mic: move on.
            guard phase == .active else { return }
            lifecycle.refreshMicrophonePermission()
            if step == .microphone, lifecycle.microphoneAuthorized {
                step = .modelDownload
            }
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 96))
                .foregroundStyle(.tint)
            Text("Welcome to WhispIt")
                .font(.largeTitle).bold()
            Text("Voice dictation that runs entirely on your iPhone. Your audio never leaves the device.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text("You'll see the red mic indicator at the top of your screen while WhispIt is enabled. That's the background audio session keeping the app alive so your keyboard can talk to it — not a recording in progress.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Spacer()
            Button("Get Started") { step = .microphone }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }

    private var microphoneStep: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "mic.fill")
                .font(.system(size: 80))
                .foregroundStyle(.tint)
            Text("Microphone Access")
                .font(.title).bold()
            Text("WhispIt needs the microphone to hear what you say. Audio is transcribed locally — nothing is uploaded.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if lifecycle.microphoneDenied {
                Text("Microphone access is turned off. Turn on Microphone for WhispIt in Settings, then come back.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.orange)
            }
            Spacer()
            if lifecycle.microphoneDenied {
                Button("Open Settings") { Self.openAppSettings() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            } else {
                Button(lifecycle.microphoneAuthorized ? "Continue" : "Allow Microphone") {
                    Task {
                        let granted = await lifecycle.requestMicrophonePermission()
                        if granted { step = .modelDownload }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    static func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private var modelDownloadStep: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.tint)
            Text("Download Speech Model")
                .font(.title).bold()
            Text("WhispIt downloads its speech model once. It's about 1.5 GB, so make sure you're on Wi-Fi.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if lifecycle.isDownloadingModel {
                ProgressView(value: lifecycle.modelDownloadProgress)
                    .padding(.horizontal, 48)
                Text("\(Int(lifecycle.modelDownloadProgress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else if case .failed(let message) = lifecycle.bootstrap {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Spacer()
            Button(buttonTitle) {
                if lifecycle.bootstrap == .ready {
                    step = .appleIntelligence
                } else {
                    Task {
                        await lifecycle.downloadModelIfNeeded()
                        if lifecycle.bootstrap == .ready { step = .appleIntelligence }
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(lifecycle.isDownloadingModel)
        }
    }

    private var buttonTitle: String {
        switch lifecycle.bootstrap {
        case .ready: return "Continue"
        case .loading: return "Loading…"
        case .failed: return "Retry"
        case .idle: return lifecycle.hasModelDownloaded ? "Continue" : "Download Model"
        }
    }

    private var appleIntelligenceStep: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: appleIntelligenceIcon)
                .font(.system(size: 80))
                .foregroundStyle(appleIntelligenceColor)
            Text("Apple Intelligence")
                .font(.title).bold()
            Text(appleIntelligenceMessage)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Continue") { step = .keyboardSetup }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }

    private var appleIntelligenceIcon: String {
        if case .available = lifecycle.appleIntelligenceStatus { return "sparkles" }
        return "exclamationmark.triangle.fill"
    }

    private var appleIntelligenceColor: Color {
        if case .available = lifecycle.appleIntelligenceStatus { return .accentColor }
        return .orange
    }

    private var appleIntelligenceMessage: String {
        switch lifecycle.appleIntelligenceStatus {
        case .available:
            return "Apple Intelligence is available. WhispIt will use it to clean up filler words, fix grammar, and add punctuation to your dictation."
        case .unavailable(let reason):
            return "\(Self.describe(reason)) WhispIt will still transcribe your speech, but won't clean it up."
        }
    }

    static func describe(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:
            return "This iPhone doesn't support Apple Intelligence."
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence is turned off. Turn it on in Settings → Apple Intelligence & Siri."
        case .modelNotReady:
            return "Apple Intelligence is still getting ready. This can take a while after it's turned on."
        @unknown default:
            return "Apple Intelligence isn't available right now."
        }
    }

    private var keyboardSetupStep: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "keyboard.fill")
                .font(.system(size: 80))
                .foregroundStyle(.tint)
            Text("Add the Keyboard")
                .font(.title).bold()
            VStack(alignment: .leading, spacing: 12) {
                Label("Tap Open Settings below", systemImage: "1.circle.fill")
                Label("Tap Keyboards and turn on WhispIt", systemImage: "2.circle.fill")
                Label("Turn on Allow Full Access", systemImage: "3.circle.fill")
            }
            .font(.callout)
            .padding(.horizontal)
            Text("Allow Full Access is required for the keyboard to talk to the main app. No data leaves your phone.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button("Open Settings") { Self.openAppSettings() }
            .buttonStyle(.bordered)
            Button("I've Added the Keyboard") {
                lifecycle.completeOnboarding()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}
