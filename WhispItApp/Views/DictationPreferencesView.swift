import SwiftUI

struct DictationPreferencesView: View {
    @State private var silenceTimeout: TimeInterval = SettingsManager.shared.silenceTimeoutSeconds

    private let options: [TimeInterval] = [1, 2, 3, 5]

    var body: some View {
        Form {
            Section {
                Picker("Auto-stop after", selection: $silenceTimeout) {
                    ForEach(options, id: \.self) { value in
                        Text("\(Int(value))s").tag(value)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Silence Timeout")
            } footer: {
                Text("How long WhispIt waits in silence before automatically ending the recording.")
            }
        }
        .navigationTitle("Dictation")
        .onChange(of: silenceTimeout) { _, newValue in
            SettingsManager.shared.silenceTimeoutSeconds = newValue
        }
    }
}
