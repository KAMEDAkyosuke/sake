import Foundation

public enum UnpackError: Error, Equatable, LocalizedError {
    case tarFailed(archive: String, status: Int32, message: String)

    public var errorDescription: String? {
        switch self {
        case .tarFailed(let archive, let status, let message):
            let detail = message.isEmpty ? "exit \(status)" : message
            return "Could not unpack \(archive): \(detail)"
        }
    }
}

public struct Unpacker: Sendable {
    private let runner: ProcessRunner

    public init(runner: ProcessRunner = ProcessRunner()) {
        self.runner = runner
    }

    /// Unpack `archive` into `directory`, optionally only the named members.
    public func unpack(_ archive: URL, into directory: URL, members: [String] = []) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // No flag for the compression: tar picks gzip or xz from the content, which is why
        // the archive's own extension never has to be passed through to here.
        let result = try await runner.run(Command(
            executable: URL(filePath: "/usr/bin/tar"),
            arguments: ["-xf", archive.path, "-C", directory.path] + members
        ))

        guard result.succeeded else {
            throw UnpackError.tarFailed(
                archive: archive.lastPathComponent,
                status: result.exitStatus,
                message: result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }
}
