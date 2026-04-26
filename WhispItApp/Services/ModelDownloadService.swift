import Foundation
import WhisperKit

final class ModelDownloadService {
    enum DownloadError: Error {
        case appGroupContainerUnavailable
        case alreadyDownloading
    }

    static let defaultVariant = "openai_whisper-large-v3-v20240930_turbo"
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

    func download(
        variant: String = ModelDownloadService.defaultVariant,
        progress progressHandler: @escaping (Double) -> Void = { _ in }
    ) async throws -> URL {
        guard !isDownloading else { throw DownloadError.alreadyDownloading }

        guard let downloadBase = WhispItConstants.sharedContainerURL?.appending(path: "models") else {
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

        UserDefaults(suiteName: WhispItConstants.appGroupID)?
            .set(modelURL.path, forKey: Self.modelURLDefaultsKey)

        return modelURL
    }
}
