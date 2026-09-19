# sake

Run Windows games on an Apple silicon Mac, by building CrossOver's Wine from CodeWeavers'
published LGPL sources — with a GUI, so it does not take a terminal.

## Status: a game starts. Nobody has played one yet.

What the app does today is answer whether this Mac can do the rest — Apple silicon,
Rosetta 2, the Command Line Tools, Apple's Game Porting Toolkit, room on disk — then
download the eleven sources, check them against known hashes, unpack them, build the tools
and libraries Wine is configured against, build CrossOver's Wine itself, guide Apple's
D3DMetal in from an image you mounted, make a bottle with the result, clone a game you
already installed under CrossOver into it, and start it.

The Battle.net client comes up, reaches Blizzard and loads its login page. Diablo IV starts
as well: launched behind a live parent process — the shape the client's Agent creates, and
the one that used to stall forever — it reaches 92 threads and 103 Metal/AGX mappings, which
is what the two patches in `patches/` are for.

What nobody has done is press Play in the client and play. The evidence here is process
state rather than a screen, and the client only hands out a login token after that press. If
you were looking for something you can play today, this is not it yet.

There are two windows: a library for what is installed and what can be started, and a setup
wizard that walks the six steps above one at a time. The wizard opens itself when setup is
not finished.

What is here:

| | |
|---|---|
| `Sources/SakeKit/` | the layout, a subprocess runner, the preflight checks, the source fetcher, the prefix build, the Wine build, the patch step, the D3DMetal step, the bottle, the import and starting a title |
| `Sources/sake/` | the SwiftUI app — two windows, kept thin |
| `patches/` | the two changes sake makes to Wine's own code — LGPL-2.1-or-later, not MIT |
| `docs/` | how the thing actually has to work, and what breaks when it doesn't |
| `scripts/build-app.sh` | builds `target/Sake.app` |
| `scripts/test.sh` | runs the tests |

## The goal

Someone who has never opened a terminal installs sake, follows the app, and ends up playing.
Every setting in the GUI, progress shown for every long operation, and failures that say
what to do next rather than printing an exit status.

The approach was already proven by a prototype — a pile of shell scripts that got Diablo IV
playable on 2026-09-17 — which worked only for someone willing to read shell. sake is the
part that was missing. See `docs/roadmap.md`.

## Why build Wine at all

The piece that makes DirectX 12 work on macOS is Apple's closed D3DMetal, and the Wine-side
glue it plugs into lives in `dlls/winemac.drv/d3dmetal.c`. That glue is LGPL, so CodeWeavers
publish it, and that is what makes "build the same Wine yourself" a real option rather than
wishful thinking. Upstream Wine does not have it.

**D3DMetal itself is not redistributable**, so sake will never ship it or fetch it for you —
it guides you through downloading Apple's Game Porting Toolkit yourself. See
`docs/licensing.md`.

## Building

Requires the Xcode Command Line Tools. Xcode is not needed.

```sh
./scripts/build-app.sh            # target/Sake.app
./scripts/build-app.sh --release  # plus a zip
./scripts/test.sh                 # the tests
```

On macOS 27 the Command Line Tools default to the macOS 27.0 SDK, which SwiftUI cannot be
built against without a macro plugin the CLT do not ship. `build-app.sh` detects this and
falls back to a macOS 26 SDK, printing what it did. Override with `SDKROOT` if needed. See
`CLAUDE.md` for the full story.

## Documentation

`docs/` is the real content of this repository at the moment. Every claim in it names where
and when it was measured. Most of it is still the prototype's; the sections sake has measured
itself say so and carry their own date.

| file | what it covers |
|---|---|
| `docs/roadmap.md` | the goal, the phases, and where Swift stops and subprocesses start |
| `docs/wine-build.md` | building Wine from CrossOver's sources; the flags that cannot be dropped |
| `docs/runtime.md` | creating a prefix, the three settings that make games run, the Play-button root cause, controllers, and how to tell four failure states apart |
| `docs/licensing.md` | what may and may not be redistributed, and why D3DMetal is unavoidable |
| `docs/layout.md` | where files go, why importing a 100 GB game costs nothing, why nothing mutable lives in the app bundle, and what pins a built tree to its path |

## Requirements (for what sake will do, once it does it)

- Apple silicon with Rosetta 2
- macOS 15 or newer
- Apple's Game Porting Toolkit dmg — a free Apple ID is enough
- ~10 GB for sources and build output, plus whatever the game needs

Nothing is installed into `/usr/local`, `/opt/local` or `/nix`.

## Licence

MIT, except `patches/`: patches against Wine's own source are derivatives of LGPL code and
are LGPL-2.1-or-later. See `docs/licensing.md`.
