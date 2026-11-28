import Foundation
import Testing
import WhisperKit
@testable import WhispIt

@Suite("ModelDownloadService storage")
struct ModelDownloadServiceTests {
    let tempDir = TemporaryDirectory()

    func isExcludedFromBackup(_ url: URL) throws -> Bool {
        try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup ?? false
    }

    /// Regression (H14): the ~630 MB re-downloadable model must not be backed up.
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

@Suite("ModelDownloadService model choice")
struct ModelVariantTests {
    /// Regression (WhispIt-4yf): the model onboarding downloads must be one
    /// Argmax supports on iPhone. Its device table lists the full ~1.5 GB
    /// large-v3 turbo build only for Macs and M-series iPads; iPhones get the
    /// compressed 632 MB build of the same model. Covers iPhone 14 Pro,
    /// 15 Pro and 16 Pro identifiers.
    @Test(arguments: ["iPhone15,2", "iPhone16,1", "iPhone17,1"])
    func defaultModelIsSupportedOnIPhone(_ device: String) {
        let support = Constants.fallbackModelSupportConfig.modelSupport(for: device)
        #expect(support.supported.contains(ModelDownloadService.defaultVariant),
                "\(ModelDownloadService.defaultVariant) isn't in WhisperKit's supported list for \(device)")
    }
}
