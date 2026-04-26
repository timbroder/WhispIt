import SwiftUI

struct DictionaryView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all, automatic, manual
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    @State private var entries: [DictionaryEntry] = []
    @State private var query = ""
    @State private var filter: Filter = .all
    @State private var showAddSheet = false
    @State private var newWord = ""

    private let manager = DictionaryManager.shared

    var body: some View {
        List {
            Picker("Filter", selection: $filter) {
                ForEach(Filter.allCases) { f in
                    Text(f.label).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets())
            .padding(.horizontal)
            .padding(.bottom, 4)

            if filtered.isEmpty {
                ContentUnavailableView(
                    "No Words",
                    systemImage: "book",
                    description: Text("Tap + to add a word manually, or let WhispIt learn proper nouns from your dictation.")
                )
            } else {
                ForEach(filtered) { entry in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(entry.word)
                                .font(.body)
                            Text("Seen \(entry.frequency) time\(entry.frequency == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(entry.source.rawValue.capitalized)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(badgeColor(for: entry.source), in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
                .onDelete(perform: delete)
            }
        }
        .searchable(text: $query, prompt: "Search words")
        .navigationTitle("Dictionary")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Label("Add Word", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            addSheet
        }
        .onAppear { reload() }
    }

    private var filtered: [DictionaryEntry] {
        let base: [DictionaryEntry]
        switch filter {
        case .all: base = entries
        case .automatic: base = entries.filter { $0.source == .automatic }
        case .manual: base = entries.filter { $0.source == .manual }
        }
        if query.isEmpty { return base }
        return base.filter { $0.word.localizedCaseInsensitiveContains(query) }
    }

    private func badgeColor(for source: DictionaryEntry.EntrySource) -> Color {
        switch source {
        case .automatic: return .blue
        case .manual: return .green
        }
    }

    private func reload() {
        manager.reload()
        entries = manager.allEntries.sorted { $0.word < $1.word }
    }

    private func delete(at offsets: IndexSet) {
        let toDelete = offsets.map { filtered[$0] }
        for entry in toDelete {
            manager.remove(id: entry.id)
        }
        reload()
    }

    private var addSheet: some View {
        NavigationStack {
            Form {
                Section("Word") {
                    TextField("e.g. WhispIt, kubernetes, Anthropic", text: $newWord)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                Section {
                    Text("Manual entries are added to the prompt WhisperKit uses to bias recognition toward your vocabulary.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add Word")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        newWord = ""
                        showAddSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        manager.add(word: newWord, source: .manual)
                        newWord = ""
                        showAddSheet = false
                        reload()
                    }
                    .disabled(newWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
