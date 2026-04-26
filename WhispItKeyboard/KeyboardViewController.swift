import SwiftUI
import UIKit

final class KeyboardViewController: UIInputViewController {
    private let state = KeyboardState()
    private var hostingController: UIHostingController<KeyboardView>?

    override func viewDidLoad() {
        super.viewDidLoad()

        let view = KeyboardView(
            state: state,
            actions: KeyboardActions(
                onMicTap: { [weak self] in self?.handleMicTap() },
                onKeyTap: { [weak self] character in self?.insert(character) },
                onBackspace: { [weak self] in self?.deleteBackward() },
                onShift: { [weak self] in self?.handleShift() },
                onReturn: { [weak self] in self?.insert("\n") },
                onSpace: { [weak self] in self?.insert(" ") },
                onGlobe: { [weak self] in self?.advanceToNextInputMode() }
            )
        )

        let hosting = UIHostingController(rootView: view)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        hosting.view.backgroundColor = .clear
        addChild(hosting)
        self.view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: self.view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
        ])
        hosting.didMove(toParent: self)
        hostingController = hosting

        observeIPC()
        refreshSharedState()
    }

    private func handleMicTap() {
        state.processing = false
        if state.recordingActive {
            Haptics.medium()
            IPCManager.shared.post(WhispItConstants.DarwinNotification.recordingStopRequested)
            state.processing = true
        } else {
            Haptics.light()
            IPCManager.shared.post(WhispItConstants.DarwinNotification.recordingStartRequested)
        }
    }

    private func handleShift() {
        if state.isShiftActive {
            state.isCapsLocked.toggle()
        } else {
            state.isShiftActive = true
        }
    }

    private func insert(_ text: String) {
        let isUppercase = state.isShiftActive || state.isCapsLocked
        textDocumentProxy.insertText(isUppercase ? text.uppercased() : text)
        if state.isShiftActive && !state.isCapsLocked {
            state.isShiftActive = false
        }
    }

    private func deleteBackward() {
        textDocumentProxy.deleteBackward()
    }

    private func observeIPC() {
        IPCManager.shared.observe(WhispItConstants.DarwinNotification.cleanedTextReady) { [weak self] in
            DispatchQueue.main.async { self?.handleCleanedTextReady() }
        }
        IPCManager.shared.observe(WhispItConstants.DarwinNotification.transcriptionUpdated) { [weak self] in
            DispatchQueue.main.async { self?.refreshSharedState() }
        }
        IPCManager.shared.observe(WhispItConstants.DarwinNotification.recordingFailed) { [weak self] in
            DispatchQueue.main.async {
                self?.state.processing = false
                self?.refreshSharedState()
                Haptics.error()
            }
        }
    }

    private func refreshSharedState() {
        guard let shared = try? IPCManager.shared.read(SharedState.self, from: .sharedState) else {
            return
        }
        state.apply(shared)
    }

    private func handleCleanedTextReady() {
        state.processing = false
        guard let cleaned = try? IPCManager.shared.readText(from: .cleanedText), !cleaned.isEmpty else {
            return
        }
        textDocumentProxy.insertText(cleaned)
        state.interimTranscript = ""
        Haptics.success()
    }

    deinit {
        IPCManager.shared.removeAllObservers()
    }
}
