# Patches against Wine's own source

**This directory is LGPL-2.1-or-later, not MIT.** A patch against Wine is a derivative of
Wine, and the rest of this repository's licence does not reach it. `LICENSE` here is Wine's
own `COPYING.LIB`, which is the licence these files are under. See `docs/licensing.md`.

They apply to the `sources/wine` tree out of CodeWeavers' CrossOver tarball, with `-p1`.
`WinePatcher` applies every `*.patch` here in name order before Wine is configured, and asks
`patch` itself whether one is already in rather than keeping a marker — if it reverses
cleanly it is applied. That stays true as patches are added or changed.

Each file carries its reasoning in a prose header above the diff. **Read that before
touching the patch**: both of these were found by measurement, and the header is where the
measurement is. `docs/runtime.md` says what each one is for and how to tell that it worked.

A new patch belongs here only if it changes Wine's own code. Anything sake can do from the
outside — a configure flag, an environment variable, a registry key — is not a patch, and a
patch is the thing that has to be rebased every time CrossOver publishes new sources.
