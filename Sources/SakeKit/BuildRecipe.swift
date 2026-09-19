import Foundation

public struct BuildRecipe: Sendable, Identifiable, Equatable {
    public struct Symlink: Sendable, Equatable {
        public let link: String
        public let target: String
    }

    public enum Kind: Sendable, Equatable {
        /// `./configure && make && make install`, in the unpacked source tree.
        case autotools(configure: [String])

        /// Nothing to build: files are taken out of the unpacked tree and put in the prefix.
        case place
    }

    public let componentID: String

    /// Relative to the prefix. Its presence is what says this step is already done.
    public let produces: String

    public let kind: Kind
    public let symlink: Symlink?

    /// The `SONAME_LIB*` macro Wine's configure records this library under, for the four
    /// libraries Wine `dlopen`s at runtime. Naming it beside `produces` is what keeps the
    /// file name from being written down a second time in the Wine build.
    public let wineSoname: String?

    /// Whether Wine links or `dlopen`s what this produces. Those have to be x86_64 like
    /// Wine. The build tools that only ever run on this machine are native instead: an
    /// x86_64 one dies the moment it execs an xcode-select shim, because `libxcrun.dylib`
    /// ships arm64 and arm64e only -- and bison execs `/usr/bin/m4`. The prototype had them
    /// x86_64 as a side effect of wrapping the whole build in `arch -x86_64`, not because
    /// anything needed it. Measured in sake on 2026-09-19.
    public let insideWine: Bool

    init(
        componentID: String,
        produces: String,
        kind: Kind,
        symlink: Symlink? = nil,
        wineSoname: String? = nil,
        insideWine: Bool = true
    ) {
        self.componentID = componentID
        self.produces = produces
        self.kind = kind
        self.symlink = symlink
        self.wineSoname = wineSoname
        self.insideWine = insideWine
    }

    public var id: String { componentID }

    /// What `configure` is handed, with the cross-compilation flags added for everything
    /// that ends up inside Wine.
    var configureArguments: [String] {
        guard case .autotools(let arguments) = kind else { return [] }
        return (insideWine ? Self.cross : []) + arguments
    }

    /// What a `@loader_path` soname has to end in: the library's own name, with the
    /// directory it landed in dropped.
    var installedName: String { URL(filePath: produces).lastPathComponent }

    public var component: Component { Component.named(componentID) }

    public func productURL(in prefix: URL) -> URL { prefix.appending(path: produces) }

    public func isBuilt(in prefix: URL) -> Bool {
        FileManager.default.fileExists(atPath: productURL(in: prefix).path)
    }
}

extension Component {
    static func named(_ id: String) -> Component {
        guard let component = all.first(where: { $0.id == id }) else {
            preconditionFailure("no component named \(id)")
        }
        return component
    }
}

extension BuildRecipe {
    /// What everything inside Wine gets. The build cannot be run translated with the
    /// Command Line Tools alone, so the compiler has to be told to target x86_64 out loud;
    /// see docs/wine-build.md. The triplet alone is not enough -- gmp then compiles x86_64
    /// assembly and hands it to an arm64 assembler.
    static let cross = [
        "--host=x86_64-apple-darwin",
        "--build=x86_64-apple-darwin",
        "CC=clang -arch x86_64",
    ]

    /// In build order. `docs/wine-build.md` says why each one is needed and which of these
    /// flags cannot be dropped.
    public static let all: [BuildRecipe] = [
        BuildRecipe(
            componentID: "bison",
            produces: "bin/bison",
            kind: .autotools(configure: []),
            insideWine: false
        ),
        BuildRecipe(
            componentID: "pkgconf",
            produces: "bin/pkgconf",
            kind: .autotools(configure: []),
            // Wine's configure looks for `pkg-config`, which macOS does not ship at all.
            symlink: Symlink(link: "bin/pkg-config", target: "pkgconf"),
            insideWine: false
        ),
        BuildRecipe(
            componentID: "gmp",
            produces: "lib/libgmp.a",
            kind: .autotools(configure: ["--disable-shared", "--enable-static", "--with-pic"])
        ),
        BuildRecipe(
            componentID: "nettle",
            produces: "lib/libnettle.a",
            kind: .autotools(configure: ["--disable-shared", "--enable-static", "--disable-documentation"])
        ),
        BuildRecipe(
            componentID: "libtasn1",
            produces: "lib/libtasn1.a",
            kind: .autotools(configure: ["--disable-shared", "--enable-static", "--disable-doc"])
        ),
        BuildRecipe(
            componentID: "gnutls",
            produces: "lib/libgnutls.30.dylib",
            kind: .autotools(configure: [
                "--enable-shared", "--disable-static", "--with-included-unistring",
                "--without-p11-kit", "--without-idn", "--without-brotli", "--without-zstd",
                "--without-zlib", "--without-tpm", "--without-tpm2",
                "--disable-doc", "--disable-tests", "--disable-tools", "--disable-guile",
                "--disable-libdane", "--disable-cxx", "--disable-nls",
            ]),
            wineSoname: "SONAME_LIBGNUTLS"
        ),
        BuildRecipe(
            componentID: "freetype",
            produces: "lib/libfreetype.6.dylib",
            kind: .autotools(configure: [
                "--enable-shared", "--disable-static",
                "--without-harfbuzz", "--without-brotli", "--without-png", "--without-bzip2",
            ]),
            wineSoname: "SONAME_LIBFREETYPE"
        ),
        BuildRecipe(
            componentID: "sdl2",
            produces: "lib/libSDL2-2.0.0.dylib",
            // Its own defaults apart from --without-x. Wine uses only the joystick and
            // haptic parts, but SDL's --disable-video/--disable-audio combinations are a
            // known way to end up with a build that does not compile.
            kind: .autotools(configure: ["--enable-shared", "--disable-static", "--without-x"]),
            wineSoname: "SONAME_LIBSDL2"
        ),
        BuildRecipe(
            componentID: "moltenvk",
            produces: "lib/libMoltenVK.dylib",
            kind: .place,
            wineSoname: "SONAME_LIBVULKAN"
        ),
    ]
}
