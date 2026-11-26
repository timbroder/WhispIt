import SwiftUI
import UIKit

final class KeyboardViewController: UIInputViewController {
    private let state = KeyboardState()
    private var hostingController: UIHostingController<KeyboardView>?
    private lazy var dictation = KeyboardDictationController(
        state: state,
        ipc: IPCManager.shared,
        feedback: HapticFeedback(),
        insertText: { [weak self] text in self?.textDocumentProxy.insertText(text) }
    )

    override func viewDidLoad() {
        super.viewDidLoad()

        let view = KeyboardView(
            state: state,
            actions: KeyboardActions(
                onMicTap: { [weak self] in self?.dictation.micTapped() },
                onKeyTap: { [weak self] character in self?.insert(character) },
                onBackspace: { [weak self] in self?.deleteBackward() },
                onShift: { [weak self] in self?.handleShift() },
                onReturn: { [weak self] in self?.insert("\n") },
                onSpace: { [weak self] in self?.insert(" ") },
                onGlobe: { [weak self] in self?.advanceToNextInputMode() }
            )
        )

        let hosting = UIHostingController(rootView: view)
        hosting.sizingOptions = .intrinsicContentSize
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

        dictation.activate()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        // Apple: hide the custom globe when the system provides one.
        if state.showsGlobeKey != needsInputModeSwitchKey {
            state.showsGlobeKey = needsInputModeSwitchKey
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        dictation.refreshFromSharedState(ignoringStaleError: true)
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

    deinit {
        IPCManager.shared.removeAllObservers()
    }
}

private struct HapticFeedback: KeyboardFeedback {
    func recordingStarted() { Haptics.light() }
    func recordingStopped() { Haptics.medium() }
    func textInserted() { Haptics.success() }
    func failed() { Haptics.error() }
}
