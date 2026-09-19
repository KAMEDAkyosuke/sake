import Foundation

/// Where sake keeps things on disk, as `docs/layout.md` specifies it.
///
/// The roots are parameters rather than constants because the engine path is not settled:
/// `~/Library/Application Support/Sake` produces sonames around 92 characters, which sits in
/// the gap between a length known to work (76) and one known to kill the process through
/// Wine's debug buffer (146). Nothing here has measured that.
public struct Paths: Sendable, Equatable {
    public let applicationSupport: URL
    public let cache: URL

    public init(applicationSupport: URL, cache: URL) {
        self.applicationSupport = applicationSupport
        self.cache = cache
    }

    public static var `default`: Paths {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return Paths(
            applicationSupport: home.appending(path: "Library/Application Support/Sake"),
            cache: home.appending(path: "Library/Caches/Sake")
        )
    }

    public var engine: URL { applicationSupport.appending(path: "engine") }
    public var bottles: URL { applicationSupport.appending(path: "bottles") }

    public var downloads: URL { cache.appending(path: "dl") }
    public var sources: URL { cache.appending(path: "sources") }
    public var toolchain: URL { cache.appending(path: "toolchain") }
    public var build: URL { cache.appending(path: "build") }

    /// Apple's redistributable unpacks into the engine here. `libd3dshared.dylib` has to sit
    /// beside the framework rather than beside the `.so` files that load it: it resolves
    /// `@rpath/D3DMetal.framework/D3DMetal` relative to its own location. See docs/runtime.md.
    public var d3dMetalFramework: URL { engine.appending(path: "lib/external/D3DMetal.framework") }
}
