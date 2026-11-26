import Foundation
import SwiftUI

@MainActor
final class KeyboardState: ObservableObject {
    @Published var recordingActive: Bool = false
    @Published var processing: Bool = false
    @Published var showDone: Bool = false
    @Published var interimTranscript: String = ""
    @Published var lastError: String?
    @Published var isShiftActive: Bool = false
    @Published var isCapsLocked: Bool = false
    /// False on devices where the system already draws a globe key.
    @Published var showsGlobeKey: Bool = true

    func apply(_ shared: SharedState) {
        recordingActive = shared.recordingActive
        interimTranscript = shared.lastInterimTranscript
        lastError = shared.lastError
    }
}
