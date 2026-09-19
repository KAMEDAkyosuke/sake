# Roadmap

## The goal

Someone who has never opened a terminal can install sake, follow the app, and end up playing
a Windows game on their Mac. Every setting is in the GUI. Every long operation shows
progress. Every failure says what went wrong and what to do about it.

That is the bar. A tool that works only for people who can read a build script already
exists — see "Where this came from".

## Where this came from

The `d4-mac` prototype (a set of shell scripts, not in this repository) got Diablo IV
playable on 2026-09-17 by building CrossOver's Wine from CodeWeavers' published LGPL sources.
It proved the approach. It is unusable by anyone who will not read shell.

None of its code is here, deliberately. What came across is the reasoning, in
`wine-build.md`, `runtime.md`, `licensing.md` and `layout.md`. Every claim in those files
says where and when it was measured. Most of it is still the prototype's; where sake has
since measured something itself, the section says so and carries its own date.

## Phases

### Phase 1 — the skeleton (done)

An app that builds, launches and does nothing. Repository conventions, and the prototype's
knowledge written down.

### Phase 2 — the build pipeline in Swift (done)

Download, verify, configure, `make`, install — driven from Swift, reporting progress the UI
can render. This is where `wine-build.md` became code.

The chain ran end to end on 2026-09-19: the preflight checks (Apple silicon, Rosetta 2, the
Command Line Tools, the Game Porting Toolkit, disk space), the two pieces the rest sits on
(the on-disk layout as a value type, and a subprocess runner that streams output and can be
cancelled), fetching the eleven sources against pinned hashes, building the tools and
libraries into the engine prefix, building Wine itself against them — configure, the
`@loader_path` soname rewrite, make, install, and a check that this is CrossOver's tree and
not upstream's — and guiding Apple's D3DMetal in from an image the user mounted. That leaves
a 1.1 GB engine.

What it does not do is **run** any of it. Starting Wine needs a prefix, and that is Phase 3.

### Phase 3 — bottles and titles (next)

Creating prefixes, importing an existing install, per-title settings. This is also where the
prototype's two ntdll patches have to land, and where the three settings in `runtime.md`
stop being something only the prototype has tried. The per-title knowledge
is pure data (executable path, arguments, environment, how to recognise its process), so it
belongs in a declarative form the GUI can read and edit — not in code.

### Phase 4 — the GUI proper

Setup flow, library, per-title configuration, uninstall. `layout.md` covers where things go
and why uninstall has to be an explicit action.

## The Swift/subprocess boundary

Settled during planning on 2026-09-18, recorded here so it is not relitigated.

- **Swift owns** configuration, orchestration, progress, error recovery, state and UI.
- **Subprocesses** run `configure`, `make`, `wine` and the rest. No design removes these;
  something has to start `make`.
- **The prototype's shell scripts are a reference, not a component.** They are not wrapped,
  vendored or shipped.

The argument for keeping the shell layer — that it is the thinnest possible wrapper and can
be run by hand when something breaks — assumes the user is someone who reads shell. That is
exactly the assumption this project exists to remove. Once settings must be editable in a
GUI, progress must be reportable step by step, and a failure must offer a next action, the
orchestration has to live where the UI can see it.

The knowledge those scripts carried in comments is not lost; it is in `docs/`, where it is
easier to read than it was interleaved with `configure` flags.

## Open questions

- **`@loader_path` sonames under a running Wine.** As of 2026-09-19 sake writes them, a real
  build carries them, and an x86_64 dylib sitting where Wine's unix libraries sit resolves
  all four — moved tree included. What is still unwatched is Wine itself loading one. See
  `layout.md`. (Path length, which used to be the question below this, went away with them.)
- **How much to generalise beyond one title.** The prototype hard-coded Diablo IV in several
  places (launch arguments, process identification, which directories to import). Phase 3
  has to decide what a title profile actually contains, and one data point is thin.
- **Where the CrossOver version lives.** It is a knob users may need — a newer CrossOver may
  fix or break a given game — but exposing it invites them to pick a combination nobody has
  run.
