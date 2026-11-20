---
name: heinzel-macos-cleanup
argument-hint: "[app name]"
description: Find and remove leftovers of uninstalled apps on a
  macOS machine, or uninstall one app with all its files, in
  ~/Library and /Library (Application Support, Containers, Group
  Containers, Preferences, caches, launchd jobs, privileged
  helpers, audio drivers, installer receipts). Use when the user
  asks to "clean up Library", "remove leftovers of old apps",
  "find orphaned app files", or to "uninstall <app> completely".
  Do NOT auto-invoke for general disk-space questions. macOS
  only.
---

# heinzel-macos-cleanup

Two modes on a macOS machine, local or over SSH:

- **Orphans:** leftovers of apps that are no longer installed.
- **Uninstall:** one installed app with everything it created.

**Never run automatically.** Only on explicit user request. The
heinzel first-connection pipeline still applies first.

## Workflow

1. **Load overrides.** Apply the heinzel override chain (later
   wins):
   - `rules/heinzel-macos-cleanup.md` of Heinzel Pro and of each active
     extension, if present (`rules/extensions.md`).
   - `memory/custom-rules/heinzel-macos-cleanup.md` if present.
   - `memory/servers/<hostname>/memory.md`.
   - `memory/servers/<hostname>/rules.md` if present.
   `memory/custom-rules/all.md` is already loaded by the
   session-start preflight.
2. **Check the scanner runtime.** The scanner needs the Python
   of the Command Line Tools. Probe:

       xcode-select -p && /usr/bin/python3 --version

   If the probe fails, do not install anything. On a fresh Mac,
   `/usr/bin/python3` opens an install dialog, and over SSH no
   one can answer it. Fall back to the manual probes in
   `references/locations.md` and say so in the report.
3. **Scan.** The scanner only reads. It prints JSON.

   Local:

       /usr/bin/python3 \
         .claude/skills/heinzel-macos-cleanup/scripts/scan.py orphans

   Remote (script on stdin, SSH options from `CLAUDE.md`):

       ssh <options> user@host /usr/bin/python3 - orphans \
         < .claude/skills/heinzel-macos-cleanup/scripts/scan.py

   Log in as the user whose apps you clean up, never as root:
   the scanner reads its own user's Library and refuses root.
   Ask for the user if the server memory names none. `/Library`
   entries need `sudo` at removal (`references/removal.md`).

   For the uninstall mode, pass `app "<name>"` instead of
   `orphans`. A name, bundle id or `.app` path works. Over SSH,
   the remote shell splits the arguments again, so quote twice:
   `app "'Microsoft Teams'"`. If the result lists `candidates`,
   ask which path is meant and rerun with that path.
4. **Read `unreadable`.** Paths listed there need Full Disk
   Access for the terminal app (or for `sshd-keygen-wrapper` over
   SSH). Report them. Do not guess their contents.
5. **Verify every candidate.** The scanner classifies by name
   and bundle id. Before proposing a removal, confirm it on the
   live system (`rules/verify-before-reporting.md`). The checks
   per class are in `references/classification.md`.
6. **Report** in the format of `references/report-format.md`.
7. **Ask per group.** Propose removal for `orphan` entries and
   for `vendor` entries that verification proved orphaned. Never
   propose `apple` or `installed`. Offer `cache` as a separate
   group. Offer `custom` and `unclear` entries only one by one,
   with the finding that makes each one safe.
8. **Remove** only what the user approved, as described in
   `references/removal.md`. Always move to the Trash. Never
   `rm -rf`.
9. **Verify absence.** Test each approved path again, or rerun
   the scanner. Report what is gone and what failed.
10. **Log.** Journal and local changelog per
    `rules/changelog.md`:

        logger -t heinzel "macOS cleanup: 42 leftovers of 9 \
        removed apps moved to Trash (1.2 GB)"

    For the uninstall mode, remove the app from
    `memory/servers/<hostname>/memory.md` if it is listed there.

## References

- `references/classification.md`: scanner classes, the checks
  that verify them, and the traps behind each rule.
- `references/locations.md`: where apps leave files, and manual
  probes for hosts without the Command Line Tools.
- `references/removal.md`: moving to the Trash, root-owned
  files, launchd jobs, installer receipts, Homebrew casks.
- `references/report-format.md`: report layout.

## Scope and limits

- macOS only. Linux package managers remove their own files.
- The scanner never deletes. Removal stays a proposed, approved
  step.
- Empty the Trash only on explicit request. Suggest waiting a few
  days so that missing data can still be restored.
