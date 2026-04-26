import SwiftUI

struct SettingsView: View {
    var body: some View {
        List {
            Section {
                NavigationLink {
                    DictionaryView()
                } label: {
                    Label("Personal Dictionary", systemImage: "book")
                }
                NavigationLink {
                    DictationPreferencesView()
                } label: {
                    Label("Dictation Preferences", systemImage: "mic.badge.plus")
                }
            }

            Section("About") {
                LabeledContent("Version") {
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                        .foregroundStyle(.secondary)
                }
                Link(destination: URL(string: "https://github.com/timbroder/WhispIt/blob/main/docs/privacy.md")!) {
                    Label("Privacy Policy", systemImage: "hand.raised")
                }
            }
        }
        .navigationTitle("Settings")
    }
}
