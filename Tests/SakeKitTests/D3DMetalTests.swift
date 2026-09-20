import Foundation
import Testing

@testable import SakeKit

private struct Fixture {
    let paths: Paths
    let volumes: URL
    let root: URL

    var installer: D3DMetalInstaller {
        D3DMetalInstaller(paths: paths, volumes: volumes)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

/// A mounted evaluation-environment volume with the layout Apple's image has, and an engine
/// with a Wine in it.
private func makeFixture(
    redist: Bool = true,
    wine: Bool = true,
    mounted: Bool = true
) throws -> Fixture {
    let manager = FileManager.default
    let root = manager.temporaryDirectory.appending(path: "sake-d3dmetal-\(UUID().uuidString)")
    let paths = Paths(root: root.appending(path: "support"), cache: root.appending(path: "cache"))
    let volumes = root.appending(path: "Volumes")

    try manager.createDirectory(at: volumes, withIntermediateDirectories: true)
    try manager.createDirectory(
        at: volumes.appending(path: GamePortingToolkit.outerVolume.lastPathComponent),
        withIntermediateDirectories: true
    )

    if wine {
        let binary = paths.engine.appending(path: "bin/wine")
        try manager.createDirectory(at: binary.deletingLastPathComponent(), withIntermediateDirectories: true)
        manager.createFile(atPath: binary.path, contents: nil)
        // Wine's own PE half, which Apple's copy replaces.
        try manager.createDirectory(at: paths.engine.appending(path: "lib/wine/x86_64-windows"),
                                    withIntermediateDirectories: true)
        for name in D3DMetalInstaller.appleOwnedDLLs {
            let dll = paths.engine.appending(path: "lib/wine/x86_64-windows/\(name)")
            manager.createFile(atPath: dll.path, contents: Data("vkd3d_create_device".utf8))
        }
    }

    if mounted {
        let volume = volumes.appending(path: "\(GamePortingToolkit.innerVolumePrefix) 4.0 beta 2")
        try manager.createDirectory(at: volume, withIntermediateDirectories: true)
        if redist { try makeRedist(at: volume.appending(path: "redist/lib")) }
    }

    return Fixture(paths: paths, volumes: volumes, root: root)
}

/// `redist/lib` as the image lays it out, symlinks and all.
private func makeRedist(at lib: URL) throws {
    let manager = FileManager.default
    let framework = lib.appending(path: "external/D3DMetal.framework")

    try manager.createDirectory(at: framework.appending(path: "Versions/A"), withIntermediateDirectories: true)
    // The trailing newline is Apple's, and stopping at the NUL alone would keep it.
    try Data("PROGRAM:D3DMetal  PROJECT:D3DMetal-4.0b2\n\0".utf8)
        .write(to: framework.appending(path: "Versions/A/D3DMetal"))
    try manager.createSymbolicLink(
        atPath: framework.appending(path: "Versions/Current").path, withDestinationPath: "A"
    )
    try manager.createSymbolicLink(
        atPath: framework.appending(path: "D3DMetal").path,
        withDestinationPath: "Versions/Current/D3DMetal"
    )

    manager.createFile(
        atPath: lib.appending(path: "external/libd3dshared.dylib").path,
        contents: Data("libd3dshared".utf8)
    )

    for (directory, suffix) in [("x86_64-unix", "so"), ("x86_64-windows", "dll")] {
        let target = lib.appending(path: "wine/\(directory)")
        try manager.createDirectory(at: target, withIntermediateDirectories: true)
        for name in ["d3d10", "d3d11", "d3d12", "dxgi", "nvapi64", "nvngx-on-metalfx"] {
            manager.createFile(
                atPath: target.appending(path: "\(name).\(suffix)").path,
                contents: Data("\(D3DMetalInstaller.appleMarker)/\(name)".utf8)
            )
        }
    }
}

private func collect(_ stream: AsyncStream<D3DMetalEvent>) async -> [D3DMetalEvent] {
    var events: [D3DMetalEvent] = []
    for await event in stream { events.append(event) }
    return events
}

private func failureReason(in events: [D3DMetalEvent]) -> String? {
    events.compactMap { event -> String? in
        if case .failed(let reason) = event { reason } else { nil }
    }.first
}

@Test func theMountedVolumeIsCopiedIntoTheCacheAndThenTheEngine() async throws {
    let fixture = try makeFixture()
    defer { fixture.remove() }

    let events = await collect(fixture.installer.install())

    let phases = events.compactMap { event -> D3DMetalPhase? in
        if case .phase(let phase) = event { phase } else { nil }
    }
    #expect(phases == [.mount, .import, .install, .colocate, .verify])
    #expect(fixture.installer.isImported)
    #expect(fixture.installer.isInstalled)
    #expect(failureReason(in: events) == nil)
}

@Test func theFrameworksSymlinksArriveAsSymlinks() async throws {
    let fixture = try makeFixture()
    defer { fixture.remove() }

    _ = await collect(fixture.installer.install())

    // Copied whole rather than walked into: `Versions/Current` has to stay a link, or
    // `D3DMetal.framework/D3DMetal` resolves to nothing.
    let framework = fixture.paths.d3dMetalFramework
    let manager = FileManager.default
    #expect(try manager.destinationOfSymbolicLink(atPath: framework.appending(path: "Versions/Current").path) == "A")
    #expect(try manager.destinationOfSymbolicLink(atPath: framework.appending(path: "D3DMetal").path)
        == "Versions/Current/D3DMetal")
    #expect(manager.fileExists(atPath: framework.appending(path: "D3DMetal").path))
}

@Test func libd3dsharedAndTheFrameworkEndUpBesideTheSoFilesThatLoadThem() async throws {
    let fixture = try makeFixture()
    defer { fixture.remove() }

    _ = await collect(fixture.installer.install())

    let unix = fixture.paths.wineUnixLibraries
    let manager = FileManager.default
    // d3d12.so looks for libd3dshared beside itself, and libd3dshared then resolves the
    // framework from its own directory. See docs/runtime.md.
    #expect(manager.fileExists(atPath: unix.appending(path: "libd3dshared.dylib").path))
    #expect(try manager.destinationOfSymbolicLink(atPath: unix.appending(path: "D3DMetal.framework").path)
        == "../../external/D3DMetal.framework")
    #expect(manager.fileExists(atPath: unix.appending(path: "D3DMetal.framework/D3DMetal").path))
}

@Test func applesPEHalfReplacesWinesOwn() async throws {
    let fixture = try makeFixture()
    defer { fixture.remove() }

    _ = await collect(fixture.installer.install())

    let windows = fixture.paths.engine.appending(path: "lib/wine/x86_64-windows")
    for name in D3DMetalInstaller.appleOwnedDLLs {
        let text = try String(contentsOf: windows.appending(path: name), encoding: .utf8)
        #expect(text.contains(D3DMetalInstaller.appleMarker), "\(name) is still Wine's")
    }
}

@Test func theVersionComesOutOfTheFramework() async throws {
    let fixture = try makeFixture()
    defer { fixture.remove() }

    _ = await collect(fixture.installer.install())

    #expect(fixture.installer.installedVersion() == "D3DMetal-4.0b2")
}

@Test func onceImportedTheToolkitIsNotNeededAgain() async throws {
    let fixture = try makeFixture()
    defer { fixture.remove() }
    _ = await collect(fixture.installer.install())

    // An engine with no lib at all and the image unmounted: what this is about is that the
    // cached copy is enough on its own. What a rebuild really leaves is narrower, and has
    // its own test below.
    try FileManager.default.removeItem(at: fixture.paths.engine.appending(path: "lib"))
    try FileManager.default.removeItem(
        at: fixture.volumes.appending(path: "\(GamePortingToolkit.innerVolumePrefix) 4.0 beta 2")
    )
    #expect(!fixture.installer.isInstalled)
    #expect(fixture.installer.missingPrerequisite == nil)

    let events = await collect(fixture.installer.install())

    let phases = events.compactMap { event -> D3DMetalPhase? in
        if case .phase(let phase) = event { phase } else { nil }
    }
    #expect(phases == [.install, .colocate, .verify])
    #expect(fixture.installer.isInstalled)
}

@Test func aWineRebuildUndoesTheInstallWithoutTouchingTheFramework() async throws {
    let fixture = try makeFixture()
    defer { fixture.remove() }
    _ = await collect(fixture.installer.install())
    #expect(fixture.installer.isInstalled)

    // Exactly what `make install` does, and nothing else: the framework stays where it is.
    // Checked for on its own it reads as a finished step, on an engine that cannot run a
    // DX12 game -- which is what happened on a real rebuild on 2026-09-19.
    for name in D3DMetalInstaller.appleOwnedDLLs {
        let dll = fixture.paths.engine.appending(path: "lib/wine/x86_64-windows/\(name)")
        try Data("vkd3d_create_device".utf8).write(to: dll)
    }

    #expect(FileManager.default.fileExists(atPath: fixture.paths.d3dMetalFramework.path))
    #expect(!fixture.installer.isInstalled)

    _ = await collect(fixture.installer.install())
    #expect(fixture.installer.isInstalled)
}

@Test func whatIsAlreadyInstalledIsNotInstalledAgain() async throws {
    let fixture = try makeFixture()
    defer { fixture.remove() }

    _ = await collect(fixture.installer.install())
    let second = await collect(fixture.installer.install())

    #expect(second == [.alreadyInstalled(version: "D3DMetal-4.0b2"), .finished])
}

@Test func withoutAWineThereIsNothingToInstallInto() async throws {
    let fixture = try makeFixture(wine: false)
    defer { fixture.remove() }

    #expect(fixture.installer.missingPrerequisite?.contains("Build Wine first") == true)
    #expect(failureReason(in: await collect(fixture.installer.install()))?.contains("Wine") == true)
}

@Test func withoutTheToolkitTheUserIsSentToAppleAndNowhereElse() async throws {
    let fixture = try makeFixture(mounted: false)
    defer { fixture.remove() }

    let reason = fixture.installer.missingPrerequisite
    #expect(reason?.contains(GamePortingToolkit.downloadPage) == true)
    // The two things sake may not do, said out loud rather than left to the reader.
    #expect(reason?.contains("download") == true)
    #expect(reason?.contains("CrossOver") == true)
}

@Test func aVolumeWithoutRedistSaysTheLayoutIsWrongRatherThanFailingQuietly() async throws {
    let fixture = try makeFixture(redist: false)
    defer { fixture.remove() }

    let reason = failureReason(in: await collect(fixture.installer.install()))

    #expect(reason?.contains("redist/lib") == true)
    #expect(!fixture.installer.isInstalled)
}
