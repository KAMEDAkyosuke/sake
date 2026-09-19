import Foundation

public enum BuildPhase: String, Sendable {
    case configure
    case make
    case install
    case place
}

public enum BuildEvent: Sendable, Equatable {
    case alreadyBuilt(BuildRecipe)
    case started(BuildRecipe)
    case phase(BuildRecipe, BuildPhase)
    case output(BuildRecipe, String)
    case installed(BuildRecipe)
    case failed(BuildRecipe, reason: String, log: URL?)
    case finished
}

public enum BuildError: Error, Equatable, LocalizedError {
    case sourceMissing(component: String, at: String)
    case phaseFailed(component: String, phase: String, status: Int32, log: String)
    case pieceMissing(component: String, piece: String)

    public var errorDescription: String? {
        switch self {
        case .sourceMissing(let component, let at):
            "The source for \(component) is not unpacked at \(at). Download the sources first."
        case .phaseFailed(let component, let phase, let status, let log):
            "\(component) failed during \(phase) (exit \(status)). The full output is in \(log)."
        case .pieceMissing(let component, let piece):
            "\(piece) is not in the unpacked \(component)."
        }
    }
}

public struct PrefixBuilder: Sendable {
    private let paths: Paths
    private let runner: ProcessRunner

    public init(paths: Paths = .default, runner: ProcessRunner = ProcessRunner()) {
        self.paths = paths
        self.runner = runner
    }

    /// One prefix for all of it, the engine. Wine dlopens these dylibs by absolute path at
    /// runtime, so they belong with the product rather than in a cache that may be purged.
    public var prefix: URL { paths.engine }

    public func logURL(for recipe: BuildRecipe) -> URL {
        paths.build.appending(path: "\(recipe.componentID).log")
    }

    public static func environment(
        prefix: URL,
        inheriting base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var environment = base
        let inherited = base["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = "\(prefix.appending(path: "bin").path):\(inherited)"
        environment["PKG_CONFIG_PATH"] = prefix.appending(path: "lib/pkgconfig").path
        environment["CPPFLAGS"] = "-I\(prefix.appending(path: "include").path)"
        environment["LDFLAGS"] = "-L\(prefix.appending(path: "lib").path)"
        return environment
    }

    public func build(_ recipes: [BuildRecipe] = BuildRecipe.all) -> AsyncStream<BuildEvent> {
        AsyncStream { continuation in
            let work = Task {
                for recipe in recipes {
                    if Task.isCancelled { break }

                    if recipe.isBuilt(in: prefix) {
                        continuation.yield(.alreadyBuilt(recipe))
                        continue
                    }

                    continuation.yield(.started(recipe))
                    do {
                        switch recipe.kind {
                        case .autotools(let arguments):
                            try await runAutotools(recipe, configure: arguments) { phase in
                                continuation.yield(.phase(recipe, phase))
                            } onOutput: { line in
                                continuation.yield(.output(recipe, line))
                            }
                        case .place:
                            continuation.yield(.phase(recipe, .place))
                            try place(recipe)
                        }
                        if let symlink = recipe.symlink { try link(symlink) }
                        continuation.yield(.installed(recipe))
                    } catch {
                        if Task.isCancelled { break }
                        continuation.yield(.failed(
                            recipe,
                            reason: error.localizedDescription,
                            log: recipe.kind == .place ? nil : logURL(for: recipe)
                        ))
                    }
                }
                continuation.yield(.finished)
                continuation.finish()
            }
            continuation.onTermination = { _ in work.cancel() }
        }
    }

    private func runAutotools(
        _ recipe: BuildRecipe,
        configure arguments: [String],
        onPhase: @Sendable (BuildPhase) -> Void,
        onOutput: @escaping @Sendable (String) -> Void
    ) async throws {
        let source = recipe.component.unpackedURL(in: paths)
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw BuildError.sourceMissing(component: recipe.componentID, at: source.path)
        }
        try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paths.build, withIntermediateDirectories: true)

        let log = try LogFile(at: logURL(for: recipe))
        defer { log.close() }

        let environment = Self.environment(prefix: prefix)
        let jobs = ProcessInfo.processInfo.activeProcessorCount

        let steps: [(BuildPhase, URL, [String])] = [
            (.configure, source.appending(path: "configure"), ["--prefix=\(prefix.path)"] + arguments),
            (.make, URL(filePath: "/usr/bin/make"), ["-j\(jobs)"]),
            (.install, URL(filePath: "/usr/bin/make"), ["install"]),
        ]

        for (phase, executable, phaseArguments) in steps {
            onPhase(phase)
            log.write("=== \(phase.rawValue) \(executable.path) \(phaseArguments.joined(separator: " "))\n")

            let result = try await runner.run(
                Command(
                    executable: executable,
                    arguments: phaseArguments,
                    environment: environment,
                    workingDirectory: source,
                    // Native, not translated: the Command Line Tools cannot run their own
                    // compiler under `arch -x86_64` at all. The recipes carry the `-arch
                    // x86_64` instead. See docs/wine-build.md.
                    architecture: .native
                )
            ) { line in
                log.write(line.text + "\n")
                onOutput(line.text)
            }

            guard result.succeeded else {
                throw BuildError.phaseFailed(
                    component: recipe.componentID,
                    phase: phase.rawValue,
                    status: result.exitStatus,
                    log: logURL(for: recipe).path
                )
            }
        }
    }

    private func place(_ recipe: BuildRecipe) throws {
        let root = recipe.component.unpackedURL(in: paths)
        guard FileManager.default.fileExists(atPath: root.path) else {
            throw BuildError.sourceMissing(component: recipe.componentID, at: root.path)
        }

        guard let dylib = Self.find(under: root, where: { $0.lastPathComponent == "libMoltenVK.dylib" }) else {
            throw BuildError.pieceMissing(component: recipe.componentID, piece: "libMoltenVK.dylib")
        }
        guard let header = Self.find(under: root, where: { $0.path.hasSuffix("include/vulkan/vulkan.h") }) else {
            throw BuildError.pieceMissing(component: recipe.componentID, piece: "include/vulkan/vulkan.h")
        }

        try FileManager.default.createDirectory(at: prefix.appending(path: "lib"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: prefix.appending(path: "include"), withIntermediateDirectories: true)

        try replace(dylib, with: prefix.appending(path: "lib/libMoltenVK.dylib"))

        // The headers are what wine's configure detects Vulkan with, and what winevulkan is
        // generated against.
        try replace(header.deletingLastPathComponent(), with: prefix.appending(path: "include/vulkan"))
    }

    private func replace(_ source: URL, with destination: URL) throws {
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: source, to: destination)
    }

    private func link(_ symlink: BuildRecipe.Symlink) throws {
        let link = prefix.appending(path: symlink.link)
        try? FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: symlink.target)
    }

    static func find(under root: URL, where matches: (URL) -> Bool) -> URL? {
        guard let entries = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return nil
        }
        for case let entry as URL in entries where matches(entry) {
            return entry
        }
        return nil
    }
}

private final class LogFile: @unchecked Sendable {
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
