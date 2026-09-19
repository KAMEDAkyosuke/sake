import CryptoKit
import Foundation

public enum FetchEvent: Sendable, Equatable {
    case alreadyInPlace(Component)
    case started(Component)
    case progress(Component, bytes: Int64, total: Int64?)
    case downloaded(Component, verified: Bool)
    case unpacked(Component)
    case failed(Component, reason: String)
    case finished
}

public enum FetchError: Error, Equatable, LocalizedError {
    case hashMismatch(component: String, expected: String, actual: String)
    case httpStatus(component: String, code: Int)

    public var errorDescription: String? {
        switch self {
        case .hashMismatch(let component, let expected, let actual):
            "\(component) does not match the hash sake expects (wanted \(expected.prefix(12))…, got \(actual.prefix(12))…)"
        case .httpStatus(let component, let code):
            "The server answered \(code) for \(component)"
        }
    }
}

public struct SourceFetcher: Sendable {
    private let paths: Paths
    private let session: URLSession
    private let unpacker: Unpacker

    public init(paths: Paths = .default, session: URLSession? = nil, unpacker: Unpacker = Unpacker()) {
        self.paths = paths
        // Not URLSession.shared: this needs a per-task delegate to report progress.
        self.session = session ?? URLSession(configuration: .default)
        self.unpacker = unpacker
    }

    public func fetch(_ components: [Component] = Component.all) -> AsyncStream<FetchEvent> {
        AsyncStream { continuation in
            let work = Task {
                for component in components {
                    if Task.isCancelled { break }

                    if component.isUnpacked(in: paths) {
                        continuation.yield(.alreadyInPlace(component))
                        continue
                    }

                    do {
                        continuation.yield(.started(component))
                        let verified = try await download(component) { bytes, total in
                            continuation.yield(.progress(component, bytes: bytes, total: total))
                        }
                        continuation.yield(.downloaded(component, verified: verified))

                        try await unpacker.unpack(
                            component.archiveURL(in: paths),
                            into: component.destinationURL(in: paths),
                            members: component.members
                        )
                        continuation.yield(.unpacked(component))
                    } catch {
                        if Task.isCancelled { break }
                        continuation.yield(.failed(component, reason: error.localizedDescription))
                    }
                }
                continuation.yield(.finished)
                continuation.finish()
            }
            continuation.onTermination = { _ in work.cancel() }
        }
    }

    /// Returns whether the archive was checked against a known hash.
    private func download(
        _ component: Component,
        onProgress: @escaping @Sendable (Int64, Int64?) -> Void
    ) async throws -> Bool {
        let destination = component.archiveURL(in: paths)
        try FileManager.default.createDirectory(at: paths.downloads, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: destination.path) {
            guard let expected = component.sha256 else { return false }
            if try Self.sha256(of: destination) == expected { return true }
            try FileManager.default.removeItem(at: destination)
        }

        let temporary = try await downloadToTemporaryFile(component, onProgress: onProgress)

        guard let expected = component.sha256 else {
            try FileManager.default.moveItem(at: temporary, to: destination)
            return false
        }
        let actual = try Self.sha256(of: temporary)
        guard actual == expected else {
            try? FileManager.default.removeItem(at: temporary)
            throw FetchError.hashMismatch(component: component.id, expected: expected, actual: actual)
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
        return true
    }

    private func downloadToTemporaryFile(
        _ component: Component,
        onProgress: @escaping @Sendable (Int64, Int64?) -> Void
    ) async throws -> URL {
        let box = DownloadBox()

        // Progress is polled off the task rather than reported by a URLSessionDownloadDelegate:
        // measured 2026-09-19, a download task created with a completion handler never calls
        // its delegate's didWriteData, so a delegate reports nothing at all.
        let reporter = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(150))
                if let (received, expected) = box.bytesSoFar() {
                    onProgress(received, expected)
                }
            }
        }
        defer { reporter.cancel() }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, any Error>) in
                let task = session.downloadTask(with: component.url) { temporary, response, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        continuation.resume(throwing: FetchError.httpStatus(
                            component: component.id, code: http.statusCode
                        ))
                        return
                    }
                    guard let temporary else {
                        continuation.resume(throwing: URLError(.badServerResponse))
                        return
                    }
                    // URLSession deletes its temporary file the moment this returns, so it
                    // has to be moved here and not after an await.
                    let kept = FileManager.default.temporaryDirectory
                        .appending(path: "sake-\(UUID().uuidString)")
                    do {
                        try FileManager.default.moveItem(at: temporary, to: kept)
                        continuation.resume(returning: kept)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
                box.start(task)
            }
        } onCancel: {
            box.cancel()
        }
    }

    static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

private final class DownloadBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionTask?
    private var isCancelled = false

    func start(_ task: URLSessionTask) {
        lock.lock()
        self.task = task
        let cancelledAlready = isCancelled
        lock.unlock()

        if cancelledAlready { task.cancel() } else { task.resume() }
    }

    func bytesSoFar() -> (received: Int64, expected: Int64?)? {
        lock.lock()
        defer { lock.unlock() }

        guard let task else { return nil }
        let expected = task.countOfBytesExpectedToReceive
        return (task.countOfBytesReceived, expected > 0 ? expected : nil)
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let task = task
        lock.unlock()

        task?.cancel()
    }
}
