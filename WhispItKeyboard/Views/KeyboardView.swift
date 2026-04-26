import SwiftUI

struct KeyboardActions {
    let onMicTap: () -> Void
    let onKeyTap: (String) -> Void
    let onBackspace: () -> Void
    let onShift: () -> Void
    let onReturn: () -> Void
    let onSpace: () -> Void
    let onGlobe: () -> Void
}

struct KeyboardView: View {
    @ObservedObject var state: KeyboardState
    let actions: KeyboardActions

    private static let row1 = ["q","w","e","r","t","y","u","i","o","p"]
    private static let row2 = ["a","s","d","f","g","h","j","k","l"]
    private static let row3 = ["z","x","c","v","b","n","m"]

    var body: some View {
        VStack(spacing: 8) {
            TranscriptionBanner(state: state)

            MicButton(state: state, action: actions.onMicTap)

            VStack(spacing: 6) {
                letterRow(Self.row1)
                letterRow(Self.row2)
                    .padding(.horizontal, 18)
                HStack(spacing: 6) {
                    modifierKey(image: shiftIcon, action: actions.onShift)
                    ForEach(Self.row3, id: \.self) { letter in
                        letterKey(letter)
                    }
                    modifierKey(image: "delete.left", action: actions.onBackspace)
                }
                HStack(spacing: 6) {
                    modifierKey(image: "globe", action: actions.onGlobe, width: 44)
                    spaceKey
                    returnKey
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }

    private func letterRow(_ letters: [String]) -> some View {
        HStack(spacing: 6) {
            ForEach(letters, id: \.self) { letter in
                letterKey(letter)
            }
        }
    }

    private func letterKey(_ letter: String) -> some View {
        let display = (state.isShiftActive || state.isCapsLocked) ? letter.uppercased() : letter
        return Button(action: { actions.onKeyTap(letter) }) {
            Text(display)
                .font(.system(size: 18))
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(Color(.label))
        }
        .buttonStyle(.plain)
    }

    private func modifierKey(image: String, action: @escaping () -> Void, width: CGFloat = 40) -> some View {
        Button(action: action) {
            Image(systemName: image)
                .font(.system(size: 16))
                .frame(width: width, height: 40)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(Color(.label))
        }
        .buttonStyle(.plain)
    }

    private var spaceKey: some View {
        Button(action: actions.onSpace) {
            Text("space")
                .font(.system(size: 14))
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(Color(.label))
        }
        .buttonStyle(.plain)
    }

    private var returnKey: some View {
        Button(action: actions.onReturn) {
            Image(systemName: "return")
                .font(.system(size: 16))
                .frame(width: 64, height: 40)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(Color(.label))
        }
        .buttonStyle(.plain)
    }

    private var shiftIcon: String {
        if state.isCapsLocked { return "capslock.fill" }
        return state.isShiftActive ? "shift.fill" : "shift"
    }
}
