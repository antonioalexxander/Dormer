import CryptoKit
import Foundation
import os

/// Downloads a file over HTTPS, reporting progress.
public enum Downloader {
    public struct Progress: Sendable, Equatable {
        public var receivedBytes: Int64
        public var totalBytes: Int64
        public var bytesPerSecond: Double
    }

    public enum DownloadError: LocalizedError, Equatable {
        case insecureURL
        case httpStatus(Int)

        public var errorDescription: String? {
            switch self {
            case .insecureURL:
                String(localized: "Dormer solo descarga archivos por HTTPS.")
            case .httpStatus(let code):
                String(localized: "El servidor respondió con el código \(code). Inténtalo más tarde.")
            }
        }
    }

    /// Downloads `url` to `destination`, replacing any existing file.
    public static func download(
        _ url: URL, to destination: URL, expectedBytes: Int64,
        onProgress: @escaping @Sendable (Progress) -> Void
    ) async throws {
        guard url.scheme?.lowercased() == "https" else { throw DownloadError.insecureURL }
        let delegate = DownloadDelegate(destination: destination, expectedBytes: expectedBytes, onProgress: onProgress)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let task = session.downloadTask(with: url)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                delegate.setContinuation(continuation)
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let expectedBytes: Int64
    private let onProgress: @Sendable (Downloader.Progress) -> Void
    private let state = OSAllocatedUnfairLock(initialState: State())

    private struct State {
        var continuation: CheckedContinuation<Void, any Error>?
        var movedFile = false
        var moveError: (any Error)?
        var startedAt = ContinuousClock.now
        var lastReport = ContinuousClock.now - .seconds(1)
    }

    init(destination: URL, expectedBytes: Int64, onProgress: @escaping @Sendable (Downloader.Progress) -> Void) {
        self.destination = destination
        self.expectedBytes = expectedBytes
        self.onProgress = onProgress
    }

    func setContinuation(_ continuation: CheckedContinuation<Void, any Error>) {
        state.withLock {
            $0.continuation = continuation
            $0.startedAt = .now
        }
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        let now = ContinuousClock.now
        let elapsed: Duration? = state.withLock { state in
            guard now - state.lastReport >= .milliseconds(150) else { return nil }
            state.lastReport = now
            return now - state.startedAt
        }
        guard let elapsed else { return }
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expectedBytes
        onProgress(
            .init(
                receivedBytes: totalBytesWritten, totalBytes: total,
                bytesPerSecond: seconds > 0 ? Double(totalBytesWritten) / seconds : 0))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The temporary file is deleted when this method returns, so move it now.
        if let response = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) {
            state.withLock { $0.moveError = Downloader.DownloadError.httpStatus(response.statusCode) }
            return
        }
        do {
            let fileManager = FileManager.default
            try? fileManager.removeItem(at: destination)
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.moveItem(at: location, to: destination)
            state.withLock { $0.movedFile = true }
        } catch {
            state.withLock { $0.moveError = error }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let (continuation, moveError, moved) = state.withLock { state in
            defer { state.continuation = nil }
            return (state.continuation, state.moveError, state.movedFile)
        }
        if let error = error ?? moveError {
            let cancelled = (error as? URLError)?.code == .cancelled
            continuation?.resume(throwing: cancelled ? CancellationError() : error)
        } else if moved {
            continuation?.resume()
        } else {
            continuation?.resume(throwing: URLError(.cannotCreateFile))
        }
    }
}

/// SHA-256 of a file, read in chunks so large archives do not have to fit in memory.
public enum FileHasher {
    public static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
