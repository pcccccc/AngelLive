import CryptoKit
import Foundation

public enum LiveLanguageDetectionResourceError: LocalizedError, Equatable, Sendable {
    case storageUnavailable
    case downloadInProgress
    case invalidResponse
    case invalidModel

    public var errorDescription: String? {
        switch self {
        case .storageUnavailable: "无法保存字幕识别文件，请检查剩余空间。"
        case .downloadInProgress: "字幕识别文件正在下载。"
        case .invalidResponse: "字幕识别文件下载失败，请检查网络后重试。"
        case .invalidModel: "字幕识别文件已损坏，请重新下载。"
        }
    }
}

struct LiveLanguageModelFiles: Sendable {
    let language: URL
    let vad: URL
}

struct LiveLanguageModelArtifact: Sendable {
    let filename: String
    let url: URL
    let bytes: Int64
    let sha256: String

    static let models: [Self] = [
        .init(
            filename: "ggml-tiny.bin",
            url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-tiny.bin")!,
            bytes: 77_691_713,
            sha256: "be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21"
        ),
        .init(
            filename: "ggml-silero-v6.2.0.bin",
            url: URL(string: "https://huggingface.co/ggml-org/whisper-vad/resolve/9ffd54a1e1ee413ddf265af9913beaf518d1639b/ggml-silero-v6.2.0.bin")!,
            bytes: 885_098,
            sha256: "2aa269b785eeb53a82983a20501ddf7c1d9c48e33ab63a41391ac6c9f7fb6987"
        )
    ]
}

protocol LiveLanguageModelDownloading: Sendable {
    func download(
        artifact: LiveLanguageModelArtifact,
        progress: @escaping @MainActor @Sendable (Int64) -> Void
    ) async throws -> URL
}

private struct LiveLanguageModelDownloader: LiveLanguageModelDownloading {
    func download(
        artifact: LiveLanguageModelArtifact,
        progress: @escaping @MainActor @Sendable (Int64) -> Void
    ) async throws -> URL {
        var request = URLRequest(url: artifact.url)
        request.timeoutInterval = 300
        let delegate = LiveLanguageModelDownloadProgress(progress: progress)
        let (temporaryURL, response) = try await URLSession.shared.download(for: request, delegate: delegate)
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw LiveLanguageDetectionResourceError.invalidResponse
        }
        return temporaryURL
    }
}

private final class LiveLanguageModelDownloadProgress: NSObject, URLSessionDownloadDelegate {
    let progress: @MainActor @Sendable (Int64) -> Void

    init(progress: @escaping @MainActor @Sendable (Int64) -> Void) {
        self.progress = progress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let callback = progress
        Task { @MainActor in callback(totalBytesWritten) }
    }
}

@MainActor
private final class LiveLanguageModelProgressLifetime {
    private var isOpen = true
    private let callback: @MainActor @Sendable (Int64) -> Void

    init(callback: @escaping @MainActor @Sendable (Int64) -> Void) {
        self.callback = callback
    }

    func report(_ bytes: Int64) {
        guard isOpen else { return }
        callback(bytes)
    }

    func close() {
        isOpen = false
    }
}

/// Download is explicit. Status and inference only inspect local resources.
/// tvOS uses purgeable cache storage and returns needsDownload after eviction.
public actor LiveLanguageDetectionResources {
    public static let shared = LiveLanguageDetectionResources()

    private let directory: URL?
    private let artifacts: [LiveLanguageModelArtifact]
    private let downloader: any LiveLanguageModelDownloading
    private var isDownloading = false
    private var verifiedFiles: [URL: VerifiedFileSignature] = [:]

    private struct VerifiedFileSignature: Equatable {
        let bytes: Int64
        let modified: Date
        let fileNumber: UInt64
    }

    private init() {
        #if os(tvOS)
        let searchDirectory: FileManager.SearchPathDirectory = .cachesDirectory
        #else
        let searchDirectory: FileManager.SearchPathDirectory = .applicationSupportDirectory
        #endif
        directory = FileManager.default.urls(for: searchDirectory, in: .userDomainMask).first?
            .appendingPathComponent("AngelLive/LiveLanguageDetection/v1", isDirectory: true)
        artifacts = LiveLanguageModelArtifact.models
        downloader = LiveLanguageModelDownloader()
    }

    init(
        directory: URL,
        artifacts: [LiveLanguageModelArtifact] = LiveLanguageModelArtifact.models,
        downloader: any LiveLanguageModelDownloading = LiveLanguageModelDownloader()
    ) {
        self.directory = directory
        self.artifacts = artifacts
        self.downloader = downloader
    }

    public func status() async -> LiveSubtitleResourceStatus {
        if isDownloading { return .downloading }
        guard let directory else { return .unavailable }
        do {
            for artifact in artifacts {
                guard try verified(artifact, at: directory.appendingPathComponent(artifact.filename)) else {
                    return .needsDownload
                }
            }
            return .ready
        } catch { return .needsDownload }
    }

    public func download(progress: @escaping @MainActor @Sendable (Double) -> Void) async throws {
        guard !isDownloading else { throw LiveLanguageDetectionResourceError.downloadInProgress }
        guard var directory else { throw LiveLanguageDetectionResourceError.storageUnavailable }
        isDownloading = true
        defer { isDownloading = false }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        let total = artifacts.reduce(Int64(0)) { $0 + $1.bytes }
        var completed: Int64 = 0
        await progress(0)
        for artifact in artifacts {
            try Task.checkCancellation()
            let destination = directory.appendingPathComponent(artifact.filename)
            if try verified(artifact, at: destination) {
                completed += artifact.bytes
                await progress(Double(completed) / Double(total))
                continue
            }
            let previousBytes = completed
            let progressLifetime = await LiveLanguageModelProgressLifetime { bytes in
                progress(Double(previousBytes + min(max(bytes, 0), artifact.bytes)) / Double(total))
            }
            let temporaryURL: URL
            do {
                temporaryURL = try await downloader.download(artifact: artifact) { bytes in
                    progressLifetime.report(bytes)
                }
            } catch {
                await progressLifetime.close()
                throw error
            }
            // Delegate callbacks enqueue independent MainActor tasks. Closing
            // on that actor before proceeding drops any delayed progress.
            await progressLifetime.close()
            // The URLSession result is a local temporary file. Always clean it
            // on cancellation/verification failure, preserving installed files.
            defer { try? FileManager.default.removeItem(at: temporaryURL) }
            try Task.checkCancellation()
            guard try verified(artifact, at: temporaryURL) else {
                throw LiveLanguageDetectionResourceError.invalidModel
            }
            let staged = directory.appendingPathComponent(UUID().uuidString + ".partial")
            try FileManager.default.moveItem(at: temporaryURL, to: staged)
            defer { try? FileManager.default.removeItem(at: staged) }
            try Task.checkCancellation()
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: staged)
            } else {
                try FileManager.default.moveItem(at: staged, to: destination)
            }
            completed += artifact.bytes
            await progress(Double(completed) / Double(total))
        }
        try Task.checkCancellation()
        await progress(1)
    }

    func verifiedModelFiles() throws -> LiveLanguageModelFiles {
        guard let directory else { throw LiveAudioLanguageDetectionError.resourcesMissing }
        for artifact in artifacts {
            guard try verified(artifact, at: directory.appendingPathComponent(artifact.filename)) else {
                throw LiveAudioLanguageDetectionError.resourcesMissing
            }
        }
        return LiveLanguageModelFiles(
            language: directory.appendingPathComponent("ggml-tiny.bin"),
            vad: directory.appendingPathComponent("ggml-silero-v6.2.0.bin")
        )
    }

    private func verified(_ artifact: LiveLanguageModelArtifact, at url: URL) throws -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            verifiedFiles[url] = nil
            return false
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let bytes = (attributes[.size] as? NSNumber)?.int64Value, bytes == artifact.bytes,
              let modified = attributes[.modificationDate] as? Date,
              let fileNumber = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value else {
            verifiedFiles[url] = nil
            return false
        }
        let signature = VerifiedFileSignature(bytes: bytes, modified: modified, fileNumber: fileNumber)
        // Hash each installed file at least once per process; replacing or
        // modifying it invalidates this cache. Silence does not reread 78 MB.
        if verifiedFiles[url] == signature { return true }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        while let chunk = try file.read(upToCount: 1_048_576), !chunk.isEmpty {
            try Task.checkCancellation()
            hash.update(data: chunk)
        }
        let matches = hash.finalize().map { String(format: "%02x", $0) }.joined() == artifact.sha256
        verifiedFiles[url] = matches ? signature : nil
        return matches
    }
}
