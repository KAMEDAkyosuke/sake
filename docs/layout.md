# On-disk layout

Where sake puts things, and why the obvious alternative does not work.

Everything below was measured on 2026-09-18 against the d4-mac prototype's tree, on one
machine (Apple silicon, macOS 27.0, CLT 27.0), except where a section carries its own date —
those were measured in sake.

## The layout

```
/Applications/Sake.app                       the app, and nothing else
~/Library/Sake/
    engine/                                  Wine, its libraries and D3DMetal, 1.1 GB
    bottles/                                 prefixes and the games in them; empty is
                                             1 GB, and a cloned game adds nothing
~/Library/Caches/Sake/
    dl/ sources/ toolchain/ build/           downloads and build intermediates, ~4 GB
    d3dmetal/                                Apple's redist/lib, kept so that the image
                                             need not stay mounted — see licensing.md
```

Uninstalling is an explicit action in the app, not a side effect of dragging the bundle to
the Trash.

## Importing a game costs nothing

A bottle with Diablo IV in it is 100 GB, and the same game is already in a CrossOver bottle
on the same disk. Copying it is not an option on a machine with 43 GB free — but on APFS it
does not have to be a copy.

Measured in sake on 2026-09-19, by copying a 2 GB tree three ways and reading the volume's
free space either side:

| | consumed |
|---|---|
| `/bin/cp -c -R` | ~0 |
| `FileManager.copyItem` | 0 |
| `copyfile(3)` with `COPYFILE_CLONE` | 0 |

So **`copyItem` clones by itself**, and the prototype's `cp -c` needs no subprocess to
reproduce. Writing to a clone does not reach the source — checked by changing a cloned file
and hashing the original — so nothing sake does to its own bottle can damage the working
CrossOver install.

**A clone cannot cross a volume, and `copyItem` does not say so**; it quietly copies
instead. sake compares `st_dev` on both sides and refuses rather than spending 100 GB nobody
asked for. `/` and the data volume share one `st_dev` either side of the firmlink, so that
pair is not what this catches; an external disk, a mounted image or a network share is.

**What comes across is decided by difference, not by a list of titles.** A fresh prefix
already has Wine's own `Common Files`, `Internet Explorer`, `Windows Media Player`,
`Windows NT` and `Microsoft`, so whatever a source bottle holds on top of those in
`Program Files`, `Program Files (x86)` and `ProgramData` is what the user installed. Against
the CrossOver bottle on this machine that comes out as exactly Battle.net, Diablo IV and
four smaller Blizzard directories, with no title named anywhere in the code.

Two things constrain it:

- **The clone has to land at the same relative path.** `ProgramData/Battle.net/Agent/product.db`
  records the install as `C:/Program Files (x86)/Diablo IV`, so the client recognises the
  game only if it is there. (Prototype, 2026-09-17.)
- **`drive_c/windows` is never touched** — that is CrossOver's own Wine; see `licensing.md`.
  `drive_c/users` is left alone as well, on weaker grounds: the prototype never carried a
  user profile across and Battle.net rebuilt its own.

The first real import, on 2026-09-19: six entries, **100.31 GB in 0.4 seconds**, free space
unchanged to within noise, and the source's 2,537 files hashing the same afterwards.

## Why not Application Support

Measured in sake on 2026-09-19. `~/Library/Application Support/Sake` is the obvious home and
it does not work: the engine is an autotools `--prefix`, and the space in "Application
Support" splits back out of `CPPFLAGS` and `LDFLAGS` the moment a configure script expands
them. Every one of the eight library builds failed the same way:

```
clang: error: no such file or directory: 'Support/Sake/engine/include'
```

What was tried, on pkgconf:

| | |
|---|---|
| the path as it is | fails |
| `-I/path/with\ space/include` | fails |
| `-I"/path/with space/include"` | fails |
| a space-free symlink to it, passed as `--prefix` and in the flags | works |

Escaping and quoting cannot work: the shell does not remove quotes or honour backslashes in
the *result* of expanding a variable, so `$CPPFLAGS` is word-split and that is that. The
symlink does work, but what gets baked in is then the link's path — `pkgconf` installed that
way reports the link in its `pc_path` — so the link becomes load-bearing forever. A root
without a space costs nothing by comparison.

macOS does not allow a space in an account's short name, so `/Users/<name>` is safe. A
volume name is where one would realistically appear (this machine boots from
`Macintosh HD`), which matters the day the location becomes something the user picks.

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

What that style actually is, measured in sake on 2026-09-19 (macOS 27.0, SDK 26.5,
deployment target 15.0): an `NSPanel` carrying the utility style mask, at window level 3,
which cannot become the main window, cannot be minimised, and has `hidesOnDeactivate` set.
The last of those decides where it may be used — a window whose job is to say "download this
from Apple" must not vanish the moment the user switches to a browser. So the main window is
a plain `Window`, and the utility style is for the auxiliary windows the setup flow will put
on top of it.

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

So sake writes `@loader_path`-relative sonames, rewriting `include/config.h` between
configure and make.

Measured against a real build on 2026-09-19, which this file previously said remained to be
done:

- The four come out as `@loader_path/../../libfreetype.6.dylib` and the like — `../..`
  because the only thing that `dlopen`s them is `lib/wine/x86_64-unix/`, two levels under
  `lib`. There is no `i386-unix` beside it; under WoW64 the unix side is x86_64 only.
- `strings` finds **no** engine path left in any `lib/wine/x86_64-unix/*.so`. The first four
  rows of the table above are gone.
- An x86_64 dylib placed in that directory `dlopen`s all four by those exact strings — and
  still does after the whole engine tree is moved elsewhere.

Rows five and six of the table survive as expected: `ntdll.so` and `bin/wine` still carry
`engine/{bin,lib,lib/wine,share/wine}`, which is what Wine recomputes from `dladdr` at
startup rather than trusting.

**Wine itself loading them**, which this file previously listed as the remaining unknown,
was measured on 2026-09-19 once there was a prefix to run in:

- `DYLD_PRINT_LIBRARIES=1` over a `wine reg query` shows dyld loading
  `engine/lib/libfreetype.6.dylib` and `engine/lib/libSDL2-2.0.0.dylib`. Their only openers
  are `win32u.so` and `winebus.so` in `lib/wine/x86_64-unix/`, so that is the `@loader_path`
  hop being taken, not a lucky absolute path.
- MoltenVK prints its own banner during `wineboot --init` (`MoltenVK version 1.4.2,
  supporting Vulkan version 1.4.357`), so `libMoltenVK.dylib` loaded as well.
- **gnutls is the one still unobserved.** `bcrypt.so` opens it when something asks for TLS,
  and nothing has yet. The soname is written the same way as the other three.

## Path length is a real constraint, and the new path is untested

The prototype's README records that with a long root, the absolute sonames grow long enough
that verbose `WINEDEBUG` channels overflow Wine's debug buffer and kill the process — taking
away the diagnostic tool exactly when it is needed. Its numbers: 146 characters was too long,
70 was fine.

| root | resulting soname length |
|---|---|
| `~/.local/share/d4-mac` (the prototype, known good) | ~76 |
| `~/Library/Application Support/Sake` (rejected above) | ~92 |
| `~/Library/Sake` | ~65 |

The 92 that sat in the untested gap between the two known points is no longer a question to
answer twice over. `~/Library/Sake` comes out at 65 on a fifteen-character user name, shorter
than the length already known to work — and as of 2026-09-19 sake writes `@loader_path`
sonames anyway, whose longest is 38 characters and does not depend on where the engine lives
at all.

`Paths` still takes both roots as parameters, so a root that turns out to be wrong again does
not reach into every caller.
