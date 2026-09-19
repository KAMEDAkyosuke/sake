import Foundation
import Testing

@testable import SakeKit

private func temporaryRoot() -> Paths {
    let root = FileManager.default.temporaryDirectory.appending(path: "sake-import-\(UUID().uuidString)")
    return Paths(root: root.appending(path: "support"), cache: root.appending(path: "cache"))
}

private func remove(_ paths: Paths) {
    try? FileManager.default.removeItem(at: paths.root.deletingLastPathComponent())
}

/// What `wineboot --init` leaves in each container, and therefore what is never a candidate.
private let fresh = ["Common Files", "Internet Explorer"]

private func makeDirectory(_ url: URL, containing contents: String) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    try contents.write(to: url.appending(path: "marker.txt"), atomically: true, encoding: .utf8)
}

/// A CrossOver bottle: its marker file, the directories a fresh prefix also has, and
/// whatever `installed` puts on top of them.
private func makeSourceBottle(at url: URL, installed: [String] = []) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    try "[Bottle]\n".write(to: url.appending(path: "cxbottle.conf"), atomically: true, encoding: .utf8)

    let driveC = url.appending(path: "drive_c")
    for container in BottleImporter.containers {
        for entry in fresh {
            try makeDirectory(driveC.appending(path: "\(container)/\(entry)"), containing: "wine's own")
        }
    }
    for entry in installed {
        try makeDirectory(driveC.appending(path: entry), containing: "the user's \(entry)")
    }
}

/// A sake bottle that has been created: the registry wineboot writes, and the containers
/// that come with it.
private func makeDestinationBottle(_ paths: Paths) throws {
    let bottle = Bottle(paths: paths)
    try FileManager.default.createDirectory(at: bottle.url, withIntermediateDirectories: true)
    try Data().write(to: bottle.systemRegistry)
    for container in BottleImporter.containers {
        for entry in fresh {
            try makeDirectory(bottle.driveC.appending(path: "\(container)/\(entry)"), containing: "wine's own")
        }
    }
}

private func collect(_ stream: AsyncStream<ImportEvent>) async -> [ImportEvent] {
    var events: [ImportEvent] = []
    for await event in stream { events.append(event) }
    return events
}

private func failure(in events: [ImportEvent]) -> (reason: String, log: URL?)? {
    events.compactMap { event -> (String, URL?)? in
        if case .failed(let reason, let log) = event { (reason, log) } else { nil }
    }.first
}

private func text(at url: URL) -> String? {
    try? String(contentsOf: url.appending(path: "marker.txt"), encoding: .utf8)
}

private let aGame = ["Program Files (x86)/Battle.net", "Program Files (x86)/Diablo IV",
                     "ProgramData/Battle.net"]

@Test func onlyWhatTheSourceHasOnTopOfAFreshPrefixIsACandidate() throws {
    let paths = temporaryRoot()
    defer { remove(paths) }
    let source = paths.root.appending(path: "crossover/Battle.net Desktop App")
    try makeSourceBottle(at: source, installed: aGame)
    try makeDestinationBottle(paths)

    let importer = BottleImporter(paths: paths, source: CrossOverBottle(url: source))

    // No list of titles anywhere: a fresh prefix already has the rest, so the difference
    // is exactly what the user installed.
    #expect(importer.candidates() == aGame)
}

@Test func neitherWinesOwnFilesNorTheUserProfileAreEverCandidates() throws {
    let paths = temporaryRoot()
    defer { remove(paths) }
    let source = paths.root.appending(path: "crossover/Battle.net Desktop App")
    try makeSourceBottle(at: source)
    try makeDestinationBottle(paths)
    try makeDirectory(source.appending(path: "drive_c/windows/system32"), containing: "crossover's wine")
    try makeDirectory(source.appending(path: "drive_c/users/crossover/Documents"), containing: "a profile")

    // `windows` is CrossOver's own Wine and is not sake's to move — docs/licensing.md. The
    // user profile is a separate decision nobody has made.
    #expect(BottleImporter(paths: paths, source: CrossOverBottle(url: source)).candidates().isEmpty)
}

@Test func eachEntryLandsAtTheSameRelativePath() async throws {
    let paths = temporaryRoot()
    defer { remove(paths) }
    let source = paths.root.appending(path: "crossover/Battle.net Desktop App")
    try makeSourceBottle(at: source, installed: aGame)
    try makeDestinationBottle(paths)

    let importer = BottleImporter(paths: paths, source: CrossOverBottle(url: source))
    let events = await collect(importer.run())

    #expect(failure(in: events) == nil || failure(in: events)?.reason == nil)
    #expect(events.contains(.started(count: 3)))
    for entry in aGame {
        // Battle.net's product.db carries the install path, so the clone has to land where
        // the source had it. See docs/layout.md.
        #expect(text(at: importer.bottle.driveC.appending(path: entry)) == "the user's \(entry)")
    }
}

@Test func whatTheBottleAlreadyHasIsLeftExactlyAsItIs() async throws {
    let paths = temporaryRoot()
    defer { remove(paths) }
    let source = paths.root.appending(path: "crossover/Battle.net Desktop App")
    try makeSourceBottle(at: source, installed: aGame)
    try makeDestinationBottle(paths)

    let importer = BottleImporter(paths: paths, source: CrossOverBottle(url: source))
    let mine = importer.bottle.driveC.appending(path: "ProgramData/Battle.net")
    try makeDirectory(mine, containing: "mine, newer")

    #expect(!importer.candidates().contains("ProgramData/Battle.net"))
    let events = await collect(importer.run())

    // The difference is the only rule about what is copied, so there is no second one that
    // could disagree with it and overwrite something.
    #expect(events.contains(.started(count: 2)))
    #expect(text(at: mine) == "mine, newer")
}

@Test func aSecondImportHasNothingLeftToDo() async throws {
    let paths = temporaryRoot()
    defer { remove(paths) }
    let source = paths.root.appending(path: "crossover/Battle.net Desktop App")
    try makeSourceBottle(at: source, installed: aGame)
    try makeDestinationBottle(paths)

    let importer = BottleImporter(paths: paths, source: CrossOverBottle(url: source))
    _ = await collect(importer.run())
    let second = await collect(importer.run())

    #expect(second == [.nothingToImport, .finished(cloned: 0, bytes: 0)])
}

@Test func halfACloneIsSweptRatherThanMistakenForAFinishedOne() async throws {
    let paths = temporaryRoot()
    defer { remove(paths) }
    let source = paths.root.appending(path: "crossover/Battle.net Desktop App")
    try makeSourceBottle(at: source, installed: aGame)
    try makeDestinationBottle(paths)

    let importer = BottleImporter(paths: paths, source: CrossOverBottle(url: source))
    let partial = importer.bottle.driveC
        .appending(path: "Program Files (x86)/\(BottleImporter.partialPrefix)Diablo IV")
    try makeDirectory(partial, containing: "half a game")

    _ = await collect(importer.run())

    #expect(!FileManager.default.fileExists(atPath: partial.path))
    #expect(
        text(at: importer.bottle.driveC.appending(path: "Program Files (x86)/Diablo IV"))
            == "the user's Program Files (x86)/Diablo IV"
    )
}

@Test func aCloneCannotCrossAVolumeAndTheGuardCanSeeIt() throws {
    let home = FileManager.default.homeDirectoryForCurrentUser

    // Without this the copy silently becomes a real one, and a game is tens of gigabytes.
    // devfs is a different filesystem on any Unix; `/` and the data volume are one st_dev
    // either side of the firmlink, which is why this is not tested with those two.
    #expect(throws: ImportError.self) {
        try BottleImporter.requireOneVolume(source: URL(filePath: "/dev"), destination: home)
    }
    #expect(throws: Never.self) {
        try BottleImporter.requireOneVolume(source: home, destination: home)
    }
}

@Test func onlyARealCrossOverBottleIsOfferedAsASource() throws {
    let paths = temporaryRoot()
    defer { remove(paths) }
    let bottles = paths.root.appending(path: "crossover")
    try makeSourceBottle(at: bottles.appending(path: "Battle.net Desktop App"))
    try makeSourceBottle(at: bottles.appending(path: "Steam"))

    // The Bottles directory holds other things; both markers have to be there.
    try FileManager.default.createDirectory(
        at: bottles.appending(path: "no-drive-c"), withIntermediateDirectories: true
    )
    try "[Bottle]\n".write(
        to: bottles.appending(path: "no-drive-c/cxbottle.conf"), atomically: true, encoding: .utf8
    )
    try FileManager.default.createDirectory(
        at: bottles.appending(path: "not-a-bottle/drive_c"), withIntermediateDirectories: true
    )

    #expect(CrossOverBottle.available(in: bottles).map(\.name) == ["Battle.net Desktop App", "Steam"])
}

@Test func withoutABottleToImportIntoNothingIsCopied() async throws {
    let paths = temporaryRoot()
    defer { remove(paths) }
    let source = paths.root.appending(path: "crossover/Battle.net Desktop App")
    try makeSourceBottle(at: source, installed: aGame)

    let importer = BottleImporter(paths: paths, source: CrossOverBottle(url: source))
    #expect(importer.missingPrerequisite?.contains("Create one first") == true)

    let events = await collect(importer.run())
    #expect(failure(in: events)?.reason.contains("Create one first") == true)
    // Nothing ran, so there is no log to send anyone to.
    #expect(failure(in: events)?.log == nil)
}

@Test func whatWasClonedIsWrittenDown() async throws {
    let paths = temporaryRoot()
    defer { remove(paths) }
    let source = paths.root.appending(path: "crossover/Battle.net Desktop App")
    try makeSourceBottle(at: source, installed: aGame)
    try makeDestinationBottle(paths)

    let importer = BottleImporter(paths: paths, source: CrossOverBottle(url: source))
    let events = await collect(importer.run())

    let log = try String(contentsOf: importer.logURL, encoding: .utf8)
    for entry in aGame { #expect(log.contains("=== cloned \(entry) ")) }
    #expect(events.last.map { if case .finished(let cloned, _) = $0 { cloned == 3 } else { false } } == true)
}
