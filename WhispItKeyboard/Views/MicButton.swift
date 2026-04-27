import SwiftUI

struct MicButton: View {
    @ObservedObject var state: KeyboardState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(backgroundColor)
                    .frame(width: 56, height: 56)

                Circle()
                    .stroke(Color.red, lineWidth: 3)
                    .frame(width: 56, height: 56)
                    .scaleEffect(state.recordingActive ? 1.5 : 1.0)
                    .opacity(state.recordingActive ? 1.0 : 0.0)
                    .animation(
                        state.recordingActive
                            ? .easeOut(duration: 1.2).repeatForever(autoreverses: false)
                            : .default,
                        value: state.recordingActive
                    )

                if state.showDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                } else if state.processing {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                } else {
                    Image(systemName: state.recordingActive ? "stop.fill" : "mic.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(state.processing || state.showDone)
        .accessibilityLabel(accessibilityLabel)
    }

    private var backgroundColor: Color {
        if state.showDone { return .green }
        if state.processing { return .gray }
        return state.recordingActive ? .red : .accentColor
    }

    private var accessibilityLabel: String {
        if state.showDone { return "Text inserted" }
        if state.processing { return "Cleaning up dictation" }
        return state.recordingActive ? "Stop recording" : "Start recording"
    }
}
