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

    public var id: String { componentID }

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
    /// Every configure gets these three. The build cannot be run translated with the
    /// Command Line Tools alone, so the compiler has to be told to target x86_64 out loud;
    /// see docs/wine-build.md. The triplet alone is not enough -- gmp then compiles x86_64
    /// assembly and hands it to an arm64 assembler.
    private static let cross = [
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
            kind: .autotools(configure: cross),
            symlink: nil
        ),
        BuildRecipe(
            componentID: "pkgconf",
            produces: "bin/pkgconf",
            kind: .autotools(configure: cross),
            // Wine's configure looks for `pkg-config`, which macOS does not ship at all.
            symlink: Symlink(link: "bin/pkg-config", target: "pkgconf")
        ),
        BuildRecipe(
            componentID: "gmp",
            produces: "lib/libgmp.a",
            kind: .autotools(configure: cross + ["--disable-shared", "--enable-static", "--with-pic"]),
            symlink: nil
        ),
        BuildRecipe(
            componentID: "nettle",
            produces: "lib/libnettle.a",
            kind: .autotools(configure: cross + ["--disable-shared", "--enable-static", "--disable-documentation"]),
            symlink: nil
        ),
        BuildRecipe(
            componentID: "libtasn1",
            produces: "lib/libtasn1.a",
            kind: .autotools(configure: cross + ["--disable-shared", "--enable-static", "--disable-doc"]),
            symlink: nil
        ),
        BuildRecipe(
            componentID: "gnutls",
            produces: "lib/libgnutls.30.dylib",
            kind: .autotools(configure: cross + [
                "--enable-shared", "--disable-static", "--with-included-unistring",
                "--without-p11-kit", "--without-idn", "--without-brotli", "--without-zstd",
                "--without-zlib", "--without-tpm", "--without-tpm2",
                "--disable-doc", "--disable-tests", "--disable-tools", "--disable-guile",
                "--disable-libdane", "--disable-cxx", "--disable-nls",
            ]),
            symlink: nil
        ),
        BuildRecipe(
            componentID: "freetype",
            produces: "lib/libfreetype.6.dylib",
            kind: .autotools(configure: cross + [
                "--enable-shared", "--disable-static",
                "--without-harfbuzz", "--without-brotli", "--without-png", "--without-bzip2",
            ]),
            symlink: nil
        ),
        BuildRecipe(
            componentID: "sdl2",
            produces: "lib/libSDL2-2.0.0.dylib",
            // Its own defaults apart from --without-x. Wine uses only the joystick and
            // haptic parts, but SDL's --disable-video/--disable-audio combinations are a
            // known way to end up with a build that does not compile.
            kind: .autotools(configure: cross + ["--enable-shared", "--disable-static", "--without-x"]),
            symlink: nil
        ),
        BuildRecipe(
            componentID: "moltenvk",
            produces: "lib/libMoltenVK.dylib",
            kind: .place,
            symlink: nil
        ),
    ]
}
