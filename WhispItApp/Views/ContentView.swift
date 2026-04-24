import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("WhispIt")
                .font(.largeTitle)
                .bold()
            Text("Voice dictation, everywhere.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
