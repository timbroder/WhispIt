import Foundation

final class DictionaryManager {
    static let shared = DictionaryManager()

    private let lock = NSLock()
    private var cache: [DictionaryEntry] = []
    private var loaded = false
    /// Set when the file exists but couldn't be read (e.g. still protected
    /// before first unlock). Writes are held back so they can't overwrite
    /// entries we failed to load; the next reload retries.
    private var readFailed = false

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Where entries are persisted. `nil` means the App Group container is
    /// unavailable (e.g. keyboard without Full Access); entries stay in memory.
    private let fileURL: URL?

    init(fileURL: URL? = WhispItConstants.sharedFileURL(.dictionary)) {
        self.fileURL = fileURL
    }

    func reload() {
        lock.lock()
        loadLocked()
        lock.unlock()
    }

    private func ensureLoadedLocked() {
        if !loaded { loadLocked() }
    }

    private func loadLocked() {
        loaded = true
        readFailed = false
        guard let url = fileURL, FileManager.default.fileExists(atPath: url.path) else {
            cache = []
            return
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            readFailed = true
            cache = []
            return
        }
        do {
            cache = try Self.decoder.decode([DictionaryEntry].self, from: data)
        } catch {
            // Unreadable JSON: move it aside instead of letting the next save
            // overwrite it, so the user's words can still be recovered.
            quarantine(url)
            cache = []
        }
    }

    private func quarantine(_ url: URL) {
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = url.deletingLastPathComponent()
            .appending(path: "\(url.deletingPathExtension().lastPathComponent).corrupt-\(stamp).json")
        try? FileManager.default.moveItem(at: url, to: backup)
    }

    var allEntries: [DictionaryEntry] {
        lock.lock()
        defer { lock.unlock() }
        ensureLoadedLocked()
        return cache
    }

    func entries(matching query: String) -> [DictionaryEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return allEntries }
        return allEntries.filter { $0.word.lowercased().contains(trimmed) }
    }

    func entries(source: DictionaryEntry.EntrySource) -> [DictionaryEntry] {
        allEntries.filter { $0.source == source }
    }

    @discardableResult
    func add(word: String, source: DictionaryEntry.EntrySource) -> DictionaryEntry? {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        lock.lock()
        defer { lock.unlock() }
        ensureLoadedLocked()

        if let idx = cache.firstIndex(where: { $0.word.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            cache[idx].frequency += 1
            persistLocked()
            return cache[idx]
        }
        let entry = DictionaryEntry(word: trimmed, source: source)
        cache.append(entry)
        persistLocked()
        return entry
    }

    func remove(id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        ensureLoadedLocked()
        cache.removeAll { $0.id == id }
        persistLocked()
    }

    func incrementFrequency(for word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        lock.lock()
        defer { lock.unlock() }
        ensureLoadedLocked()
        if let idx = cache.firstIndex(where: { $0.word.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            cache[idx].frequency += 1
            persistLocked()
        }
    }

    private func persistLocked() {
        guard let url = fileURL, !readFailed else { return }
        do {
            let data = try Self.encoder.encode(cache)
            try data.write(to: url, options: .atomic)
        } catch {
            // Persistence failure leaves cache in memory consistent for the
            // current process; next reload() will re-derive from disk.
        }
    }
}
