import Foundation
import Testing

@testable import SakeKit

private func temporaryRoot() -> Paths {
    let root = FileManager.default.temporaryDirectory.appending(path: "sake-title-\(UUID().uuidString)")
    return Paths(root: root.appending(path: "support"), cache: root.appending(path: "cache"))
}

private func remove(_ paths: Paths) {
    try? FileManager.default.removeItem(at: paths.root.deletingLastPathComponent())
}

private let battleNet = Title.known[0]

/// An engine whose `wine` and `wineserver` record how they were called, and a bottle with
/// the title installed in it.
private func makeEngineAndBottle(_ paths: Paths, installing title: Title? = battleNet) throws {
    let bin = paths.engine.appending(path: "bin")
    try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)

    let scripts = [
        "wine": """
            #!/bin/sh
            here="$(dirname "$0")"
            echo "$@" >> "$here/wine.args"
            pwd > "$here/wine.cwd"
            printenv WINEPREFIX > "$here/wine.wineprefix"
            echo "the client is up"
            exit 0
            """,
        "wineserver": """
            #!/bin/sh
            here="$(dirname "$0")"
            echo "$@" >> "$here/wineserver.args"
            exit 0
            """,
    ]
    for (name, script) in scripts {
        let url = bin.appending(path: name)
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    let bottle = Bottle(paths: paths)
    try FileManager.default.createDirectory(at: bottle.url, withIntermediateDirectories: true)
    try Data().write(to: bottle.systemRegistry)

    if let title {
        let executable = title.executableURL(in: bottle)
        try FileManager.default.createDirectory(
            at: executable.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data().write(to: executable)
    }
}

private func recorded(_ name: String, in paths: Paths) -> [String] {
    let text = (try? String(contentsOf: paths.engine.appending(path: "bin/\(name)"), encoding: .utf8)) ?? ""
    return text.split(separator: "\n").map(String.init)
}

private func collect(_ stream: AsyncStream<LaunchEvent>) async -> [LaunchEvent] {
    var events: [LaunchEvent] = []
    for await event in stream { events.append(event) }
    return events
}

@Test func aProcessIsTheGameOnlyIfArgv0EndsWithItsName() {
    let engine = "/Users/x/Library/Sake/engine/bin/wine"

    // Each of these came from a real `ps -Ao pid=,args=` shape. The three that must not
    // match are the ones a containment test gets wrong, and two of them cost the prototype
    // a wrong diagnosis. See docs/runtime.md.
    let cases: [(line: String, program: String, isTheGame: Bool)] = [
        ("101 \(engine) Battle.net.exe --use-gl=angle", "Battle.net.exe", true),
        (#"102 \#(engine) C:\Program Files (x86)\Diablo IV\Diablo IV.exe -launch"#, "Diablo IV.exe", true),
        (#"103 \#(engine) start.exe /d C:\Games "Diablo IV.exe""#, "Diablo IV.exe", false),
        (#"104 \#(engine) cmd.exe /c "Diablo IV.exe""#, "Diablo IV.exe", false),
        ("105 \(engine) Battle.net Launcher.exe", "Battle.net.exe", false),
        ("106 \(engine) Agent.exe", "Battle.net.exe", false),
        ("107 \(engine)server", "Battle.net.exe", false),
    ]
    for c in cases {
        #expect(
            TitleLauncher.matches(c.line, program: c.program) == c.isTheGame,
            "\(c.program) against \(c.line)"
        )
    }
}

@Test func onlyTitlesActuallyInTheBottleAreOffered() throws {
    let paths = temporaryRoot()
    defer { remove(paths) }
    try makeEngineAndBottle(paths, installing: nil)

    let bottle = Bottle(paths: paths)
    #expect(Title.installed(in: bottle).isEmpty)

    try makeEngineAndBottle(paths)
    #expect(Title.installed(in: bottle) == [battleNet])
}

@Test func theClientIsStartedFromItsOwnDirectoryWithTheFlagsItNeeds() throws {
    let paths = temporaryRoot()
    defer { remove(paths) }
    try makeEngineAndBottle(paths)

    let command = TitleLauncher(paths: paths, title: battleNet).command()

    // The bare leaf name, from the game's directory: Battle.net resolves things relative
    // to it, and it is what keeps argv[0] apart from the Agent's full Windows path.
    #expect(command.arguments.first == "Battle.net.exe")
    #expect(command.workingDirectory?.lastPathComponent == "Battle.net")
    // Without these the login view is drawn and never shown, and ANGLE finds no GPU at
    // all. See docs/runtime.md.
    #expect(command.arguments.contains("--use-angle=vulkan"))
    #expect(command.arguments.contains("--in-process-gpu"))
    // `arch` would strip every DYLD_* variable, and wine is x86_64 already.
    #expect(command.architecture == .native)
}

@Test func launchingRecordsWhatItStartedAndWhereItRanFrom() async throws {
    let paths = temporaryRoot()
    defer { remove(paths) }
    try makeEngineAndBottle(paths)

    let launcher = TitleLauncher(paths: paths, title: battleNet)
    let events = await collect(launcher.launch())

    #expect(events.contains(.started(battleNet)))
    #expect(events.contains(.output("the client is up")))
    #expect(events.contains(.exited(status: 0)))
    #expect(recorded("wine.cwd", in: paths).first?.hasSuffix("Battle.net") == true)
    #expect(recorded("wine.wineprefix", in: paths) == [Bottle(paths: paths).url.path])

    let log = try String(contentsOf: launcher.logURL, encoding: .utf8)
    #expect(log.contains("=== launch Battle.net.exe --use-gl=angle"))
}

@Test func stoppingKillsWineserverAndThenLooksRatherThanClaims() async throws {
    let paths = temporaryRoot()
    defer { remove(paths) }
    try makeEngineAndBottle(paths)

    let left = await TitleLauncher(paths: paths, title: battleNet).stop()

    // `wineserver -k` exits 0 whether or not it killed anything of yours, which is how the
    // prototype's stop script hid its own bug. The answer is a second look.
    #expect(recorded("wineserver.args", in: paths) == ["-k"])
    #expect(left.isEmpty)
}

@Test func aTitleThatIsNotInTheBottleIsNamedRatherThanRunInto() async throws {
    let paths = temporaryRoot()
    defer { remove(paths) }
    try makeEngineAndBottle(paths, installing: nil)

    let launcher = TitleLauncher(paths: paths, title: battleNet)
    #expect(launcher.missingPrerequisite?.contains("Import it first") == true)

    let events = await collect(launcher.launch())
    let failure = events.compactMap { event -> (String, URL?)? in
        if case .failed(let reason, let log) = event { (reason, log) } else { nil }
    }.first
    #expect(failure?.0.contains("Import it first") == true)
    // Nothing ran, so there is no log to send anyone to.
    #expect(failure?.1 == nil)
}

@Test func aSurvivorSweepSeesTheProcessesARealRunLeaves() {
    let engine = URL(filePath: "/Users/x/Library/Sake/engine")

    // Copied from `ps -Ao pid=,args=` during a real Battle.net run on 2026-09-19. Two of
    // these decide whether "stopped — nothing left running" is true or a lie.
    let table = [
        "94779 start.exe /exec Battle.net.exe --use-gl=angle --use-angle=vulkan",
        "94781 /Users/x/Library/Sake/engine/lib/wine/../../bin/wineserver",
        #"94857 C:\Program Files (x86)\Battle.net\Battle.net.exe --use-gl=angle --in-process-gpu"#,
        #"95346 C:\Program Files (x86)\Battle.net\Battle.net.exe --type=renderer --lang=en-US"#,
        #"94878 C:\windows\system32\explorer.exe /desktop"#,
        "95201 /opt/homebrew/bin/crit _serve --plan-dir /Users/x/.crit/plans/battle-net",
    ]

    let ours = TitleLauncher.ours(in: table, program: "Battle.net.exe", engine: engine)
    let pids = ours.compactMap { $0.split(separator: " ").first.map(String.init) }

    // wineserver spells itself lib/wine/../../bin/wineserver, so matching the tidy
    // engine/bin/wineserver finds nothing and the sweep quietly always succeeds.
    #expect(pids.contains("94781"))
    // The client and its renderer, which are what `wineserver -k` has to take with it.
    #expect(pids.contains("94857"))
    #expect(pids.contains("95346"))
    // Our own `wine` turns a relative name into `start.exe /exec`, so the launcher shim
    // has to drop out or every run looks like it is still going.
    #expect(!pids.contains("94779"))
    #expect(!pids.contains("94878"))
    #expect(!pids.contains("95201"))
}

@Test func aTitleAddedByHandIsKeptInTheBottleAndComesBack() throws {
    let paths = temporaryRoot()
    defer { remove(paths) }
    try makeEngineAndBottle(paths, installing: nil)

    let bottle = Bottle(paths: paths)
    let executable = bottle.driveC.appending(path: "Games/Thing/Thing.exe")
    try FileManager.default.createDirectory(
        at: executable.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try Data().write(to: executable)

    let store = TitleStore(bottle: bottle)
    let title = try store.title(at: executable, named: "Thing", arguments: ["-windowed"])
    try store.add(title)

    // Relative to drive_c, which is what survives the bottle being renamed or moved.
    #expect(title.executable == "Games/Thing/Thing.exe")
    #expect(title.id == "thing")
    #expect(TitleStore(bottle: bottle).load() == [title])
    #expect(Title.installed(in: bottle) == [title])

    // The file is what says whether it is still there; the entry alone is not enough.
    try FileManager.default.removeItem(at: executable)
    #expect(Title.installed(in: bottle).isEmpty)
    #expect(TitleStore(bottle: bottle).load() == [title])

    try store.remove(id: title.id)
    #expect(TitleStore(bottle: bottle).load().isEmpty)
}

@Test func aTitleHasToBeAProgramInsideTheBottle() throws {
    let paths = temporaryRoot()
    defer { remove(paths) }
    try makeEngineAndBottle(paths, installing: nil)

    let bottle = Bottle(paths: paths)
    let store = TitleStore(bottle: bottle)

    // Somewhere on the Mac, which would be started outside the prefix and would not
    // survive the bottle moving.
    let outside = paths.cache.appending(path: "Downloads/Thing.exe")
    try FileManager.default.createDirectory(
        at: outside.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try Data().write(to: outside)
    #expect(throws: TitleStoreError.outsideBottle("Thing.exe")) {
        try store.title(at: outside, named: "Thing")
    }

    let inside = bottle.driveC.appending(path: "Thing.exe")
    try FileManager.default.createDirectory(at: bottle.driveC, withIntermediateDirectories: true)
    try Data().write(to: inside)
    #expect(throws: TitleStoreError.unnamed) {
        try store.title(at: inside, named: "   ")
    }
    #expect(throws: TitleStoreError.notThere(bottle.driveC.appending(path: "Missing.exe").path)) {
        try store.title(at: bottle.driveC.appending(path: "Missing.exe"), named: "Missing")
    }
}

@Test func anAddedTitleNeverTakesAKnownTitlesIdentifier() throws {
    let paths = temporaryRoot()
    defer { remove(paths) }
    try makeEngineAndBottle(paths)

    let bottle = Bottle(paths: paths)
    let store = TitleStore(bottle: bottle)
    let executable = bottle.driveC.appending(path: "Other/Battle.net.exe")
    try FileManager.default.createDirectory(
        at: executable.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try Data().write(to: executable)

    // "Battle.net" slugs to the id the known title already has, and a log file is named
    // after it.
    let title = try store.title(at: executable, named: "Battle.net")
    #expect(title.id == "battle-net-2")

    try store.add(title)
    #expect(Title.installed(in: bottle) == [battleNet, title])
}
