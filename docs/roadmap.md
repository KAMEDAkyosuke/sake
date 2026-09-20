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

What it does not do is **run** a game. Starting Wine at all needs a prefix, and that is
Phase 3.

### Phase 3 — bottles and titles (under way)

Creating prefixes, importing an existing install, per-title settings. This is also where the
prototype's two ntdll patches have to land, and where the three settings in `runtime.md`
stop being something only the prototype has tried. The per-title knowledge
is pure data (executable path, arguments, environment, how to recognise its process), so it
belongs in a declarative form the GUI can read and edit — not in code.

**Creating a prefix is done, as of 2026-09-19**, and it is the first thing here that runs
what the earlier phases built: wineboot, the wait, the checks that WoW64 came up and that
Wine found the engine's own libraries, and the crash dialog turned off before anything can
put one up. `runtime.md` has what that measured.

**Importing is done too, the same day.** A game already installed under CrossOver is cloned
in rather than copied, which costs no disk at all, and what comes across is decided by
difference against a fresh prefix — so no title is named in the code. `layout.md` has the
measurement and `licensing.md` the line it stays inside.

**Starting a title is done, also 2026-09-19**, and with it the first end-to-end evidence
that any of this works: the Battle.net client comes up in sake's own bottle and loads its
login page. What a title is — executable, arguments, how to recognise its process — is a
value, not code.

**The two patches landed the same day, and with them a game runs.** Diablo IV starts behind
a live parent process and reaches 92 threads, 1982 MB and 103 Metal/AGX mappings, where the
unpatched build stalls flat at 12. `runtime.md` has both measurements and what they are
against; `licensing.md` has why `patches/` is not MIT. What is still unpressed is the Play
button itself — the probe reproduces the check that button trips over, not the button.

Still to come here: what else a title profile has to carry once a second one exists.

### Phase 4 — the GUI proper (under way)

Setup flow, library, per-title configuration, uninstall. `layout.md` covers where things go
and why uninstall has to be an explicit action.

**Started on 2026-09-19 by splitting the window in two.** Setting sake up is done once and
running a game is done every day, and one scrolling column had them interleaved. Now there
is a library window and a setup wizard, one step per screen with the whole list of steps
beside it — the list stays because a step here can take tens of minutes and fail, and a
wizard that shows only the current card leaves you with no idea where you were.

Which step is current, and what blocks each one, is in `SakeKit` rather than the wizard: it
is the only real decision the wizard makes, and logic in a view is logic that stops being
tested.

The library is a list with a detail pane rather than a row per game, for two reasons worth
keeping: a row per game means a Play button per game, and the detail pane is where per-title
settings go when they arrive. Importing is a sheet on that window rather than a window of
its own — it belongs to one bottle, and it finishes in under a second. The setup wizard is
a window instead precisely because it does not: it runs for tens of minutes and sends the
user to a browser part way through.

Still to come: more than one bottle, adding and editing titles, and uninstall.

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

- **gnutls is the last `@loader_path` soname nothing has loaded.** As of 2026-09-19 a
  running Wine loads freetype, SDL2 and MoltenVK by the rewritten names; `bcrypt.so` opens
  gnutls only when something asks for TLS, and nothing has yet. See `layout.md`. (This used
  to be the whole question of whether Wine could load any of them, and path length before
  that. Both went away.)
- **A built engine does not pick up a change to a patch.** `bin/wine` existing is what says
  the Wine step is done, so changing something in `patches/` means deleting that by hand and
  rebuilding. The D3DMetal half of this went away on 2026-09-19 — a rebuild now drops that
  step back to unfinished, because it asks whether the DLLs are Apple's rather than whether
  the framework is there — but nothing yet knows that a patch has changed under it.
- **How much to generalise beyond one title.** The prototype hard-coded Diablo IV in several
  places (launch arguments, process identification, which directories to import). One of
  those went away on 2026-09-19 — which directories to import is a difference, not a list —
  but launch arguments and process identification are still per-title, and one data point
  is thin.
- **Where the CrossOver version lives.** It is a knob users may need — a newer CrossOver may
  fix or break a given game — but exposing it invites them to pick a combination nobody has
  run.
