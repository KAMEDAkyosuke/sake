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
says where and when it was measured; sake itself has verified none of it.

## Phases

### Phase 1 — the skeleton (done)

An app that builds, launches and does nothing. Repository conventions, and the prototype's
knowledge written down.

### Phase 2 — the build pipeline in Swift (in progress)

Download, verify, configure, `make`, install — driven from Swift, reporting progress the UI
can render. This is where `wine-build.md` becomes code.

Success looks like: a button that produces a working Wine, a progress view that names the
current step, and a failure that says "the Game Porting Toolkit is not mounted" rather than
printing a non-zero exit status.

Standing so far: the preflight checks — Apple silicon, Rosetta 2, the Command Line Tools,
the Game Porting Toolkit, disk space — and the two pieces the rest of the phase sits on, the
on-disk layout as a value type and a subprocess runner that streams output and can be
cancelled. Nothing downloads or builds yet.

### Phase 3 — bottles and titles

Creating prefixes, importing an existing install, per-title settings. The per-title knowledge
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

- **`@loader_path`-relative sonames** would make a built engine movable, which the prototype
  explicitly is not. Verified in isolation, never against a real Wine build. See
  `layout.md`.
- **Path length.** The intended engine location produces sonames ~92 characters long, in the
  untested gap between a known-good 76 and a known-bad 146. Measure before committing to it.
- **How much to generalise beyond one title.** The prototype hard-coded Diablo IV in several
  places (launch arguments, process identification, which directories to import). Phase 3
  has to decide what a title profile actually contains, and one data point is thin.
- **Where the CrossOver version lives.** It is a knob users may need — a newer CrossOver may
  fix or break a given game — but exposing it invites them to pick a combination nobody has
  run.
