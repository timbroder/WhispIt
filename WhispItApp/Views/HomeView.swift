import SwiftUI

struct HomeView: View {
    @EnvironmentObject var lifecycle: AppLifecycle

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "mic.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.tint)

                Text("WhispIt")
                    .font(.largeTitle).bold()

                statusCard

                Spacer()

                NavigationLink {
                    SettingsView()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding()
            .navigationTitle("")
            .navigationBarHidden(true)
        }
        .task {
            await lifecycle.bootstrapIfReady()
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch lifecycle.bootstrap {
            case .ready:
                Label("Ready", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Switch to the WhispIt keyboard in any app and tap the mic to dictate.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            case .loading:
                ProgressView()
                Text("Loading the speech model…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            case .failed(let message):
                Label("Setup needs attention", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .idle:
                Label("Initializing…", systemImage: "hourglass")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}
