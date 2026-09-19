import Foundation

public enum LaunchEvent: Sendable, Equatable {
    case started(Title)
    case output(String)
    case exited(status: Int32)
    case failed(reason: String, log: URL?)
    case finished
}

public enum LaunchError: Error, Equatable, LocalizedError {
    case notReady(String)

    public var errorDescription: String? {
        switch self {
        case .notReady(let what): what
        }
    }
}

/// Starts one title in one bottle, and takes the bottle down again.
public struct TitleLauncher: Sendable {
    private let paths: Paths
    private let runner: ProcessRunner
    public let bottle: Bottle
    public let title: Title

    public init(
        paths: Paths = .default,
        name: String = Bottle.defaultName,
        title: Title,
        runner: ProcessRunner = ProcessRunner()
    ) {
        self.paths = paths
        self.runner = runner
        self.bottle = Bottle(paths: paths, name: name)
        self.title = title
    }

    public var logURL: URL { paths.build.appending(path: "title-\(title.id).log") }

    public var missingPrerequisite: String? {
        guard bottle.exists else {
            return "There is no bottle to run it in yet. Create one first."
        }
        guard title.isInstalled(in: bottle) else {
            return "\(title.name) is not in this bottle yet. Import it first."
        }
        return nil
    }

    /// Started from the game's own directory and named by its bare leaf, which is how the
    /// prototype started it and what keeps `argv[0]` distinguishable from the full Windows
    /// path the Battle.net Agent passes.
    public func command() -> Command {
        bottle.command(
            "wine",
            [title.program] + title.arguments,
            workingDirectory: title.directoryURL(in: bottle)
        )
    }

    public func launch() -> AsyncStream<LaunchEvent> {
        AsyncStream { continuation in
            let work = Task {
                do {
                    if let missing = missingPrerequisite { throw LaunchError.notReady(missing) }
                    try FileManager.default.createDirectory(
                        at: paths.build, withIntermediateDirectories: true
                    )
                    let log = try LogFile(at: logURL)
                    defer { log.close() }

                    let command = self.command()
                    log.write("=== launch \(command.arguments.joined(separator: " "))\n")
                    continuation.yield(.started(title))

                    let result = try await runner.run(command) { line in
                        log.write(line.text + "\n")
                        continuation.yield(.output(line.text))
                    }
                    continuation.yield(.exited(status: result.exitStatus))
                } catch {
                    if Task.isCancelled {
                        // Cancelling reaches `wine` and nothing else: the client's CEF
                        // helpers are not in its process group, Agent.exe runs with ppid 1,
                        // and wineserver is a daemon. See docs/runtime.md.
                        await takeDown()
                    } else {
                        continuation.yield(.failed(
                            reason: error.localizedDescription,
                            log: error is LaunchError ? nil : logURL
                        ))
                    }
                }
                continuation.yield(.finished)
                continuation.finish()
            }
            continuation.onTermination = { _ in work.cancel() }
        }
    }

    /// Take the bottle down, then say what is still running rather than claim success.
    ///
    /// The prototype's `stop.sh` only found its own `WINEPREFIX` bug because it re-checked
    /// afterwards instead of trusting `wineserver -k`'s exit status, which is 0 either way.
    @discardableResult
    public func stop() async -> [String] {
        _ = try? await bottle.stop(runner: runner)
        // Killing wineserver does not take its clients down instantly.
        try? await Task.sleep(for: .seconds(1))
        return await survivors()
    }

    /// Every `ps` line that belongs to this bottle: the title's own processes, and
    /// wineserver.
    public func survivors() async -> [String] {
        Self.ours(in: await processTable(), program: title.program, engine: bottle.engine)
    }

    /// wineserver is matched on the engine root and the name rather than on
    /// `engine/bin/wineserver`, because it does not spell itself that way: measured on
    /// 2026-09-19, `ps` shows `<engine>/lib/wine/../../bin/wineserver`. The tidier path
    /// never matches, and a survivor check that never matches reports success.
    static func ours(in lines: [String], program: String, engine: URL) -> [String] {
        lines.filter { line in
            matches(line, program: program)
                || (line.contains(engine.path) && line.contains("wineserver"))
        }
    }

    public func running() async -> [Int32] {
        await processTable()
            .filter { Self.matches($0, program: title.program) }
            .compactMap { Int32($0.split(separator: " ").first ?? "") }
    }

    /// Whether a `ps -Ao pid=,args=` line is the program, by cutting the command line at
    /// its first `.exe` and asking what that ends with.
    ///
    /// Containment instead would also match `cmd.exe`, `start.exe` and any launcher
    /// carrying the name among its own arguments, which handed the prototype the wrong
    /// process twice. Matching the bare name at the front is not enough either: `argv[0]`
    /// is spelled differently depending on how the program was started — a full Windows
    /// path from the Agent, a bare name from here. See docs/runtime.md.
    static func matches(_ line: String, program: String) -> Bool {
        guard let exe = line.range(of: ".exe") else { return false }
        return line[..<exe.upperBound].hasSuffix(program)
    }

    private func processTable() async -> [String] {
        let result = try? await runner.run(Command(
            executable: URL(filePath: "/bin/ps"), arguments: ["-Ao", "pid=,args="]
        ))
        return (result?.standardOutput ?? "")
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// The task this runs in is already cancelled, and ``ProcessRunner`` refuses to start
    /// anything from a cancelled one.
    private func takeDown() async {
        let bottle = self.bottle
        let runner = self.runner
        await Task.detached { _ = try? await bottle.stop(runner: runner) }.value
    }
}
