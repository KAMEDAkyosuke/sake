import Foundation
import Testing

@testable import SakeKit

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "sake-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// A tarball holding `<name>/hello.txt`, plus a second directory to select against.
private func makeArchive(in root: URL, name: String) async throws -> URL {
    let staging = root.appending(path: "staging")
    for directory in [name, "other-1.0"] {
        let tree = staging.appending(path: directory)
        try FileManager.default.createDirectory(at: tree, withIntermediateDirectories: true)
        try "hello".write(to: tree.appending(path: "hello.txt"), atomically: true, encoding: .utf8)
    }

    let archive = root.appending(path: "archive.tar")
    let result = try await ProcessRunner().run(Command(
        executable: URL(filePath: "/usr/bin/tar"),
        arguments: ["-cf", archive.path, "-C", staging.path, name, "other-1.0"]
    ))
    #expect(result.succeeded)
    return archive
}

private func collect(_ stream: AsyncStream<FetchEvent>) async -> [FetchEvent] {
    var events: [FetchEvent] = []
    for await event in stream { events.append(event) }
    return events
}

@Test func unpacksAnArchive() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let archive = try await makeArchive(in: root, name: "thing-1.0")

    let into = root.appending(path: "out")
    try await Unpacker().unpack(archive, into: into)

    #expect(FileManager.default.fileExists(atPath: into.appending(path: "thing-1.0/hello.txt").path))
    #expect(FileManager.default.fileExists(atPath: into.appending(path: "other-1.0/hello.txt").path))
}

@Test func unpacksOnlyTheMembersAskedFor() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let archive = try await makeArchive(in: root, name: "thing-1.0")

    let into = root.appending(path: "out")
    try await Unpacker().unpack(archive, into: into, members: ["thing-1.0"])

    #expect(FileManager.default.fileExists(atPath: into.appending(path: "thing-1.0/hello.txt").path))
    #expect(!FileManager.default.fileExists(atPath: into.appending(path: "other-1.0").path))
}

@Test func unpackingSomethingThatIsNotAnArchiveFails() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let notAnArchive = root.appending(path: "rubbish.tar")
    try "not a tarball".write(to: notAnArchive, atomically: true, encoding: .utf8)

    await #expect(throws: UnpackError.self) {
        try await Unpacker().unpack(notAnArchive, into: root.appending(path: "out"))
    }
}

@Test func hashingMatchesTheSystemTool() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appending(path: "payload")
    try Data(repeating: 0xAB, count: 3 << 20).write(to: file)

    let shasum = try await ProcessRunner().run(Command(
        executable: URL(filePath: "/usr/bin/shasum"),
        arguments: ["-a", "256", file.path]
    ))
    let expected = shasum.standardOutput.split(separator: " ").first.map(String.init)

    #expect(try SourceFetcher.sha256(of: file) == expected)
}

@Test func fetchesVerifiesAndUnpacks() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let archive = try await makeArchive(in: root, name: "thing-1.0")

    let paths = Paths(applicationSupport: root.appending(path: "support"),
                      cache: root.appending(path: "cache"))
    let component = Component(
        id: "thing", version: "1.0", url: archive,
        sha256: try SourceFetcher.sha256(of: archive),
        archive: .tar, destination: .sources, unpacked: "thing-1.0", members: []
    )

    let events = await collect(SourceFetcher(paths: paths).fetch([component]))

    #expect(events.contains(.downloaded(component, verified: true)))
    #expect(events.contains(.unpacked(component)))
    #expect(!events.contains { if case .failed = $0 { true } else { false } })
    #expect(FileManager.default.fileExists(atPath: paths.sources.appending(path: "thing-1.0/hello.txt").path))
    #expect(FileManager.default.fileExists(atPath: paths.downloads.appending(path: "thing-1.0.tar").path))
}

@Test func aWrongHashStopsTheComponentAndSaysSo() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let archive = try await makeArchive(in: root, name: "thing-1.0")

    let paths = Paths(applicationSupport: root.appending(path: "support"),
                      cache: root.appending(path: "cache"))
    let component = Component(
        id: "thing", version: "1.0", url: archive,
        sha256: String(repeating: "0", count: 64),
        archive: .tar, destination: .sources, unpacked: "thing-1.0", members: []
    )

    let events = await collect(SourceFetcher(paths: paths).fetch([component]))

    let failure = events.compactMap { event -> String? in
        if case .failed(_, let reason) = event { reason } else { nil }
    }.first
    #expect(failure?.contains("does not match the hash") == true)
    #expect(!FileManager.default.fileExists(atPath: paths.sources.appending(path: "thing-1.0").path))
}

@Test func whatIsAlreadyUnpackedIsLeftAlone() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let archive = try await makeArchive(in: root, name: "thing-1.0")

    let paths = Paths(applicationSupport: root.appending(path: "support"),
                      cache: root.appending(path: "cache"))
    let component = Component(
        id: "thing", version: "1.0", url: archive,
        sha256: try SourceFetcher.sha256(of: archive),
        archive: .tar, destination: .sources, unpacked: "thing-1.0", members: []
    )
    let fetcher = SourceFetcher(paths: paths)

    _ = await collect(fetcher.fetch([component]))
    let second = await collect(fetcher.fetch([component]))

    #expect(second == [.alreadyInPlace(component), .finished])
}
