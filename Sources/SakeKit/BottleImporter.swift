import Foundation

/// A bottle CrossOver made, as somewhere to import a game out of.
public struct CrossOverBottle: Sendable, Equatable, Hashable, Identifiable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public var id: String { url.path }
    public var name: String { url.lastPathComponent }
    public var driveC: URL { url.appending(path: "drive_c") }

    public static var bottlesDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/CrossOver/Bottles")
    }

    /// Both markers are checked, because the Bottles directory holds other things too.
    public static func available(in directory: URL = CrossOverBottle.bottlesDirectory) -> [CrossOverBottle] {
        let manager = FileManager.default
        let entries = (try? manager.contentsOfDirectory(atPath: directory.path)) ?? []
        return entries.sorted()
            .map { CrossOverBottle(url: directory.appending(path: $0)) }
            .filter {
                manager.fileExists(atPath: $0.url.appending(path: "cxbottle.conf").path)
                    && manager.fileExists(atPath: $0.driveC.path)
            }
    }
}

public enum ImportEvent: Sendable, Equatable {
    case nothingToImport
    case started(count: Int)
    case cloning(String)
    case cloned(String, bytes: Int64)
    case failed(reason: String, log: URL?)
    case finished(cloned: Int, bytes: Int64)
}

public enum ImportError: Error, Equatable, LocalizedError {
    case notReady(String)
    case differentVolumes(source: String, destination: String)
    case cloneFailed(path: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .notReady(let what):
            what
        case .differentVolumes(let source, let destination):
            """
            \(source) and \(destination) are on different volumes. A clone cannot cross \
            one, so this would be a real copy of the whole game rather than something that \
            costs nothing — tens of gigabytes either way you have them.
            """
        case .cloneFailed(let path, let reason):
            "\(path) could not be cloned: \(reason)"
        }
    }

    /// Both of the first two are decided before anything is copied.
    var cameFromARun: Bool {
        if case .cloneFailed = self { true } else { false }
    }
}

/// Brings a game that is already installed in a CrossOver bottle into one of sake's, by
/// cloning it rather than copying it.
///
/// What comes across is decided by difference: a fresh prefix already has Wine's own
/// `Common Files`, `Internet Explorer` and the rest, so whatever the source has on top of
/// that is what the user installed. No list of titles is needed, and there is none.
public struct BottleImporter: Sendable {
    private let paths: Paths
    public let bottle: Bottle
    public let source: CrossOverBottle

    public init(paths: Paths = .default, name: String = Bottle.defaultName, source: CrossOverBottle) {
        self.paths = paths
        self.bottle = Bottle(paths: paths, name: name)
        self.source = source
    }

    /// The three places a Windows application installs into.
    ///
    /// `windows` is deliberately absent and must stay absent: that is CrossOver's own Wine,
    /// which is theirs and not sake's to move — see docs/licensing.md. `users` is absent
    /// too, for a weaker reason: the prototype never brought a user profile across and
    /// Battle.net rebuilt its own, so carrying one is a separate decision nobody has made.
    public static let containers = ["Program Files", "Program Files (x86)", "ProgramData"]

    /// A clone that was interrupted must not be mistaken for a finished one, so each entry
    /// lands under this name and is renamed only once it is whole.
    static let partialPrefix = ".sake-importing-"

    public var logURL: URL { paths.build.appending(path: "import-\(bottle.name).log") }

    public var missingPrerequisite: String? {
        guard bottle.exists else {
            return "There is no bottle to import into yet. Create one first."
        }
        guard FileManager.default.fileExists(atPath: source.driveC.path) else {
            return "\(source.name) has no drive_c, so there is nothing in it to import."
        }
        return nil
    }

    /// What the source has that this bottle does not.
    public func candidates() -> [String] {
        var found: [String] = []
        for container in Self.containers {
            let ours = Set(contents(of: bottle.driveC.appending(path: container)))
            for entry in contents(of: source.driveC.appending(path: container))
            where !ours.contains(entry) && !entry.hasPrefix(Self.partialPrefix) {
                found.append("\(container)/\(entry)")
            }
        }
        return found
    }

    /// `nil` takes everything ``candidates()`` found. A list takes only what is in both,
    /// so a caller cannot name a path of its own and have it joined onto `drive_c`.
    public func run(_ entries: [String]? = nil) -> AsyncStream<ImportEvent> {
        AsyncStream { continuation in
            let work = Task {
                var done = 0
                var bytes: Int64 = 0
                do {
                    (done, bytes) = try clone(entries) { continuation.yield($0) }
                } catch {
                    if !Task.isCancelled {
                        let fromARun = (error as? ImportError)?.cameFromARun ?? true
                        continuation.yield(.failed(
                            reason: error.localizedDescription,
                            log: fromARun ? logURL : nil
                        ))
                    }
                }
                continuation.yield(.finished(cloned: done, bytes: bytes))
                continuation.finish()
            }
            continuation.onTermination = { _ in work.cancel() }
        }
    }

    private func clone(
        _ wanted: [String]?,
        onEvent: @Sendable (ImportEvent) -> Void
    ) throws -> (cloned: Int, bytes: Int64) {
        if let missing = missingPrerequisite { throw ImportError.notReady(missing) }
        try Self.requireOneVolume(source: source.driveC, destination: bottle.url)
        sweepPartials()

        let entries = wanted.map { chosen in candidates().filter(Set(chosen).contains) }
            ?? candidates()
        guard !entries.isEmpty else {
            onEvent(.nothingToImport)
            return (0, 0)
        }
        onEvent(.started(count: entries.count))

        try FileManager.default.createDirectory(at: paths.build, withIntermediateDirectories: true)
        let log = try LogFile(at: logURL)
        defer { log.close() }

        var done = 0
        var total: Int64 = 0
        for entry in entries {
            try Task.checkCancellation()

            onEvent(.cloning(entry))
            let bytes = try cloneOne(entry, to: bottle.driveC.appending(path: entry))
            log.write("=== cloned \(entry) \(bytes) bytes\n")
            onEvent(.cloned(entry, bytes: bytes))
            done += 1
            total += bytes
        }
        return (done, total)
    }

    /// Clone beside the final name and rename, so a cancelled run leaves nothing rather
    /// than half a game that the next run would skip as already there.
    private func cloneOne(_ entry: String, to destination: URL) throws -> Int64 {
        let manager = FileManager.default
        let partial = destination
            .deletingLastPathComponent()
            .appending(path: Self.partialPrefix + destination.lastPathComponent)

        try? manager.removeItem(at: partial)
        try manager.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        do {
            // Not `cp -c` in a subprocess: measured on 2026-09-19, `copyItem` clones on
            // APFS by itself. See docs/layout.md.
            try manager.copyItem(at: source.driveC.appending(path: entry), to: partial)
            try manager.moveItem(at: partial, to: destination)
        } catch {
            try? manager.removeItem(at: partial)
            throw ImportError.cloneFailed(path: entry, reason: error.localizedDescription)
        }
        return size(of: destination)
    }

    /// A clone cannot cross a volume, and `copyItem` does not say so — it quietly copies
    /// instead, which for a game is tens of gigabytes nobody asked to spend.
    ///
    /// `st_dev`, which is the same on either side of the system/data firmlink and differs
    /// for anything genuinely separate: an external disk, a mounted image, a network share.
    static func requireOneVolume(source: URL, destination: URL) throws {
        func volume(of url: URL) -> NSNumber? {
            (try? FileManager.default.attributesOfItem(atPath: url.path))?[.systemNumber]
                as? NSNumber
        }
        guard volume(of: source) == volume(of: destination) else {
            throw ImportError.differentVolumes(source: source.path, destination: destination.path)
        }
    }

    /// What a run that died rather than was cancelled would have left behind.
    private func sweepPartials() {
        for container in Self.containers {
            let directory = bottle.driveC.appending(path: container)
            for entry in contents(of: directory) where entry.hasPrefix(Self.partialPrefix) {
                try? FileManager.default.removeItem(at: directory.appending(path: entry))
            }
        }
    }

    private func contents(of directory: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
    }

    /// What each entry would bring over, for the list the user chooses from.
    ///
    /// Not folded into ``candidates()``, which is a pair of directory listings and stays
    /// that way: this walks the source, and a bottle with a large library in it takes long
    /// enough that a window would wait on it.
    public func sizes(of entries: [String]) async -> [String: Int64] {
        var found: [String: Int64] = [:]
        for entry in entries {
            if Task.isCancelled { break }
            found[entry] = size(of: source.driveC.appending(path: entry))
        }
        return found
    }

    private func size(of url: URL) -> Int64 { DiskUsage.size(of: url) }
}
