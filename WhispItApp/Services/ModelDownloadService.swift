import Foundation
import WhisperKit

final class ModelDownloadService {
    enum DownloadError: Error {
        case appGroupContainerUnavailable
        case alreadyDownloading
    }

    static let defaultVariant = "openai_whisper-large-v3-v20240930_turbo"

    /// The variant onboarding downloads. Debug builds can swap in a small
    /// model with `-WhispItModelVariant openai_whisper-tiny`.
    static var preferredVariant: String {
        #if DEBUG
        if let override = DebugOverrides.modelVariant, !override.isEmpty {
            return override
        }
        #endif
        return defaultVariant
    }
    private static let modelURLDefaultsKey = "WhispIt.downloadedModelFolderPath"

    private(set) var isDownloading = false

    /// Root of downloaded models inside the App Group container.
    static var modelsRoot: URL? {
        WhispItConstants.sharedContainerURL?.appending(path: "models")
    }

    /// Creates the models directory and excludes it from iCloud/device
    /// backups: the model is re-downloadable and ~1.5 GB (App Store
    /// guideline 2.23, iOS Data Storage Guidelines).
    static func prepareDownloadBase(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try excludeFromBackup(url)
    }

    static func excludeFromBackup(_ url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }

    /// Applies the backup exclusion to models downloaded by earlier builds.
    static func excludeExistingModelsFromBackup() {
        guard let root = modelsRoot, FileManager.default.fileExists(atPath: root.path) else { return }
        try? excludeFromBackup(root)
    }

    var storedModelURL: URL? {
        guard let defaults = UserDefaults(suiteName: WhispItConstants.appGroupID),
              let path = defaults.string(forKey: Self.modelURLDefaultsKey) else {
            return nil
        }
        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// - Parameters:
    ///   - downloadBase: where to store the model. Defaults to the App Group
    ///     container; tests pass their own cache directory.
    ///   - remember: record the location so the app treats the model as installed.
    func download(
        variant: String = ModelDownloadService.preferredVariant,
        into downloadBase: URL? = ModelDownloadService.modelsRoot,
        remember: Bool = true,
        progress progressHandler: @escaping (Double) -> Void = { _ in }
    ) async throws -> URL {
        guard !isDownloading else { throw DownloadError.alreadyDownloading }

        guard let downloadBase else {
            throw DownloadError.appGroupContainerUnavailable
        }

        try Self.prepareDownloadBase(downloadBase)

        isDownloading = true
        defer { isDownloading = false }

        let modelURL = try await WhisperKit.download(
            variant: variant,
            downloadBase: downloadBase,
            useBackgroundSession: false,
            progressCallback: { progress in
                progressHandler(progress.fractionCompleted)
            }
        )

        if remember {
            UserDefaults(suiteName: WhispItConstants.appGroupID)?
                .set(modelURL.path, forKey: Self.modelURLDefaultsKey)
        }

        return modelURL
    }
}
