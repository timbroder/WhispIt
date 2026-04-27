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

    func apply(_ shared: SharedState) {
        recordingActive = shared.recordingActive
        interimTranscript = shared.lastInterimTranscript
        lastError = shared.lastError
    }
}
