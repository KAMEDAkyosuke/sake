import Foundation

public struct Requirement: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable, CaseIterable {
        case appleSilicon
        case rosetta
        case commandLineTools
        case gamePortingToolkit
        case diskSpace
    }

    public enum Status: Sendable, Equatable {
        case satisfied(String)
        case actionNeeded(problem: String, remedy: String)

        public var isSatisfied: Bool {
            if case .satisfied = self { true } else { false }
        }
    }

    public let kind: Kind
    public let status: Status

    public var id: Kind { kind }

    public var title: String {
        switch kind {
        case .appleSilicon: "Apple silicon"
        case .rosetta: "Rosetta 2"
        case .commandLineTools: "Command Line Tools"
        case .gamePortingToolkit: "Game Porting Toolkit"
        case .diskSpace: "Disk space"
        }
    }
}

public enum GamePortingToolkit {
    public static let outerVolume = URL(filePath: "/Volumes/Game Porting Toolkit")

    /// Matched as a prefix, never as a whole name: the volume and the nested image both
    /// carry the version, as in "Evaluation environment for Windows games 4.0 beta 2".
    public static let innerVolumePrefix = "Evaluation environment for Windows games"

    public static let downloadPage = "https://developer.apple.com/download/all/"
}

enum Rosetta {
    static let runtimePath = "/Library/Apple/usr/libexec/oah/libRosettaRuntime"
}

/// What sake checks before it offers to build anything.
///
/// There is deliberately no macOS version check. The requirements that decide whether this
/// works are Apple silicon, Rosetta 2 and a D3DMetal the user supplied; refusing on the
/// version alone is what docs/layout.md rules out.
public enum Preflight {
    /// About what the sources, the toolchain and the build output come to; the game needs
    /// its own space on top.
    static let requiredCacheBytes: Int64 = 10 * 1_000_000_000

    public static func run(
        paths: Paths = .default,
        runner: ProcessRunner = ProcessRunner()
    ) async -> [Requirement] {
        let fileManager = FileManager.default
        return [
            .appleSilicon(isARM64: isAppleSilicon()),
            .rosetta(isInstalled: fileManager.fileExists(atPath: Rosetta.runtimePath)),
            .commandLineTools(clangPath: await clangPath(runner: runner)),
            .gamePortingToolkit(
                d3dMetalInstalled: fileManager.fileExists(atPath: paths.d3dMetalFramework.path),
                mountedVolumes: contentsOfDirectory(atPath: "/Volumes"),
                nestedImageNames: contentsOfDirectory(atPath: GamePortingToolkit.outerVolume.path)
            ),
            .diskSpace(availableBytes: availableBytes(forCacheAt: paths.cache)),
        ]
    }

    private static func isAppleSilicon() -> Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 else { return false }
        return value == 1
    }

    private static func clangPath(runner: ProcessRunner) async -> String? {
        let command = Command(
            executable: URL(filePath: "/usr/bin/xcrun"),
            arguments: ["--find", "clang"]
        )
        guard let result = try? await runner.run(command), result.succeeded else { return nil }
        let path = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    private static func contentsOfDirectory(atPath path: String) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
    }

    private static func availableBytes(forCacheAt cache: URL) -> Int64? {
        // Nothing has created the cache directory yet on a fresh install, so ask the
        // nearest ancestor that does exist.
        var directory = cache
        while !FileManager.default.fileExists(atPath: directory.path) {
            let parent = directory.deletingLastPathComponent()
            guard parent.path != directory.path else { return nil }
            directory = parent
        }
        let values = try? directory.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        return values?.volumeAvailableCapacityForImportantUsage
    }
}

extension Requirement {
    static func appleSilicon(isARM64: Bool) -> Requirement {
        guard isARM64 else {
            return Requirement(kind: .appleSilicon, status: .actionNeeded(
                problem: "This Mac is not Apple silicon.",
                remedy: """
                    There is nothing to install. sake builds an x86_64 Wine that runs under \
                    Rosetta 2, and Rosetta 2 only exists on Apple silicon.
                    """
            ))
        }
        return Requirement(kind: .appleSilicon, status: .satisfied("This Mac is Apple silicon."))
    }

    static func rosetta(isInstalled: Bool) -> Requirement {
        guard isInstalled else {
            return Requirement(kind: .rosetta, status: .actionNeeded(
                problem: "Rosetta 2 is not installed. The Wine sake builds is x86_64 and needs it.",
                remedy: """
                    Run `softwareupdate --install-rosetta` and accept Apple's licence. \
                    Agreeing to that licence is yours to do, so sake does not run it for you.
                    """
            ))
        }
        return Requirement(kind: .rosetta, status: .satisfied("Rosetta 2 is installed."))
    }

    static func commandLineTools(clangPath: String?) -> Requirement {
        guard let clangPath, !clangPath.isEmpty else {
            return Requirement(kind: .commandLineTools, status: .actionNeeded(
                problem: "The Xcode Command Line Tools are not usable: `xcrun --find clang` found nothing.",
                remedy: "Run `xcode-select --install`. Xcode itself is not needed."
            ))
        }
        return Requirement(kind: .commandLineTools, status: .satisfied("clang at \(clangPath)"))
    }

    static func gamePortingToolkit(
        d3dMetalInstalled: Bool,
        mountedVolumes: [String],
        nestedImageNames: [String]
    ) -> Requirement {
        if d3dMetalInstalled {
            return Requirement(kind: .gamePortingToolkit, status: .satisfied(
                "D3DMetal is already installed in the engine."
            ))
        }
        if let volume = mountedVolumes.first(where: {
            $0.hasPrefix(GamePortingToolkit.innerVolumePrefix)
        }) {
            return Requirement(kind: .gamePortingToolkit, status: .satisfied("Mounted: \(volume)"))
        }
        if let image = nestedImageNames.first(where: {
            $0.hasPrefix(GamePortingToolkit.innerVolumePrefix) && $0.hasSuffix(".dmg")
        }) {
            return Requirement(kind: .gamePortingToolkit, status: .satisfied("""
                \(image) is on the Game Porting Toolkit volume. sake mounts it when it \
                needs it.
                """
            ))
        }
        return Requirement(kind: .gamePortingToolkit, status: .actionNeeded(
            problem: """
                Apple's Game Porting Toolkit is not mounted. It supplies D3DMetal, which sake \
                may not ship, download on your behalf, or copy out of an installed CrossOver.
                """,
            remedy: """
                Download the Game Porting Toolkit from \(GamePortingToolkit.downloadPage) — a \
                free Apple ID is enough — and open the .dmg. sake mounts the \
                evaluation-environment image inside it itself.
                """
        ))
    }

    static func diskSpace(availableBytes: Int64?) -> Requirement {
        let needed = Preflight.requiredCacheBytes.formatted(.byteCount(style: .file))
        guard let availableBytes else {
            return Requirement(kind: .diskSpace, status: .actionNeeded(
                problem: "The free space on the volume that holds sake's cache could not be read.",
                remedy: "Check that ~/Library/Caches exists and is readable."
            ))
        }
        let free = availableBytes.formatted(.byteCount(style: .file))
        guard availableBytes >= Preflight.requiredCacheBytes else {
            return Requirement(kind: .diskSpace, status: .actionNeeded(
                problem: "\(free) free, and the sources and build output need about \(needed).",
                remedy: "Free up space on the volume that holds ~/Library/Caches."
            ))
        }
        return Requirement(kind: .diskSpace, status: .satisfied(
            "\(free) free; sources and build output need about \(needed), the game more again."
        ))
    }
}
