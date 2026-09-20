import Foundation

public enum D3DMetalPhase: String, Sendable {
    case mount
    case `import`
    case install
    case colocate
    case verify
}

public enum D3DMetalEvent: Sendable, Equatable {
    case alreadyInstalled(version: String?)
    case started
    case phase(D3DMetalPhase)
    case placed(String)
    case installed(version: String?)
    case failed(reason: String)
    case finished
}

public enum D3DMetalError: Error, Equatable, LocalizedError {
    case notReady(String)
    case mountFailed(image: String, message: String)
    case mountedNothing(image: String)
    case unexpectedLayout(volume: String)
    case frameworkUnresolved(at: String)
    case notApplesLibrary(name: String)

    public var errorDescription: String? {
        switch self {
        case .notReady(let what):
            what
        case .mountFailed(let image, let message):
            "\(image) could not be mounted: \(message)"
        case .mountedNothing(let image):
            "\(image) mounted, but no evaluation-environment volume appeared."
        case .unexpectedLayout(let volume):
            """
            \(volume) has no redist/lib. That is the volume sake expected D3DMetal on, so \
            either the toolkit's layout has changed or this is a different image.
            """
        case .frameworkUnresolved(let at):
            "\(at) does not resolve, so Wine's d3d12 would not find D3DMetal."
        case .notApplesLibrary(let name):
            """
            \(name) is still Wine's own rather than Apple's. Wine's `make install` writes \
            these back, so D3DMetal has to go in after it.
            """
        }
    }

    /// A missing prerequisite is caught before anything runs.
    var cameFromARun: Bool {
        if case .notReady = self { false } else { true }
    }
}

/// Puts Apple's D3DMetal into the engine, from an image the user downloaded and mounted
/// themselves.
///
/// sake never ships D3DMetal, never downloads it, and never takes it out of an installed
/// CrossOver — `docs/licensing.md` is binding on all three. What it may do is mount the
/// image the user already has and copy `redist/lib` out of it, which is what this does.
public struct D3DMetalInstaller: Sendable {
    private let paths: Paths
    private let runner: ProcessRunner
    private let volumes: URL

    public init(
        paths: Paths = .default,
        runner: ProcessRunner = ProcessRunner(),
        volumes: URL = URL(filePath: "/Volumes")
    ) {
        self.paths = paths
        self.runner = runner
        self.volumes = volumes
    }

    /// Where `libd3dshared.dylib` and the framework both have to end up, beside the `.so`
    /// files that load them. `d3d12.so` declares `LC_RPATH = @loader_path` and looks for
    /// `libd3dshared.dylib` next to itself; `libd3dshared` then resolves
    /// `@rpath/D3DMetal.framework/D3DMetal` from *its* own directory, so moving one without
    /// the other breaks it. See docs/runtime.md.
    var unixFramework: URL { paths.wineUnixLibraries.appending(path: "D3DMetal.framework") }

    /// What Wine's own `make install` writes back over Apple's. Wine builds no unix-side
    /// `d3d*.so` at all, so only the PE half can be undone — which is why the check is here
    /// and not on the framework.
    static let appleOwnedDLLs = ["d3d10.dll", "d3d11.dll", "d3d12.dll", "dxgi.dll"]

    /// Apple's build stamps its own sources into these; Wine's link against vkd3d instead.
    static let appleMarker = "D3DMetalDLLs"

    public var isImported: Bool {
        FileManager.default.fileExists(atPath: importedFramework.path)
    }

    /// The engine's DX12 stack being Apple's, which is a different question from D3DMetal
    /// having been installed once.
    ///
    /// Wine's `make install` writes all four DLLs back over Apple's and does not touch the
    /// framework, so checking for the framework alone reports a finished step on an engine
    /// that cannot run a DX12 game. Measured in sake on 2026-09-19; see docs/wine-build.md.
    public var isInstalled: Bool {
        FileManager.default.fileExists(atPath: paths.d3dMetalFramework.path)
            && FileManager.default.fileExists(atPath: unixFramework.appending(path: "D3DMetal").path)
            && Self.appleOwnedDLLs.allSatisfy { isApples(windowsDLL(named: $0)) }
    }

    private var windowsDLLs: URL { paths.engine.appending(path: "lib/wine/x86_64-windows") }

    private func windowsDLL(named name: String) -> URL { windowsDLLs.appending(path: name) }

    private func isApples(_ dll: URL) -> Bool {
        guard let data = try? Data(contentsOf: dll, options: .mappedIfSafe) else { return false }
        return data.range(of: Data(Self.appleMarker.utf8)) != nil
    }

    public var missingPrerequisite: String? {
        guard FileManager.default.fileExists(atPath: paths.engine.appending(path: "bin/wine").path) else {
            return "There is no Wine to put D3DMetal into yet. Build Wine first."
        }
        guard isImported || mountedVolume() != nil || nestedImage() != nil else {
            return """
                Apple's Game Porting Toolkit is not mounted. Download it from \
                \(GamePortingToolkit.downloadPage) — a free Apple ID is enough — and open the \
                .dmg. sake mounts the evaluation-environment image inside it itself, but it \
                may not download D3DMetal for you or take it out of an installed CrossOver.
                """
        }
        return nil
    }

    private var importedFramework: URL {
        paths.d3dMetal.appending(path: "external/D3DMetal.framework")
    }

    public func install() -> AsyncStream<D3DMetalEvent> {
        AsyncStream { continuation in
            let work = Task {
                if isInstalled {
                    continuation.yield(.alreadyInstalled(version: installedVersion()))
                } else {
                    continuation.yield(.started)
                    do {
                        try await run { continuation.yield(.phase($0)) } onPlaced: {
                            continuation.yield(.placed($0))
                        }
                        continuation.yield(.installed(version: installedVersion()))
                    } catch {
                        if !Task.isCancelled {
                            continuation.yield(.failed(reason: error.localizedDescription))
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
        onPhase: @Sendable (D3DMetalPhase) -> Void,
        onPlaced: @Sendable (String) -> Void
    ) async throws {
        if let missing = missingPrerequisite { throw D3DMetalError.notReady(missing) }

        if !isImported {
            onPhase(.mount)
            let volume = try await mountedOrMountedNow()

            onPhase(.import)
            let redist = volume.appending(path: "redist/lib")
            guard FileManager.default.fileExists(atPath: redist.path) else {
                throw D3DMetalError.unexpectedLayout(volume: volume.path)
            }
            try merge(redist, into: paths.d3dMetal, onPlaced: { _ in })
        }

        onPhase(.install)
        try merge(paths.d3dMetal, into: paths.engine.appending(path: "lib"), onPlaced: onPlaced)

        onPhase(.colocate)
        try colocate()

        onPhase(.verify)
        try verify()
    }

    private func mountedOrMountedNow() async throws -> URL {
        if let volume = mountedVolume() { return volume }

        guard let image = nestedImage() else {
            throw D3DMetalError.notReady(missingPrerequisite ?? "The toolkit is not mounted.")
        }
        let result = try await runner.run(Command(
            executable: URL(filePath: "/usr/bin/hdiutil"),
            arguments: ["attach", "-nobrowse", "-readonly", image.path]
        ))
        guard result.succeeded else {
            throw D3DMetalError.mountFailed(
                image: image.lastPathComponent,
                message: result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        guard let volume = mountedVolume() else {
            throw D3DMetalError.mountedNothing(image: image.lastPathComponent)
        }
        return volume
    }

    /// Matched as a prefix on both counts: the volume and the image carry the version, as in
    /// "Evaluation environment for Windows games 4.0 beta 2".
    private func mountedVolume() -> URL? {
        contents(of: volumes)
            .first { $0.hasPrefix(GamePortingToolkit.innerVolumePrefix) }
            .map { volumes.appending(path: $0) }
    }

    private func nestedImage() -> URL? {
        let outer = volumes.appending(path: GamePortingToolkit.outerVolume.lastPathComponent)
        return contents(of: outer)
            .first { $0.hasPrefix(GamePortingToolkit.innerVolumePrefix) && $0.hasSuffix(".dmg") }
            .map { outer.appending(path: $0) }
    }

    private func contents(of directory: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
    }

    /// Copy `source` over `destination`, keeping what is already there.
    ///
    /// A `.framework` is copied whole rather than walked into: its `Versions/Current` and
    /// the two links beside it have to land as symlinks, and `copyItem` keeps them.
    private func merge(
        _ source: URL,
        into destination: URL,
        onPlaced: @Sendable (String) -> Void
    ) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: destination, withIntermediateDirectories: true)

        for entry in try manager.contentsOfDirectory(
            at: source, includingPropertiesForKeys: [.isDirectoryKey]
        ).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let target = destination.appending(path: entry.lastPathComponent)
            let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory
            if isDirectory == true, entry.pathExtension != "framework" {
                try merge(entry, into: target, onPlaced: onPlaced)
            } else {
                try? manager.removeItem(at: target)
                try manager.copyItem(at: entry, to: target)
                onPlaced(entry.lastPathComponent)
            }
        }
    }

    private func colocate() throws {
        let manager = FileManager.default
        try manager.createDirectory(at: paths.wineUnixLibraries, withIntermediateDirectories: true)

        let library = paths.wineUnixLibraries.appending(path: "libd3dshared.dylib")
        try? manager.removeItem(at: library)
        try manager.copyItem(at: paths.d3dSharedLibrary, to: library)

        try? manager.removeItem(at: unixFramework)
        try manager.createSymbolicLink(
            atPath: unixFramework.path, withDestinationPath: "../../external/D3DMetal.framework"
        )
    }

    private func verify() throws {
        let binary = unixFramework.appending(path: "D3DMetal")
        guard FileManager.default.fileExists(atPath: binary.path) else {
            throw D3DMetalError.frameworkUnresolved(at: binary.path)
        }

        for name in Self.appleOwnedDLLs where !isApples(windowsDLL(named: name)) {
            throw D3DMetalError.notApplesLibrary(name: name)
        }
    }

    /// What Apple's build stamped into the framework, as in `D3DMetal-4.0b2`.
    public func installedVersion() -> String? {
        let binary = paths.d3dMetalFramework.appending(path: "Versions/A/D3DMetal")
        guard let data = try? Data(contentsOf: binary, options: .mappedIfSafe) else { return nil }

        let marker = Data("PROJECT:D3DMetal-".utf8)
        guard let found = data.range(of: marker) else { return nil }

        // Apple's stamp runs `PROJECT:D3DMetal-4.0b2\n\0`, so stopping at the NUL alone
        // would carry the newline into the UI.
        let tail = data[found.upperBound..<min(found.upperBound + 32, data.endIndex)]
        let version = String(decoding: tail.prefix { $0 > UInt8(ascii: " ") }, as: UTF8.self)
        return version.isEmpty ? nil : "D3DMetal-\(version)"
    }
}
