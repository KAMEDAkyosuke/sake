import Foundation

/// The whole of a build's output, written as it arrives. The UI only ever sees the last
/// line, so this is the only place a failure can be read back from.
final class LogFile: @unchecked Sendable {
    private let lock = NSLock()
    private let handle: FileHandle

    init(at url: URL) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 0)
    }

    func write(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        lock.lock()
        defer { lock.unlock() }
        try? handle.write(contentsOf: data)
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        try? handle.close()
    }
}
