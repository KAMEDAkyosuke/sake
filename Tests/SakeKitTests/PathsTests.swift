import Foundation
import Testing

@testable import SakeKit

@Test func theLayoutIsTheOneDocumented() {
    let paths = Paths(
        root: URL(filePath: "/tmp/support"),
        cache: URL(filePath: "/tmp/cache")
    )

    #expect(paths.engine.path == "/tmp/support/engine")
    #expect(paths.bottles.path == "/tmp/support/bottles")
    #expect(paths.downloads.path == "/tmp/cache/dl")
    #expect(paths.sources.path == "/tmp/cache/sources")
    #expect(paths.toolchain.path == "/tmp/cache/toolchain")
    #expect(paths.build.path == "/tmp/cache/build")
    #expect(paths.d3dMetalFramework.path == "/tmp/support/engine/lib/external/D3DMetal.framework")
}

@Test func theDefaultRootsAreOutsideTheAppBundleAndFreeOfSpaces() {
    let paths = Paths.default
    let home = FileManager.default.homeDirectoryForCurrentUser.path

    #expect(paths.root.path == "\(home)/Library/Sake")
    #expect(paths.cache.path == "\(home)/Library/Caches/Sake")
    // A space in the engine path breaks every autotools configure. See docs/layout.md.
    #expect(!paths.engine.path.dropFirst(home.count).contains(" "))
}
