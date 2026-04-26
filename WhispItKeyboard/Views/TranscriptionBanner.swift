import SwiftUI

struct TranscriptionBanner: View {
    @ObservedObject var state: KeyboardState

    var body: some View {
        let text = displayText
        if !text.isEmpty {
            Text(text)
                .font(.callout)
                .lineLimit(2)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(state.lastError == nil ? Color.primary : .red)
                .transition(.opacity)
        }
    }

    private var displayText: String {
        if let error = state.lastError, !error.isEmpty {
            return error
        }
        if !state.interimTranscript.isEmpty {
            return state.interimTranscript
        }
        if state.processing { return "Cleaning up…" }
        if state.recordingActive { return "Listening…" }
        return ""
    }
}
