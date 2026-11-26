import Foundation
import Testing
@testable import WhispIt

@Suite("DictionaryManager")
struct DictionaryManagerTests {
    let tempDir = TemporaryDirectory()
    var fileURL: URL { tempDir.file("dictionary.json") }

    func makeManager() -> DictionaryManager { DictionaryManager(fileURL: fileURL) }

    @Test func startsEmptyWhenNoFile() {
        #expect(makeManager().allEntries.isEmpty)
    }

    @Test func addTrimsWhitespace() throws {
        let manager = makeManager()
        let entry = try #require(manager.add(word: "  Kubernetes \n", source: .manual))
        #expect(entry.word == "Kubernetes")
        #expect(entry.source == .manual)
        #expect(entry.frequency == 1)
    }

    @Test(arguments: ["", "   ", "\n\t"])
    func addRejectsBlankWords(_ word: String) {
        let manager = makeManager()
        #expect(manager.add(word: word, source: .manual) == nil)
        #expect(manager.allEntries.isEmpty)
    }

    @Test func addingDuplicateIgnoresCaseAndBumpsFrequency() throws {
        let manager = makeManager()
        manager.add(word: "Anthropic", source: .manual)
        let again = try #require(manager.add(word: "anthropic", source: .automatic))
        #expect(manager.allEntries.count == 1)
        #expect(again.frequency == 2)
        #expect(again.word == "Anthropic", "Original casing is kept")
        #expect(again.source == .manual, "Original source is kept")
    }

    @Test func removeDeletesOnlyThatEntry() throws {
        let manager = makeManager()
        let keep = try #require(manager.add(word: "Keep", source: .manual))
        let drop = try #require(manager.add(word: "Drop", source: .manual))
        manager.remove(id: drop.id)
        #expect(manager.allEntries.map(\.id) == [keep.id])
    }

    @Test func searchIsCaseInsensitiveAndTrimmed() {
        let manager = makeManager()
        manager.add(word: "Kubernetes", source: .manual)
        manager.add(word: "Anthropic", source: .automatic)
        #expect(manager.entries(matching: "  KUBER ").map(\.word) == ["Kubernetes"])
        #expect(manager.entries(matching: "").count == 2)
        #expect(manager.entries(matching: "zzz").isEmpty)
    }

    @Test func filtersBySource() {
        let manager = makeManager()
        manager.add(word: "Manual", source: .manual)
        manager.add(word: "Auto", source: .automatic)
        #expect(manager.entries(source: .manual).map(\.word) == ["Manual"])
        #expect(manager.entries(source: .automatic).map(\.word) == ["Auto"])
    }

    @Test func incrementFrequencyOnlyAffectsExistingWords() {
        let manager = makeManager()
        manager.add(word: "Swift", source: .manual)
        manager.incrementFrequency(for: " swift ")
        manager.incrementFrequency(for: "Kotlin")
        #expect(manager.allEntries.map(\.frequency) == [2])
        #expect(manager.allEntries.count == 1)
    }

    @Test func persistsAcrossInstances() {
        makeManager().add(word: "Persisted", source: .manual)
        let reloaded = makeManager()
        #expect(reloaded.allEntries.map(\.word) == ["Persisted"])
    }

    @Test func reloadPicksUpChangesFromAnotherInstance() {
        let first = makeManager()
        #expect(first.allEntries.isEmpty)
        makeManager().add(word: "FromOtherProcess", source: .manual)
        first.reload()
        #expect(first.allEntries.map(\.word) == ["FromOtherProcess"])
    }

    @Test func nilFileURLKeepsEntriesInMemory() {
        let manager = DictionaryManager(fileURL: nil)
        manager.add(word: "Ephemeral", source: .manual)
        #expect(manager.allEntries.map(\.word) == ["Ephemeral"])
    }

    /// Regression (H8): a corrupt dictionary file must not be silently replaced
    /// by the next write, which would throw away every entry the user had.
    @Test func corruptFileIsNotOverwrittenByNextAdd() throws {
        let garbage = Data("{ not json".utf8)
        try garbage.write(to: fileURL)

        let manager = makeManager()
        manager.add(word: "New", source: .manual)

        let preserved = FileManager.default.fileExists(atPath: fileURL.path)
            && (try? Data(contentsOf: fileURL)) == garbage
        let backups = (try? FileManager.default.contentsOfDirectory(atPath: tempDir.url.path)) ?? []
        let backedUp = backups.contains { $0.hasPrefix("dictionary.corrupt") }
        #expect(preserved || backedUp)
        #expect(manager.allEntries.map(\.word) == ["New"], "the dictionary keeps working")
    }

    @Test func corruptFileIsMovedAsideWithItsContents() throws {
        let garbage = Data("[{\"word\": \"Half".utf8)
        try garbage.write(to: fileURL)
        _ = makeManager().allEntries
        let names = try FileManager.default.contentsOfDirectory(atPath: tempDir.url.path)
        let backup = try #require(names.first { $0.hasPrefix("dictionary.corrupt-") })
        #expect(try Data(contentsOf: tempDir.file(backup)) == garbage)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test func unreadableFileIsNeverOverwritten() throws {
        // A directory where the file should be: exists, but can't be read as data.
        try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: true)
        let manager = makeManager()
        manager.add(word: "InMemory", source: .manual)
        #expect(manager.allEntries.map(\.word) == ["InMemory"])
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) && isDirectory.boolValue)
    }
}
