import SwiftUI

/// Shows `content` at full height when it fits, so its `Spacer`s still push
/// elements apart, and falls back to a vertical `ScrollView` when it doesn't
/// (for example, on iPhone in landscape).
struct ScrollIfNeeded<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
        }
    }
}
