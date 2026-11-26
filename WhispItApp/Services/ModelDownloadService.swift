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
        into downloadBase: URL? = WhispItConstants.sharedContainerURL?.appending(path: "models"),
        remember: Bool = true,
        progress progressHandler: @escaping (Double) -> Void = { _ in }
    ) async throws -> URL {
        guard !isDownloading else { throw DownloadError.alreadyDownloading }

        guard let downloadBase else {
            throw DownloadError.appGroupContainerUnavailable
        }

        try? FileManager.default.createDirectory(
            at: downloadBase,
            withIntermediateDirectories: true
        )

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
