import Foundation

/// What sake has to know to start one game.
///
/// Every field here is something the prototype hard-coded in a shell script. Why each
/// argument is needed is in docs/runtime.md and is not restated beside the value, because
/// a comment next to data is the copy that goes stale.
public struct Title: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let name: String
    /// Relative to the bottle's `drive_c`.
    public let executable: String
    public let arguments: [String]

    public init(id: String, name: String, executable: String, arguments: [String] = []) {
        self.id = id
        self.name = name
        self.executable = executable
        self.arguments = arguments
    }

    public func executableURL(in bottle: Bottle) -> URL {
        bottle.driveC.appending(path: executable)
    }

    /// What the program is started from. Battle.net resolves things relative to its own
    /// directory, which is why the prototype changed into it before starting anything.
    public func directoryURL(in bottle: Bottle) -> URL {
        executableURL(in: bottle).deletingLastPathComponent()
    }

    /// The leaf name, which is both what is passed as `argv[0]` and what a `ps` line is
    /// matched against.
    public var program: String {
        executable.split(separator: "/").last.map(String.init) ?? executable
    }

    public func isInstalled(in bottle: Bottle) -> Bool {
        FileManager.default.fileExists(atPath: executableURL(in: bottle).path)
    }

    /// What can be started in this bottle: what somebody added to it, filtered by what is
    /// still there.
    ///
    /// sake ships no titles of its own. It knew one game once, which meant a row appeared
    /// for that one and for nothing else; what the row carried -- the Chromium flags -- is
    /// now ``suggestedArguments(for:)``, which answers for any program rather than for one.
    public static func installed(in bottle: Bottle) -> [Title] {
        TitleStore(bottle: bottle).load().filter { $0.isInstalled(in: bottle) }
    }

    /// The flags a Chromium app needs here, or nothing at all.
    ///
    /// `--use-gl=angle --use-angle=vulkan` and `--in-process-gpu` are Chromium's, not
    /// Wine's: they mean something to a CEF app and nothing to a game, which is why they
    /// are not simply put on everything the way the two environment variables in
    /// `Bottle.environment` are. See docs/runtime.md.
    ///
    /// **`libcef.dll` is looked for one directory down as well as beside the program.**
    /// Battle.net's own exe sits in `Battle.net/` and its CEF build in
    /// `Battle.net/Battle.net.<build>/`, so beside-only finds nothing. Measured against a
    /// real install on 2026-09-20.
    public static func suggestedArguments(for executable: URL) -> [String] {
        let chromium = ["--use-gl=angle", "--use-angle=vulkan", "--in-process-gpu"]
        let directory = executable.deletingLastPathComponent()
        let manager = FileManager.default
        if manager.fileExists(atPath: directory.appending(path: "libcef.dll").path) {
            return chromium
        }
        let entries = (try? manager.contentsOfDirectory(atPath: directory.path)) ?? []
        for entry in entries {
            let below = directory.appending(path: entry).appending(path: "libcef.dll")
            if manager.fileExists(atPath: below.path) { return chromium }
        }
        return []
    }
}
