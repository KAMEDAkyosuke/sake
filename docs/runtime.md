# Running games: the settings, the patches, and how to tell failures apart

A built Wine is not a working one. This is what the d4-mac prototype needed on top of the
build to get Diablo IV from "starts" to "plays", verified 2026-09-17 and 2026-09-18 on one
machine. **sake has verified none of it.**

## Three settings carry the whole thing

None is on by default, and no symptom resembles its cause.

### `WINE_SIMULATE_WRITECOPY=1` — or Battle.net never fetches the login page

CodeWeavers' `CW Hack 22996`. With it, a page that has been `VirtualProtect`ed away from
`PAGE_WRITECOPY` is reported as already copied, which is what Windows does.

Without it, every CEF render process executes an `int3` within five seconds of starting,
always at the same address; `UAuth: begin loading` never appears and the login page is never
even requested. CodeWeavers told Battle.net users to set this by hand in 2023 and it is
still not automatic.

### `--in-process-gpu` — or the login form is drawn but never shown

With a separate GPU process the login web view never gets a compositor surface of its own.
MoltenVK reports swapchains for the window (348x646) and the chrome strip (348x50) but never
one the size of the page content (348x558); the view stays black while the renderer paints
the form perfectly. Folding the GPU into the browser process makes the content surface
appear.

This is not a graphics setting in disguise. Turning off Battle.net's own browser hardware
acceleration changes nothing, `--disable-direct-composition` changes nothing, and fonts are
not involved.

Battle.net also needs `--use-gl=angle --use-angle=vulkan`. Left alone, ANGLE tries its D3D11
backend (which gets nothing — D3DMetal has no 32-bit half), then SwANGLE, then gives up with
"GL is disabled" and the GPU process exits with `ACCESS_VIOLATION`.

### `CX_APPLEGPTK_LIBD3DSHARED_PATH` — or Diablo IV does not start at all

Apple's `libd3dshared.dylib` exports `register_non_native_code_region`, which is how Rosetta
is told a region of memory holds dynamically generated x86_64 code. Wine only looks that
symbol up when this variable points at the library (`init_non_native_support()` in
`dlls/ntdll/unix/loader.c`). CrossOver's launcher sets it on every run; nothing else does.

Blizzard's protected loader `diablo_iv_loader.dll` generates code at runtime and drives it
with fibers plus `SetThreadContext` on other threads. Without the registration the fiber
switch does not return where the loader expects, its scheduler loop re-enters, and it
deadlocks re-acquiring its own non-recursive SRW lock. What you see is 0.0% CPU, 122 MB
resident, nine threads, no window, and **not one byte** in the game's own
`_FenrisDebug-*.txt`. Nothing in that picture points at Rosetta.

The 32-bit client is structurally unaffected: `pe_module_loaded()` reaches
`init_non_native_support()` only on the 64-bit side, because the WoW64 entry point
`wow64_pe_module_loaded()` is a stub returning `STATUS_NOT_IMPLEMENTED`.

**Also place `libd3dshared.dylib` in the same directory as `D3DMetal.framework`.**
`d3d12.so` declares `LC_RPATH = @loader_path` and looks for `libd3dshared.dylib` beside
itself; `libd3dshared` then `dlopen`s `@rpath/D3DMetal.framework/D3DMetal` relative to *its*
own location. Copying only `libd3dshared` next to the `.so` files breaks it.

## Two patches to Wine's own code

The prototype carried two patches. Both are LGPL, being derivatives of Wine.

**Resolve `libd3dshared` from `dll_dir` when the variable is unset.** A process whose
environment was composed by an application never inherits the variable. Measured with the
variable removed: before the patch 122 MB at 0.0% CPU with nine threads (deadlocked), after
it 2561 MB at 38.6% CPU with 84 threads (running). The variable still wins when set.

**Read `BOOLEAN` syscall arguments as the Windows ABI defines them.** This is the one that
made the Play button work, and it is worth understanding before touching ntdll.

Since Diablo IV 3.1.0 (2026-06-30) the loader inspects the process that started it, when
that process is still alive — and `Agent.exe` always is. It opens the parent, reads its
image path, and walks `\DosDevices` one entry at a time with `NtQueryDirectoryObject` to
build a drive-letter-to-device map. CrossOver's build asks for index 0, 1, 2 … 48 and
finishes. The prototype's asked for **index 0 on every call, ~55,000 times a second,
forever** — its `+server` log grew at 17 MB/s, which is how the loop was found.

`WINEDEBUG=+syscall` showed the fifth argument, `RestartScan`, a stack-passed `BOOLEAN`:

| build | `restart` argument word |
|---|---|
| the prototype | `6c006200610000` — UTF-16 `abl`, leftover from a path string |
| CrossOver | `00000000` |

The low byte is FALSE in both. The Windows x64 ABI leaves the upper bits of a narrow
argument undefined and MSVC stores exactly one byte, so the caller is within its rights.
`__wine_syscall_dispatcher` copies the whole 8-byte word into the SysV register, and the
clang-built unix side assumes — as the SysV ABI permits — that a narrow parameter arrives
zero-extended, compiling the test to `testl %r8d, %r8d`. Non-zero garbage above the low byte
therefore reads as TRUE and the enumeration restarts forever.

The fix adds an empty asm barrier that makes the compiler forget the zero-extension
assumption, and applies it to both `BOOLEAN` parameters of `NtQueryDirectoryObject` only,
because that is the call that was measured. **The same exposure exists in
`NtQueryDirectoryFile`, `NtQueryEaFile`, `NtSetTimer`, `NtLockFile`,
`NtNotifyChangeDirectoryFile`, `NtNotifyChangeKey` and `NtCreateEvent`** — Wine's own PE DLLs
are their usual callers and keep the slot clean, so nothing has been seen to need it.

Two things this is *not*:

- **Not a CrossOver-only correctness win.** CrossOver's `ntdll.so` has the identical
  `testl %r8d, %r8d`. It passes because its GCC/binutils-built PE DLLs leave zeros in that
  slot. That reading is inference, not measurement; what was measured is the zero in their
  trace and the string in ours. Either way it is a latent bug in every clang-built Wine.
- **Not Valve's Proton Hotfix.** ValveSoftware/Proton #9926 is a different failure on Linux
  (an exit on a breakpoint before any renderer init). A GCC-built unix side cannot hit this
  bug.

## SSO: pressing Play does two separable things

1. **The client becomes willing to hand out a token.** Launching the game directly without a
   press earlier in the same client session gets it all the way up — rendering, intro
   playing — and then `Aurora has rejected the token`, *"There was a problem logging in.
   (Code 7)"*. Measured in one session: manual launch at 02:13 got Code 7, Play pressed at
   02:48, manual launch at 02:52 logged in and reached character select.
2. **`Agent.exe` starts the game.** This is the part the BOOLEAN bug broke.

The client logs `Pre-existing game session detected without a pending launch` for every
manual start **including the ones that log in perfectly**, so that message says nothing
about the token.

Implication for sake: a "launch the game directly" button cannot work for this title on its
own. The launcher's own flow has to be driven at least once per session.

## Controllers need SDL2

`winebus.sys` has two backends. **IOHID** is built either way and handles anything behaving
as a plain HID gamepad. **SDL** is compiled in only if configure found SDL2, and it is the
one that knows device-specific protocols.

A Nintendo Switch Pro Controller needs the second: it enumerates as a HID device with a
reasonable descriptor and then sends **no input reports at all** until it has been through
Nintendo's handshake, which lives in SDL's HIDAPI driver. An IOHID-only build gives a
controller that is plugged in, visible to macOS, and completely dead in the game.

Verified by playing the game with a Switch Pro Controller over USB, 2026-09-17. Bluetooth
and other pads are untested.

Use SDL2 newer than CrossOver's 2.30.12: 2.32.2 fixed a crash initialising with controllers
already connected on macOS, 2.32.6 fixed reliability of initializing Switch controllers on
macOS, and 2.32.10 fixed thumbstick range and calibration for Switch Pro Controllers by
name. If a pad misbehaves, 2.30.12 is the version known-good under CrossOver and the right
thing to bisect against. Not SDL3 — Wine looks for pkg-config's `sdl2` and `SDL_Init` in
`libSDL2-2.0*`.

## Telling failure states apart

RSS alone misleads, and a hang and a slow start look nothing alike. Thread count separates
the top three states; `vmmap $pid | grep -icE 'Metal|AGX'` says whether graphics was ever
reached (~50 mappings means never, 100+ means rendering).

| state | threads | RSS | Metal/AGX maps |
|---|---|---|---|
| no Rosetta registration, or a mismatched-ABI module | 9-11 | 125-155 MB | ~50 |
| the `\DosDevices` loop (before the BOOLEAN fix) | 12 | 235-245 MB | ~50 |
| graphics up, waiting on the client | 17-19 | 390-410 MB | 74-81 |
| running and rendering | 83-98 | 1.7-4.6 GB | 100+ |

Four traps in that table, each of which produced a wrong conclusion in the prototype:

- **The running row kept being too narrow.** It read 83-90, then 83-96, then 83-98, widened
  each time someone measured again. Read it as "well past 40", not as a window to match.
- **The counts include the process row** (`ps -M -p $pid | tail -n +2 | grep -c .`). Count
  thread rows alone and everything reads one low — the stall comes out at 11, lands in the
  row above, and a reproducing hang gets reported as a dead build.
- **Threads do not separate the bottom two states.** 9-11 against 12 is one thread. RSS is
  what tells those apart: 125-155 MB against 235-245 MB.
- **Sample, do not read once at the end.** A build that clears the check and then dies of
  something unrelated looks identical to one that never cleared it, if you only look at the
  end. Keep the peak.

Identify the game's process by the `argv[0]` that *ends with* the executable name, not one
that contains it: a loose match also catches `cmd.exe`, `start.exe` or any launcher carrying
the name in its own arguments. That happened twice. Matching the bare name at the start is
not enough either, because `argv[0]` is spelled differently depending on how the game was
started. Cut `argv[0]` at its first `.exe` and check what that ends with.

## Diagnostic technique that paid off

- **Search before analysing.** The `WINE_SIMULATE_WRITECOPY` fix is documented across
  Lutris, GamingOnLinux and CodeWeavers' own forum. Hours of first-principles crash analysis
  went in before anyone searched. The lesson was then ignored on the Play button and the
  same bill arrived. Caveat learned the second time: the search found the *game update*, not
  the *cause*. **Search first, then measure.**
- **Diff against a working implementation on the same machine.** CrossOver is installed and
  this tree is built from *its* sources, so anything that differs is configuration or build
  flags. Running CrossOver's binaries against the prototype's bottle answered "build or
  bottle?" in one command. Its Perl `bin/wine` is readable and
  `--bottle NAME --ux-app /usr/bin/env` dumps the environment its launcher builds — bisect
  the environment from the side that works, rather than guessing single variables against a
  failing run.
- **Make the two candidates produce different observable output before believing either.**
  The Play button was blamed on `Agent.exe` not passing an environment variable. The
  variable arrives. The diagnosis stood because the symptom it predicted was the symptom
  present.
- **Read the application's own logs first.** Battle.net writes
  `drive_c/users/<user>/AppData/Local/Battle.net/Logs/{battle.net,libcef}-*.log`, and the
  libcef log named the real problem after a lot of guessing had not.
- **`--remote-debugging-port=9222`** distinguishes "not painting" from "painting but not
  shown". Battle.net forwards unrecognised arguments to CEF. `Page.captureScreenshot` proved
  the renderer was drawing the login form perfectly while the window was black.
- **MoltenVK's `Created N swapchain images with size (W, H)` lines are a free instrument.**
  Comparing which surface sizes appear between runs exposed the missing content-sized
  surface and then confirmed the fix.
- **`WINEDEBUG=+loaddll` names the last DLL before a hang** and is safe on its own.
  `+server`, `+syscall`, `+module`, `+seh` and `+file` are light enough to keep a failure
  reproducing.
- **Wine keeps its sockets in `wineserver`**, not the Windows-side process. `lsof` against
  the Battle.net pid shows zero connections while it is talking to Blizzard happily. This
  produced three consecutive wrong network conclusions.
- **`wineserver -k` silently targets `~/.wine` unless `WINEPREFIX` is set**, exits 0, and
  reports success having killed nothing. Killing wineserver *is* how a bottle is taken
  down — `Agent.exe` runs with ppid 1, wineserver is its own daemon, and Battle.net keeps a
  fistful of CEF helpers.
- **`WINEDEBUG=err+all` causes crashes rather than revealing them.** A failed `dlopen` of a
  missing dylib produces a `dlerror()` string long enough to overflow Wine's debug buffer;
  the exception cannot be dispatched and the process dies. Raising the log level turns a
  cleanly handled failure into a crash.
- **A whole-module relay trace can hide the bug.** `RelayFromInclude` on the loader logs ~7M
  calls and the game then starts fine. That was read as timing sensitivity and it was not
  one — the overhead changes what callees leave on the stack. A Heisenbug is a limit on
  which instrument you may use, not evidence about the cause.
- **Attaching a debugger to Diablo IV is destructive.** The protected loader answers with an
  unhandled `0xc00000e5` and obfuscated registers, and the process drops from 58% CPU to
  1.8% — the state you came to read is gone. `sample(1)` is safe but cannot unwind through
  `__wine_syscall_dispatcher`.
- **Check that the control actually ran.** A control run whose log is zero bytes did not
  reproduce anything; it failed to start.
