import Foundation
import Testing
@testable import WhispIt

@Suite("ModelDownloadService storage")
struct ModelDownloadServiceTests {
    let tempDir = TemporaryDirectory()

    func isExcludedFromBackup(_ url: URL) throws -> Bool {
        try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup ?? false
    }

    /// Regression (H14): the ~1.5 GB re-downloadable model must not be backed up.
    @Test func downloadBaseIsCreatedAndExcludedFromBackup() throws {
        let base = tempDir.file("models")
        try ModelDownloadService.prepareDownloadBase(base)
        #expect(FileManager.default.fileExists(atPath: base.path))
        #expect(try isExcludedFromBackup(base))
    }

    @Test func preparingAnExistingDirectoryKeepsItsContents() throws {
        let base = tempDir.file("models")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try Data("weights".utf8).write(to: base.appending(path: "model.bin"))
        try ModelDownloadService.prepareDownloadBase(base)
        #expect(FileManager.default.fileExists(atPath: base.appending(path: "model.bin").path))
        #expect(try isExcludedFromBackup(base))
    }

    @Test func modelsRootLivesInTheAppGroup() throws {
        let root = try #require(ModelDownloadService.modelsRoot)
        let group = try #require(WhispItConstants.sharedContainerURL)
        #expect(root.path.hasPrefix(group.path))
    }
}
