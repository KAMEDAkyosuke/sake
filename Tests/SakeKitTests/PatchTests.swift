import Foundation
import Testing

@testable import SakeKit

/// The repository's own `patches/`. The app finds them in its bundle, which a test bundle
/// is not, so they are found from this file instead.
private let repositoryPatches = URL(filePath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appending(path: "patches")

private func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "sake-patch-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// A tree with one file in it, and a patch that changes that file.
private func makeTree(in root: URL, content: String = "one\ntwo\nthree\n") throws -> (tree: URL, patches: URL) {
    let tree = root.appending(path: "tree")
    let file = tree.appending(path: "dlls/ntdll/unix/loader.c")
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try content.write(to: file, atomically: true, encoding: .utf8)

    let patches = root.appending(path: "patches")
    try FileManager.default.createDirectory(at: patches, withIntermediateDirectories: true)
    try """
        Say what it does here, the way the real ones do.

        --- a/dlls/ntdll/unix/loader.c
        +++ b/dlls/ntdll/unix/loader.c
        @@ -1,3 +1,4 @@
         one
         two
        +patched
         three

        """.write(to: patches.appending(path: "0001-fake.patch"), atomically: true, encoding: .utf8)

    return (tree, patches)
}

private final class Lines: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var all: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(line)
    }
}

private func read(_ tree: URL) throws -> String {
    try String(contentsOf: tree.appending(path: "dlls/ntdll/unix/loader.c"), encoding: .utf8)
}

@Test func theRepositoryCarriesTheSixPatchesAndSaysTheyAreNotMIT() throws {
    let patcher = WinePatcher(directory: repositoryPatches)
    let patches = try patcher.patches()

    #expect(patches.map(\.id) == [
        "0001-ntdll-libd3dshared-fallback.patch",
        "0002-ntdll-read-BOOLEAN-syscall-arguments-as-the-Windows-ABI-defines-them.patch",
        "0003-winemac-factor-out-MetalViewSwapChain.patch",
        "0004-winemac-cross-process-MetalViewSwapChain-via-CALayerHost.patch",
        "0005-winemac-cross-process-child-window-swapchains.patch",
        "0006-winemac-give-D3DMetal-a-hosted-swapchain-for-a-window-it-does-not-own.patch",
    ])
    // Each one says what it does on its first line, which is where the reasoning starts,
    // and names the module it changes the way a Wine commit does.
    for patch in patches {
        let subject = patch.subject
        #expect(
            subject.hasPrefix("ntdll: ") || subject.hasPrefix("winemac: "),
            "\(patch.id): \(subject)"
        )
    }

    // A patch against Wine is a derivative of Wine, whatever this repository's own licence
    // says. See docs/licensing.md.
    let licence = try String(contentsOf: repositoryPatches.appending(path: "LICENSE"), encoding: .utf8)
    #expect(licence.contains("GNU LESSER GENERAL PUBLIC LICENSE"))
    #expect(licence.contains("Version 2.1"))
}

@Test func nothingOutsideNtdllAndTheMacDriverIsPatched() throws {
    for patch in try WinePatcher(directory: repositoryPatches).patches() {
        let text = try String(contentsOf: patch.url, encoding: .utf8)
        let targets = text.split(separator: "\n")
            .filter { $0.hasPrefix("--- a/") }
            .map { $0.dropFirst("--- a/".count) }

        #expect(!targets.isEmpty, "\(patch.id) patches nothing")
        for target in targets {
            // Widened from ntdll alone on 2026-09-20, as a decision: Steam's client draws
            // in one process and owns its window in another, and the driver that has to
            // carry that across is winemac.drv. docs/runtime.md has the measurement.
            #expect(
                target.hasPrefix("dlls/ntdll/") || target.hasPrefix("dlls/winemac.drv/"),
                "\(patch.id) reaches \(target)"
            )
        }
    }
}

@Test func aPatchIsAppliedOnceAndThenRecognisedAsAlreadyIn() async throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let (tree, patches) = try makeTree(in: root)
    let patcher = WinePatcher(directory: patches)

    let first = Lines()
    try await patcher.apply(to: tree) { first.append($0) }
    #expect(first.all == ["applied: 0001-fake.patch"])
    #expect(try read(tree) == "one\ntwo\npatched\nthree\n")

    // The source tree is unpacked once and never re-extracted, so every later build finds
    // the patches already in. Asking `patch` beats a marker file, which would have to be
    // invalidated by hand whenever a patch here changed.
    let second = Lines()
    try await patcher.apply(to: tree) { second.append($0) }
    #expect(second.all == ["already applied: 0001-fake.patch"])
    #expect(try read(tree) == "one\ntwo\npatched\nthree\n")
}

@Test func aPatchThatFitsNeitherFormIsAnErrorAndLeavesTheTreeAlone() async throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let (tree, patches) = try makeTree(in: root, content: "something\nelse\nentirely\n")

    await #expect(throws: PatchError.doesNotApply(patch: "0001-fake.patch", tree: tree.path)) {
        try await WinePatcher(directory: patches).apply(to: tree)
    }
    #expect(try read(tree) == "something\nelse\nentirely\n")
}

@Test func noPatchesAtAllIsAFailureRatherThanAQuietSuccess() async throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let (tree, patches) = try makeTree(in: root)
    try FileManager.default.removeItem(at: patches.appending(path: "0001-fake.patch"))

    // Wine builds, installs and passes every check this repository makes without them.
    // What it cannot do is start a game, which is a long way from here.
    await #expect(throws: PatchError.noPatches(directory: patches.path)) {
        try await WinePatcher(directory: patches).apply(to: tree)
    }
    await #expect(throws: PatchError.directoryMissing) {
        try await WinePatcher(directory: nil).apply(to: tree)
    }
}
