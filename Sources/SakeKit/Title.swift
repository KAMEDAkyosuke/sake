import Foundation

/// What sake has to know to start one game.
///
/// Every field here is something the prototype hard-coded in a shell script. Why each
/// argument is needed is in docs/runtime.md and is not restated beside the value, because
/// a comment next to data is the copy that goes stale.
public struct Title: Sendable, Equatable, Codable, Identifiable {
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

    /// Diablo IV is deliberately not here. Started on its own it comes all the way up and
    /// then fails on "Aurora has rejected the token": the client only hands a token out
    /// after Play has been pressed in the same session, and the Play button needs the
    /// BOOLEAN patch this tree does not carry yet. See docs/runtime.md.
    public static let known = [
        Title(
            id: "battle-net",
            name: "Battle.net",
            executable: "Program Files (x86)/Battle.net/Battle.net.exe",
            arguments: ["--use-gl=angle", "--use-angle=vulkan", "--in-process-gpu"]
        )
    ]

    public static func installed(in bottle: Bottle) -> [Title] {
        known.filter { $0.isInstalled(in: bottle) }
    }
}
