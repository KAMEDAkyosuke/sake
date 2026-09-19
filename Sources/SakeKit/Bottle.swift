import Foundation

/// One Wine prefix, and the environment everything in the engine has to be run with.
///
/// The bottle directory *is* the `WINEPREFIX`, and the games live in its `drive_c`. See
/// docs/layout.md.
public struct Bottle: Sendable, Equatable {
    public let paths: Paths
    public let name: String

    public init(paths: Paths = .default, name: String = Bottle.defaultName) {
        self.paths = paths
        self.name = name
    }

    /// Until there is more than one, there is this one.
    public static let defaultName = "default"

    public var url: URL { paths.bottle(named: name) }
    public var engine: URL { paths.engine }

    public var driveC: URL { url.appending(path: "drive_c") }
    public var system32: URL { driveC.appending(path: "windows/system32") }
    public var sysWoW64: URL { driveC.appending(path: "windows/syswow64") }
    public var systemRegistry: URL { url.appending(path: "system.reg") }

    /// The registry rather than the directory: a run that was stopped half way leaves the
    /// directory behind, and a prefix without a registry is not one.
    public var exists: Bool {
        FileManager.default.fileExists(atPath: systemRegistry.path)
    }

    /// What Wine put in the two system directories. `syswow64` empty means WoW64 never
    /// initialised, so no 32-bit application will run -- and Battle.net's launcher is
    /// 32-bit. It is the prototype's one acceptance check on a new prefix.
    public func systemFileCounts() -> (system32: Int, sysWoW64: Int) {
        func count(_ directory: URL) -> Int {
            (try? FileManager.default.contentsOfDirectory(atPath: directory.path))?.count ?? 0
        }
        return (count(system32), count(sysWoW64))
    }

    /// Everything a wine run needs, in one place. Each of these is here because leaving it
    /// out breaks something that does not look related; see docs/runtime.md.
    public func environment(
        inheriting base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var environment = base
        environment["WINEPREFIX"] = url.path
        // Not optional. Without mscoree and mshtml disabled, wineboot puts up the Wine Mono
        // installer and waits for a click that never comes: 0% CPU forever, and syswow64
        // never populated.
        environment["WINEDLLOVERRIDES"] = "mscoree,mshtml=d"
        // Leave this at -all. With err+all a failed dlopen produces a dlerror() string long
        // enough to overflow Wine's debug buffer, and the exception cannot then be
        // dispatched -- so raising the log level turns a handled failure into a crash.
        environment["WINEDEBUG"] = "-all"
        // CodeWeavers' CW Hack 22996, off by default, and the one thing that makes
        // Battle.net's login page load at all.
        environment["WINE_SIMULATE_WRITECOPY"] = "1"
        // Only when the library is really there: Wine looks up Rosetta's
        // register_non_native_code_region only if this points at it, and a variable
        // pointing at nothing would read as "D3DMetal is set up" everywhere downstream.
        if FileManager.default.fileExists(atPath: paths.d3dSharedLibrary.path) {
            environment["CX_APPLEGPTK_LIBD3DSHARED_PATH"] = paths.d3dSharedLibrary.path
        }
        return environment
    }

    /// One of the engine's own binaries, run in this bottle.
    ///
    /// Never translated. Wine's binaries are x86_64 already so Rosetta handles them, and
    /// `arch` is a hardened system binary whose exec strips every `DYLD_*` variable -- so
    /// wrapping a *run* the way the build is wrapped takes the environment away. See
    /// docs/wine-build.md.
    public func command(
        _ program: String,
        _ arguments: [String] = [],
        workingDirectory: URL? = nil,
        inheriting base: [String: String] = ProcessInfo.processInfo.environment
    ) -> Command {
        Command(
            executable: engine.appending(path: "bin/\(program)"),
            arguments: arguments,
            environment: environment(inheriting: base),
            workingDirectory: workingDirectory,
            architecture: .native
        )
    }

    /// Take the bottle down.
    ///
    /// Killing wineserver is what stops a bottle: a game's Agent runs with ppid 1 and
    /// wineserver is a daemon of its own, so terminating what sake started leaves both
    /// running. And `wineserver -k` without `WINEPREFIX` goes after the default `~/.wine`,
    /// kills nothing of yours and exits 0 -- which is why this is a method on the bottle
    /// rather than a command anyone may assemble.
    @discardableResult
    public func stop(runner: ProcessRunner = ProcessRunner()) async throws -> CommandResult {
        try await runner.run(command("wineserver", ["-k"]))
    }
}
