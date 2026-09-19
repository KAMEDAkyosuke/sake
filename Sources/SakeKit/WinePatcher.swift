import Foundation

public struct WinePatch: Sendable, Equatable, Identifiable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public var id: String { url.lastPathComponent }

    /// The first line of the file, which is where each patch says what it does.
    public var subject: String {
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        return String(text.prefix(while: { !$0.isNewline }))
    }
}

public enum PatchError: Error, Equatable, LocalizedError {
    case directoryMissing
    case noPatches(directory: String)
    case doesNotApply(patch: String, tree: String)

    public var errorDescription: String? {
        switch self {
        case .directoryMissing:
            """
            This copy of sake is incomplete: it carries no patches, and the Wine it would \
            build could not start a game.
            """
        case .noPatches(let directory):
            "\(directory) holds no patches, and Wine cannot be built without them."
        case .doesNotApply(let patch, let tree):
            """
            \(patch) applies to neither the original nor the patched form of \(tree). \
            These patches are written against CrossOver's sources and have to be rebased \
            when CodeWeavers publish new ones.
            """
        }
    }
}

/// Applies the patches in `patches/` to the unpacked CrossOver tree.
///
/// Zero patches is an error rather than a quiet success: Wine builds, installs and passes
/// every check this repository makes without them, and only fails much later at the thing
/// the patches exist for. See `docs/runtime.md`.
public struct WinePatcher: Sendable {
    public let directory: URL?
    private let runner: ProcessRunner

    public init(directory: URL? = WinePatcher.bundled, runner: ProcessRunner = ProcessRunner()) {
        self.directory = directory
        self.runner = runner
    }

    /// `patches/` inside the running app. Not a SwiftPM resource bundle: the patches are
    /// their own licence, and burying them in `Sources/` to satisfy `Bundle.module` would
    /// hide that. `scripts/build-app.sh` copies the directory in.
    public static var bundled: URL? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let directory = resources.appending(path: "patches")
        guard FileManager.default.fileExists(atPath: directory.path) else { return nil }
        return directory
    }

    public func patches() throws -> [WinePatch] {
        guard let directory else { throw PatchError.directoryMissing }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []
        let patches = files
            .filter { $0.pathExtension == "patch" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map(WinePatch.init)
        guard !patches.isEmpty else { throw PatchError.noPatches(directory: directory.path) }
        return patches
    }

    /// Apply every patch to `tree`, skipping the ones already in it.
    ///
    /// Whether a patch is already applied is asked of `patch` itself -- if it reverses
    /// cleanly it is in -- rather than recorded in a marker file, which would have to be
    /// invalidated by hand every time a patch here changed.
    public func apply(
        to tree: URL,
        onOutput: @Sendable (String) -> Void = { _ in }
    ) async throws {
        for patch in try patches() {
            if try await runs(patch, on: tree, reversed: true, dryRun: true) {
                onOutput("already applied: \(patch.id)")
            } else if try await runs(patch, on: tree, reversed: false, dryRun: true) {
                _ = try await runs(patch, on: tree, reversed: false, dryRun: false)
                onOutput("applied: \(patch.id)")
            } else {
                throw PatchError.doesNotApply(patch: patch.id, tree: tree.path)
            }
        }
    }

    private func runs(
        _ patch: WinePatch, on tree: URL, reversed: Bool, dryRun: Bool
    ) async throws -> Bool {
        var arguments = ["-d", tree.path, "-p1", "-s", "-i", patch.url.path]
        // --force so that a reversed patch is reported in the exit status instead of
        // stopping to ask, which would hang a build with no terminal to answer it.
        if reversed { arguments += ["-R", "--force"] }
        if dryRun { arguments.append("--dry-run") }

        let result = try await runner.run(Command(
            executable: URL(filePath: "/usr/bin/patch"), arguments: arguments
        ))
        return result.succeeded
    }
}
