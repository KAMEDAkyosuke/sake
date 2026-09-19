import Foundation

public enum BottlePhase: String, Sendable {
    case boot
    case settle
    case verify
    case registry
}

public enum BottleEvent: Sendable, Equatable {
    case alreadyCreated(system32: Int, sysWoW64: Int)
    case started
    case phase(BottlePhase)
    case output(String)
    case created(system32: Int, sysWoW64: Int)
    case failed(reason: String, log: URL?)
    case finished
}

public enum BottleError: Error, Equatable, LocalizedError {
    case notReady(String)
    case phaseFailed(phase: String, status: Int32, log: String)
    case registryMissing(at: String)
    case wow64Empty(at: String)
    case freeTypeUnresolved

    public var errorDescription: String? {
        switch self {
        case .notReady(let what):
            what
        case .phaseFailed(let phase, let status, let log):
            "The bottle failed during \(phase) (exit \(status)). The full output is in \(log)."
        case .registryMissing(let at):
            "wineboot finished without writing \(at), so there is no prefix here."
        case .wow64Empty(let at):
            """
            \(at) is empty, so WoW64 did not initialise and no 32-bit application will \
            run — including Battle.net's launcher.
            """
        case .freeTypeUnresolved:
            """
            Wine started but could not load FreeType, so the sonames written into config.h \
            do not resolve from where Wine loads them. The engine would have no fonts.
            """
        }
    }

    /// A missing prerequisite is caught before anything runs, so there is no log to point
    /// at and nothing to take down.
    var cameFromARun: Bool {
        if case .notReady = self { false } else { true }
    }
}

/// Creates a bottle, which is the first thing sake does that actually runs what it built.
public struct BottleBuilder: Sendable {
    private let paths: Paths
    private let runner: ProcessRunner
    public let bottle: Bottle

    public init(
        paths: Paths = .default,
        name: String = Bottle.defaultName,
        runner: ProcessRunner = ProcessRunner()
    ) {
        self.paths = paths
        self.runner = runner
        self.bottle = Bottle(paths: paths, name: name)
    }

    public var logURL: URL { paths.build.appending(path: "bottle-\(bottle.name).log") }

    public var missingPrerequisite: String? {
        guard FileManager.default.fileExists(atPath: paths.engine.appending(path: "bin/wine").path)
        else {
            return "There is no Wine to make a bottle with yet. Build Wine first."
        }
        return nil
    }

    /// Set before anything has had a chance to crash. Otherwise a crash spawns
    /// `winedbg --auto`, which puts up a dialog and holds the process until somebody
    /// clicks Close -- an unattended run simply blocks -- and resets `WINEDEBUG` on its
    /// way, so suppressed logging comes roaring back into whatever was being debugged.
    static let crashDialogOff = [
        "reg", "add", #"HKCU\Software\Wine\WineDbg"#,
        "/v", "ShowCrashDialog", "/t", "REG_DWORD", "/d", "0", "/f",
    ]

    /// `WINE_MESSAGE` ignores `WINEDEBUG`, so this line survives the `-all` every run is
    /// made with. It is the one cheap window onto whether the `@loader_path` sonames
    /// resolve for a Wine that is actually running: `win32u` prints it when its
    /// `dlopen(SONAME_LIBFREETYPE)` fails. See docs/layout.md.
    static let freeTypeMissing = "Wine cannot find the FreeType font library"

    public func create() -> AsyncStream<BottleEvent> {
        AsyncStream { continuation in
            let work = Task {
                if bottle.exists {
                    let counts = bottle.systemFileCounts()
                    continuation.yield(
                        .alreadyCreated(system32: counts.system32, sysWoW64: counts.sysWoW64)
                    )
                } else {
                    continuation.yield(.started)
                    do {
                        try await run { continuation.yield(.phase($0)) } onOutput: {
                            continuation.yield(.output($0))
                        }
                        let counts = bottle.systemFileCounts()
                        continuation.yield(
                            .created(system32: counts.system32, sysWoW64: counts.sysWoW64)
                        )
                    } catch {
                        let fromARun = (error as? BottleError)?.cameFromARun ?? true
                        if fromARun { await takeDown() }
                        if !Task.isCancelled {
                            continuation.yield(.failed(
                                reason: error.localizedDescription,
                                log: fromARun ? logURL : nil
                            ))
                        }
                    }
                }
                continuation.yield(.finished)
                continuation.finish()
            }
            continuation.onTermination = { _ in work.cancel() }
        }
    }

    private func run(
        onPhase: @Sendable (BottlePhase) -> Void,
        onOutput: @escaping @Sendable (String) -> Void
    ) async throws {
        if let missing = missingPrerequisite { throw BottleError.notReady(missing) }

        try FileManager.default.createDirectory(at: bottle.url, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paths.build, withIntermediateDirectories: true)

        let log = try LogFile(at: logURL)
        defer { log.close() }

        onPhase(.boot)
        let boot = try await runPhase(
            .boot, bottle.command("wine", ["wineboot", "--init"]), log: log, onOutput: onOutput
        )

        // Wine's own processes outlive the command that started them, so this is where the
        // prefix is finished rather than where wineboot returned.
        onPhase(.settle)
        _ = try await runPhase(
            .settle, bottle.command("wineserver", ["-w"]), log: log, onOutput: onOutput
        )

        onPhase(.verify)
        try verify(boot: boot, log: log)

        onPhase(.registry)
        _ = try await runPhase(
            .registry, bottle.command("wine", Self.crashDialogOff), log: log, onOutput: onOutput
        )
    }

    @discardableResult
    private func runPhase(
        _ phase: BottlePhase,
        _ command: Command,
        log: LogFile,
        onOutput: @escaping @Sendable (String) -> Void
    ) async throws -> CommandResult {
        log.write("=== \(phase.rawValue) \(command.executable.path) \(command.arguments.joined(separator: " "))\n")

        let result = try await runner.run(command) { line in
            log.write(line.text + "\n")
            onOutput(line.text)
        }

        guard result.succeeded else {
            throw BottleError.phaseFailed(
                phase: phase.rawValue, status: result.exitStatus, log: logURL.path
            )
        }
        return result
    }

    private func verify(boot: CommandResult, log: LogFile) throws {
        guard bottle.exists else {
            throw BottleError.registryMissing(at: bottle.systemRegistry.path)
        }

        let counts = bottle.systemFileCounts()
        guard counts.sysWoW64 > 0 else { throw BottleError.wow64Empty(at: bottle.sysWoW64.path) }
        log.write("=== verify system32 \(counts.system32) / syswow64 \(counts.sysWoW64) files\n")

        let output = boot.standardOutput + boot.standardError
        guard !output.contains(Self.freeTypeMissing) else { throw BottleError.freeTypeUnresolved }
        log.write("=== verify Wine loaded FreeType from the engine\n")
    }

    /// Cancelling sends SIGTERM to `wine`, and wineserver is a daemon of its own that
    /// survives it holding a half-made bottle. The detached task is not decoration: the
    /// task this runs in is already cancelled, and ``ProcessRunner`` refuses to start
    /// anything from a cancelled one.
    private func takeDown() async {
        let bottle = self.bottle
        let runner = self.runner
        await Task.detached { _ = try? await bottle.stop(runner: runner) }.value
    }
}
