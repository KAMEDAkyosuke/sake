# Building Wine from CrossOver's sources

What the build has to do, and which parts of it are not negotiable.

Everything here was learned in the d4-mac prototype between 2026-08 and 2026-09-17, on one
machine (Apple silicon, macOS 27.0), unless a section says otherwise. **sake has built the
prefix — the nine tools and libraries below — on 2026-09-19, and has not yet built Wine
itself.** Treat the rest as the specification the Swift implementation has to satisfy, not
as a report on sake's behaviour.

## Why CrossOver's sources and not upstream Wine

The piece that makes DirectX 12 work on macOS is Apple's closed **D3DMetal**, and the
Wine-side glue it plugs into lives in `dlls/winemac.drv/d3dmetal.c` and `d3dmetal_objc.m` —
about 512 lines of C and Objective-C that hand D3DMetal a `CAMetalLayer`. That glue is LGPL,
so CodeWeavers are obliged to publish it, and they do:
`crossover-sources-<version>.tar.gz`, ~149 MB. Upstream Wine does not have it.

The prototype used CrossOver 26.3.0 because that is the version demonstrably running the
game on the same machine. CodeWeavers keep several versions available, so the version is a
knob the GUI can expose.

## What has to be built before Wine

CrossOver's tarball bundles many dependencies **as sources**, which is not the same as
satisfying them — building the bundled glib needs meson, ninja and python, and gnutls needs
nettle, gmp and libtasn1, none of which are bundled. The short list that actually has to be
produced:

| component | why it cannot be skipped |
|---|---|
| llvm-mingw | the PE compiler. Universal binary, so it runs native or translated |
| bison ≥ 3.0 | `/usr/bin/bison` is 2.3 (2006) and configure rejects it |
| pkgconf | macOS ships no `pkg-config` at all |
| gmp, nettle, libtasn1 | static, underneath gnutls |
| gnutls | without TLS the Battle.net client cannot log in |
| freetype | no fonts at all without it |
| SDL2 | no game controller works without it — see `runtime.md` |
| MoltenVK | Chromium's GPU process dies with no Vulkan driver |

Notes that cost time to find:

- **mingw-w64's GCC is never needed.** llvm-mingw ships `x86_64-w64-mingw32-gcc` as a
  symlink to a clang wrapper, so Wine's configure matches its first-choice "gcc" name while
  the compiler is really LLVM. Apple's old Homebrew formula pulling in mingw-w64 is what
  made this look mandatory.
- **`sources/gnutls` in the tarball is an empty directory.** Several component directories
  ship empty. gnutls has to come from upstream.
- **freetype is present but unbuildable as shipped** — its `dlg` git submodule is missing and
  the Makefile runs `git submodule update` in a non-repository. The official release tarball
  of the same version already contains `src/dlg` and skips that path.
- **MoltenVK is Apache-2.0**, so the upstream Khronos release is used as-is. Rebuilding it
  would change nothing legally.
- The prototype ran newer gnutls, MoltenVK, SDL2 and D3DMetal than CrossOver ships, and that
  was deliberate, not drift.

## configure flags that must not be removed

- **`--enable-archs=i386,x86_64`.** Battle.net's launcher is 32-bit, so 32-bit support is not
  optional. `--enable-win32on64` (CrossOver 22, Apple's 2023 formula) no longer exists;
  Wine 11 uses upstream WoW64.
- **Do not pass `--without-vulkan` or `--without-gnutls`.** They do not compile:
  `dlls/win32u/vulkan.c` (marked `CW HACK 25909`) and `dlls/bcrypt/gnutls.c` reference
  `SONAME_LIBVULKAN` / `SONAME_LIBGNUTLS` with no `#ifdef` around them, because CodeWeavers
  always ship both.
- **Do not pass `--without-sdl`.** The prototype did, and the price was that no game
  controller worked at all, silently — `winebus.sys` still has its IOHID backend and still
  enumerates the device. The tell is `SONAME_LIBSDL2` sitting at `#undef` in `config.h`.
- **Do not pass `--without-unwind`.** configure calls it "do not use the libunwind library
  (exception handling)" and means it: `unwind_builtin_dll()` in
  `dlls/ntdll/unix/signal_x86_64.c` returns `STATUS_UNSUCCESSFUL` for any frame whose DWARF
  FDE cannot be found instead of falling back to libunwind. macOS needs no extra library —
  `unw_step` lives in libSystem, so `HAVE_LIBUNWIND` is defined with `UNWIND_LIBS` empty.
  (Correct on its own merits; it was **not** the fix for the Play button.)

Also: clang 16+ turned several legacy-C patterns into hard errors, so the build needs
`-Wno-implicit-function-declaration -Wno-format -Wno-deprecated-declarations
-Wno-incompatible-pointer-types`. Apple's own formula carried the same list. Apple's patched
clang is *not* required; the Mach-O side builds with stock Apple clang.

## Ordering traps

- **The build must produce x86_64 host tools**, because it generates and then executes them
  (winebuild, widl, wrc, makedep). The prototype got that by wrapping the *build* in
  `arch -x86_64`; with the Command Line Tools alone that route is closed — see below.
- **Never wrap a Wine *run* in `arch -x86_64`.** `arch` is a hardened system binary, so
  exec'ing it strips every `DYLD_*` variable. Wine's binaries are already x86_64, so Rosetta
  handles them anyway.
- **`make install` overwrites D3DMetal.** It puts Wine's own `d3d11`/`d3d12`/`dxgi.dll` back,
  so installing D3DMetal has to happen *after* every `make install`, not once.
- **Sonames must be absolute or `@loader_path`-relative, never leaf names.** See
  `layout.md` — `DYLD_LIBRARY_PATH` does not reach Wine's child processes.

### The wrapping no longer works with the Command Line Tools alone

Measured in sake on 2026-09-19 (CLT 27.0, macOS 27.0). This one is not the prototype's.

`/usr/bin/make` and `/usr/bin/clang` are universal, but they are xcode-select shims that
`dlopen` `libxcrun.dylib` — and that library ships arm64 and arm64e only. The real binaries
behind them, in `/Library/Developer/CommandLineTools/usr/bin`, are arm64-only. Under
`arch -x86_64` the shim reports `missing compatible architecture (need 'x86_64')` and the
real binary reports `Bad CPU type in executable`. Xcode 26.4's copies of both are universal,
so pointing `DEVELOPER_DIR` at Xcode brings the wrapping back — at the price of requiring
Xcode.

What works with the Command Line Tools alone is to run the tools natively and name the
target out loud: every `configure` gets `--host=x86_64-apple-darwin
--build=x86_64-apple-darwin` **and** `CC="clang -arch x86_64"`. Autoconf then believes it is
a native x86_64 build and runs its test programs, which Rosetta executes — which is what the
wrapping used to buy.

`CC` is not optional. With the triplet alone, gmp compiles x86_64 assembly and hands it to
an arm64 assembler: `tmp-add_err1_n.s: error: invalid operand / pop %rbx`.

Verified by building the nine tools and libraries this way on 2026-09-19: all nine landed as
x86_64, and the two that produce executables run. **Wine's own configure is not verified this
way** — the prototype passed it no triplet at all and leaned on the wrapping instead.

## Prefix creation

- **`WINEDLLOVERRIDES="mscoree,mshtml=d"` or `wineboot` hangs forever** on the Wine Mono
  installer dialog, at 0% CPU inside `CFRunLoopRun` → `mach_msg`, and `syswow64` is never
  populated. An empty `syswow64` means no 32-bit app will run — check it.
- **Disable the crash dialog immediately after creating the prefix**
  (`HKCU\Software\Wine\WineDbg` → `ShowCrashDialog` = `REG_DWORD 0`). Otherwise every crash
  spawns `winedbg --auto`, which puts up a GUI dialog and holds the process until someone
  clicks Close. It also resets `WINEDEBUG`. This cost one 300-second timeout in the
  prototype — and in a GUI app, a dialog nobody can see is a hang with no explanation.
- An existing game install can be brought in with `cp -c -R` (APFS `clonefile`). A ~92 GB
  game cost ~0 bytes, and unlike a symlink, writes to the clone do not propagate back, so
  the source install cannot be damaged.

## Shell-specific traps worth keeping

The prototype was shell; sake will not be. These two still apply to anything that composes
paths or runs `hdiutil`:

- **Keep `*` out of a glob stored in a variable.** Every path involved in mounting the Game
  Porting Toolkit contains spaces, so an unquoted variable holding a glob word-splits into
  "Evaluation", "environment", "for", … and silently matches nothing — which reads as "the
  toolkit is not mounted" while it is sitting right there.
- **Three tools lie on this platform.** `pgrep -cf` errors out in a way that reads as "not
  running"; `ps eww` shows nothing for another process's environment, so it cannot confirm
  whether a variable was inherited; and `ps -Ao <fmt> -p <pid>` silently ignores `-p` and
  prints every process.
