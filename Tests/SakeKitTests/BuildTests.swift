import Foundation
import Testing

@testable import SakeKit

private func temporaryRoot() throws -> Paths {
    let root = FileManager.default.temporaryDirectory.appending(path: "sake-build-\(UUID().uuidString)")
    let paths = Paths(root: root.appending(path: "support"),
                      cache: root.appending(path: "cache"))
    try FileManager.default.createDirectory(at: paths.sources, withIntermediateDirectories: true)
    return paths
}

/// A source tree whose `configure` records what it was handed and whose `make install`
/// produces the file the recipe says it produces.
private func makeFakeSource(for recipe: BuildRecipe, in paths: Paths, configureExit: Int32 = 0) throws {
    let source = recipe.component.unpackedURL(in: paths)
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)

    let configure = """
        #!/bin/sh
        echo "$@" > configure.args
        printenv PATH > configure.path
        printenv CPPFLAGS > configure.cppflags
        for a in "$@"; do
            case "$a" in --prefix=*) printf '%s' "${a#--prefix=}" > prefix ;; esac
        done
        echo "checking whether this is a fake... yes"
        exit \(configureExit)
        """
    let configureURL = source.appending(path: "configure")
    try configure.write(to: configureURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: configureURL.path)

    let produced = recipe.produces
    let directory = produced.lastIndex(of: "/").map { String(produced[..<$0]) } ?? "."
    let makefile = [
        "all:",
        "\t@echo building",
        "install:",
        "\t@mkdir -p $$(cat prefix)/\(directory)",
        "\t@touch $$(cat prefix)/\(produced)",
        "\t@echo installing",
        "",
    ].joined(separator: "\n")
    try makefile.write(to: source.appending(path: "Makefile"), atomically: true, encoding: .utf8)
}

private func collect(_ stream: AsyncStream<BuildEvent>) async -> [BuildEvent] {
    var events: [BuildEvent] = []
    for await event in stream { events.append(event) }
    return events
}

private let pkgconf = BuildRecipe.all.first { $0.componentID == "pkgconf" }!

@Test func everyRecipeNamesARealComponentAndADistinctProduct() {
    let recipes = BuildRecipe.all

    #expect(Set(recipes.map(\.produces)).count == recipes.count)
    for recipe in recipes {
        #expect(Component.all.contains { $0.id == recipe.componentID })
        #expect(!recipe.produces.hasPrefix("/"), "\(recipe.id) escapes the prefix")
        #expect(!recipe.produces.contains(".."), "\(recipe.id) escapes the prefix")
    }
}

@Test func whatGoesInsideWineSaysX86_64OutLoudAndTheBuildToolsDoNot() {
    for recipe in BuildRecipe.all {
        guard case .autotools = recipe.kind else { continue }
        let configure = recipe.configureArguments

        if recipe.insideWine {
            // The build cannot be run translated with the Command Line Tools alone, so the
            // target has to be named instead. See docs/wine-build.md.
            #expect(configure.contains("CC=clang -arch x86_64"), "\(recipe.id) would build arm64")
            #expect(configure.contains("--host=x86_64-apple-darwin"), "\(recipe.id) has no host triplet")
            #expect(configure.contains("--build=x86_64-apple-darwin"), "\(recipe.id) has no build triplet")
        } else {
            // An x86_64 build tool dies the moment it execs an xcode-select shim, because
            // libxcrun.dylib ships arm64 and arm64e only -- and bison execs /usr/bin/m4.
            #expect(!configure.contains("CC=clang -arch x86_64"), "\(recipe.id) is a build tool")
            #expect(!configure.contains { $0.hasPrefix("--host=") }, "\(recipe.id) is a build tool")
        }
    }
}

@Test func onlyTheToolsThatNeverEndUpInsideWineAreBuiltNative() {
    let native = Set(BuildRecipe.all.filter { !$0.insideWine }.map(\.id))

    #expect(native == ["bison", "pkgconf"])
    // Anything Wine dlopens is loaded into an x86_64 process, so it cannot be native.
    for recipe in BuildRecipe.all where recipe.wineSoname != nil {
        #expect(recipe.insideWine, "\(recipe.id) is dlopened by Wine")
    }
}

@Test func theBuildEnvironmentPointsAtThePrefixFirst() {
    let environment = PrefixBuilder.environment(
        prefix: URL(filePath: "/tmp/engine"),
        inheriting: ["PATH": "/usr/bin:/bin", "HOME": "/Users/someone"]
    )

    #expect(environment["PATH"] == "/tmp/engine/bin:/usr/bin:/bin")
    #expect(environment["PKG_CONFIG_PATH"] == "/tmp/engine/lib/pkgconfig")
    #expect(environment["CPPFLAGS"] == "-I/tmp/engine/include")
    #expect(environment["LDFLAGS"] == "-L/tmp/engine/lib")
    #expect(environment["HOME"] == "/Users/someone", "the rest of the environment is kept")
}

@Test func configureMakeAndInstallRunInOrderWithThePrefixHandedIn() async throws {
    let paths = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: paths.cache.deletingLastPathComponent()) }
    try makeFakeSource(for: pkgconf, in: paths)

    let builder = PrefixBuilder(paths: paths)
    let events = await collect(builder.build([pkgconf]))

    let phases = events.compactMap { event -> BuildPhase? in
        if case .phase(_, let phase) = event { phase } else { nil }
    }
    #expect(phases == [.configure, .make, .install])
    #expect(events.contains(.installed(pkgconf)))
    #expect(FileManager.default.fileExists(atPath: builder.prefix.appending(path: "bin/pkgconf").path))

    let source = pkgconf.component.unpackedURL(in: paths)
    let arguments = try String(contentsOf: source.appending(path: "configure.args"), encoding: .utf8)
    #expect(arguments.contains("--prefix=\(builder.prefix.path)"))
    // pkgconf only runs on this machine, so what reaches configure says nothing about x86_64.
    #expect(!arguments.contains("CC=clang -arch x86_64"))

    let path = try String(contentsOf: source.appending(path: "configure.path"), encoding: .utf8)
    #expect(path.hasPrefix(builder.prefix.appending(path: "bin").path + ":"))
    let cppflags = try String(contentsOf: source.appending(path: "configure.cppflags"), encoding: .utf8)
    #expect(cppflags.contains(builder.prefix.appending(path: "include").path))
}

@Test func theSymlinkWineConfigureLooksForIsMade() async throws {
    let paths = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: paths.cache.deletingLastPathComponent()) }
    try makeFakeSource(for: pkgconf, in: paths)

    let builder = PrefixBuilder(paths: paths)
    _ = await collect(builder.build([pkgconf]))

    let link = builder.prefix.appending(path: "bin/pkg-config")
    #expect(FileManager.default.fileExists(atPath: link.path))
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == "pkgconf")
}

@Test func theWholeOutputGoesToALogEvenThoughTheUISeesLines() async throws {
    let paths = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: paths.cache.deletingLastPathComponent()) }
    try makeFakeSource(for: pkgconf, in: paths)

    let builder = PrefixBuilder(paths: paths)
    let events = await collect(builder.build([pkgconf]))

    let log = try String(contentsOf: builder.logURL(for: pkgconf), encoding: .utf8)
    #expect(log.contains("=== configure"))
    #expect(log.contains("checking whether this is a fake... yes"))
    #expect(log.contains("=== install"))
    #expect(events.contains(.output(pkgconf, "checking whether this is a fake... yes")))
}

@Test func aFailedPhaseNamesTheLogRatherThanAnExitStatus() async throws {
    let paths = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: paths.cache.deletingLastPathComponent()) }
    try makeFakeSource(for: pkgconf, in: paths, configureExit: 1)

    let builder = PrefixBuilder(paths: paths)
    let events = await collect(builder.build([pkgconf]))

    let failure = events.compactMap { event -> (String, URL?)? in
        if case .failed(_, let reason, let log) = event { (reason, log) } else { nil }
    }.first
    #expect(failure?.0.contains("failed during configure") == true)
    #expect(failure?.0.contains(builder.logURL(for: pkgconf).path) == true)
    #expect(failure?.1 == builder.logURL(for: pkgconf))
    #expect(!FileManager.default.fileExists(atPath: builder.prefix.appending(path: "bin/pkgconf").path))
}

@Test func whatIsAlreadyBuiltIsNotBuiltAgain() async throws {
    let paths = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: paths.cache.deletingLastPathComponent()) }
    try makeFakeSource(for: pkgconf, in: paths)

    let builder = PrefixBuilder(paths: paths)
    _ = await collect(builder.build([pkgconf]))
    let second = await collect(builder.build([pkgconf]))

    #expect(second == [.alreadyBuilt(pkgconf), .finished])
}

@Test func buildingWithoutTheSourceSaysToDownloadItFirst() async throws {
    let paths = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: paths.cache.deletingLastPathComponent()) }

    let events = await collect(PrefixBuilder(paths: paths).build([pkgconf]))

    let reason = events.compactMap { event -> String? in
        if case .failed(_, let reason, _) = event { reason } else { nil }
    }.first
    #expect(reason?.contains("not unpacked") == true)
}
