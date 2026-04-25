import Foundation

final class DictionaryManager {
    static let shared = DictionaryManager()

    private let lock = NSLock()
    private var cache: [DictionaryEntry] = []
    private var loaded = false

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

    private init() {}

    func reload() {
        lock.lock()
        cache = (try? loadFromDisk()) ?? []
        loaded = true
        lock.unlock()
    }

    private func ensureLoadedLocked() {
        if !loaded {
            cache = (try? loadFromDisk()) ?? []
            loaded = true
        }
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

    private func loadFromDisk() throws -> [DictionaryEntry] {
        guard let url = WhispItConstants.sharedFileURL(.dictionary) else { return [] }
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try Self.decoder.decode([DictionaryEntry].self, from: data)
    }

    private func persistLocked() {
        guard let url = WhispItConstants.sharedFileURL(.dictionary) else { return }
        do {
            let data = try Self.encoder.encode(cache)
            try data.write(to: url, options: .atomic)
        } catch {
            // Persistence failure leaves cache in memory consistent for the
            // current process; next reload() will re-derive from disk.
        }
    }
}
