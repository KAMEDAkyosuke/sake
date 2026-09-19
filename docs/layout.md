# On-disk layout

Where sake puts things, and why the obvious alternative does not work.

Everything below was measured on 2026-09-18 against the d4-mac prototype's tree, on one
machine (Apple silicon, macOS 27.0, CLT 27.0). sake has verified none of it in its own code.

## The layout

```
/Applications/Sake.app                       the app, and nothing else
~/Library/Application Support/Sake/
    engine/                                  the Wine build and its libraries, ~1.2 GB
    bottles/                                 prefixes and the games in them, tens of GB
~/Library/Caches/Sake/
    dl/ sources/ toolchain/ build/           downloads and build intermediates, ~4 GB
```

Uninstalling is an explicit action in the app, not a side effect of dragging the bundle to
the Trash.

## Why nothing mutable goes inside the bundle

Putting the whole tree under `Sake.app` is attractive: drag to Trash and everything is gone.
It does not survive contact with how apps are updated.

**Finder's "Replace" on an app bundle is a wholesale replacement, not a merge.** Every app
update would therefore destroy the engine and every bottle inside it. `scripts/build-app.sh`
does the same thing locally — it `rm -rf`s the app directory before rebuilding. An update
costing the user a re-download of tens of gigabytes is not a trade worth making for a
tidier uninstall.

Two further costs, measured rather than assumed:

- Writing a file into `Contents/Resources` after signing makes `codesign --verify` report
  `a sealed resource is missing or invalid`. An ad-hoc signed app still launches, so this is
  survivable for a self-built binary, but it forecloses notarized distribution.
- `/Applications` is `drwxrwxr-x root:admin`, so a non-admin user cannot install there at
  all, and an app that writes into itself in a protected location is exposed to macOS 14+
  App Management restrictions. That last point was **not** measured — the layout above makes
  it moot.

## Deployment target: macOS 15

D3DMetal itself does not require it:

```
$ otool -l .../D3DMetal.framework/Versions/A/D3DMetal | grep -A4 LC_BUILD_VERSION
      cmd LC_BUILD_VERSION
  platform 1
    minos 14.0
      sdk 26.4          # libd3dshared.dylib reports the same
```

macOS 14 is the floor D3DMetal sets. sake targets 15 anyway, for reasons above it rather
than below it:

- SwiftUI's `UtilityWindow` is `@available(macOS 15.0, *)`, and it is the window style this
  app wants for the setup flow's own windows. 14 would rule it out.
- The Game Porting Toolkit that supplies D3DMetal wanted Sequoia by version 3, so users who
  can obtain D3DMetal at all are essentially all on 15 or newer.
- Nothing is gained by going higher. The UI this app needs is available at 15, so raising
  the target to 26 removes no `@available` checks — it only excludes Sequoia users, who are
  exactly the audience.

Raise it when a macOS 26-only API earns it; raising a deployment target later is cheap.

**What sake must not do is refuse to install based on the OS version alone.** The real
requirements are Apple silicon, Rosetta 2, and a D3DMetal the user has supplied. Check those
at runtime and say which one is missing.

## Relocatability

The prototype's README states the built tree cannot be moved. That is true of the prototype
as built, and it is a self-inflicted constraint rather than a property of Wine.

Every absolute path baked into the built tree, measured with `strings`:

| file | baked path |
|---|---|
| `win32u.so` | `prefix/lib/libfreetype.6.dylib`, `libMoltenVK.dylib` |
| `bcrypt.so` | `prefix/lib/libgnutls.30.dylib` |
| `winebus.so` | `prefix/lib/libSDL2-2.0.0.dylib` |
| `ntdll.so`, `bin/wine` | `wine-install/{bin,lib/wine,share/wine}` |

Seven strings in five files. The first four are written by the prototype's own `sed` over
`include/config.h`, which rewrites the sonames `configure` recorded as leaf names. The reason
it does that is sound and must be preserved: Wine `dlopen()`s these by the recorded name, a
leaf name only resolves through `DYLD_LIBRARY_PATH`, and **`DYLD_LIBRARY_PATH` does not reach
Wine's child processes** — the symptom is the main process finding freetype while every CEF
subprocess reports "Wine cannot find the FreeType font library".

What makes the constraint removable:

- **Wine relocates itself already.** `dlls/ntdll/unix/loader.c:479` calls
  `dladdr(init_paths, &info)` to find where `ntdll.so` actually is, then derives `bin_dir`
  and `data_dir` with `build_relative_path()`. The compiled-in `BINDIR` / `LIBDIR` are only
  used to compute the relative offset between them.
- **`dlopen("@loader_path/...")` resolves.** Verified directly: an x86_64 dylib that
  `dlopen`s a path relative to `@loader_path` loads its target from an unrelated working
  directory, and continues to work after the whole tree is moved elsewhere.
- **The dylibs have no absolute cross-dependencies.** `otool -L` on each library in
  `prefix/lib` lists only its own install name; gmp, nettle and libtasn1 are linked
  statically into gnutls. A stale install name therefore does no harm when the library is
  `dlopen`ed by an explicit path.

What genuinely stays pinned is `bison`, which compiles in the location of its skeleton files
(`prefix/share/bison`). That only bites a *rebuild* after a move, not a run, and
`BISON_PKGDATADIR` overrides it.

So sake should write `@loader_path`-relative sonames from the start. **This has been measured
only in isolation, never against a real Wine build** — that remains to be done.

## Path length is a real constraint, and the new path is untested

The prototype's README records that with a long root, the absolute sonames grow long enough
that verbose `WINEDEBUG` channels overflow Wine's debug buffer and kill the process — taking
away the diagnostic tool exactly when it is needed. Its numbers: 146 characters was too long,
70 was fine.

| root | resulting soname length |
|---|---|
| `~/.local/share/d4-mac` (the prototype, known good) | ~76 |
| `~/Library/Application Support/Sake` | ~92 |

**92 is in the untested gap between the two known points.** Measure it before committing the
engine to that path — and note that `@loader_path`-relative sonames, which are short, remove
the problem entirely if they land first.
