# Changelog

## 2.0.1 — 2026-04-14

- `bin/heinzel-backup` now uses `mktemp
  "${TMPDIR:-/tmp}/heinzel-backup.XXXXXX"` instead
  of `mktemp -t`, which differs between BSD (macOS)
  and GNU (Linux) — the old form worked by
  accident on macOS but produced an awkward file
  name on Linux
- README Project Structure tree now lists
  `rules/activity-check.md` and
  `rules/best-practices.md`, which were inventoried
  missing during the 2.0 audit

## 2.0.0 — 2026-04-14

**BREAKING:** All user state is now consolidated
under `memory/`. Backups are a single
`tar czf backup.tgz memory/` — no more tracking
three scattered locations.

- `rules/custom/` → `memory/custom-rules/`
- `opencode.json` → `memory/opencode.json`
- `opencode.json.example` → `memory/opencode.json.example`
- `.gitignore` rewritten around the new single
  user-state root with team-mode opt-in comments
- New `bin/heinzel-backup` script: dry-run, backup,
  and restore a `memory/` archive. Restore
  validates entries live under `memory/` and
  refuses to overwrite existing state without
  `--force`
- Auto-migration: `.claude/hooks/check-updates.sh`
  now detects the 1.x layout on session start and
  moves files into place, idempotently
- README gained a "Backup & Restore" section and a
  "Upgrading from 1.x to 2.0.0" walkthrough

Why: previously, user state was spread across
`memory/*`, `rules/custom/`, and the repo-root
`opencode.json`, which made backups a scripted
operation rather than a one-liner and required
multiple `.gitignore` blocks that had drifted
apart. Pulling everything under `memory/` makes the
mental model, the gitignore, and the backup story
all collapse to one directory.

Users on pinned 1.x tags won't be affected until
they unpin; everyone on `main` gets auto-migrated
on the next Claude Code session start. OpenCode
users or anyone bypassing the hook should run
`bin/heinzel-update` (or follow the manual steps
in the README's upgrade section).

## 1.0.6 — 2026-04-14

- Reframed the "Risks & Responsibilities" section:
  Heinzel is now positioned as a help for everybody
  — newcomers and veterans alike — rather than a
  tool only for experienced sysadmins, while being
  honest that no guarantee is possible

## 1.0.5 — 2026-04-14

- Merged the duplicate "Getting Started" section
  into "How to Install": Prerequisites and Team
  setup are now subsections of install, removing
  two parallel install guides
- Renamed the Features entry "Auto-detection" to
  "Auto OS-detection" and dropped its example
  prompt snippets

## 1.0.4 — 2026-04-14

- README install guide now mentions that Heinzel
  asks a few questions on the first connection
  (e.g. which SSH user) and remembers the answers

## 1.0.3 — 2026-04-14

- README restructured: renamed "How It Works" to
  "How to Install", promoted feature showcases into
  a dedicated "Features" section, moved
  "Updates & Versioning" directly after install, and
  replaced generic "the AI" phrasing with "Heinzel"
  for a consistent voice
- Clarified in the README that auto-update is
  skipped when pinned to a tag, on a non-`main`
  branch, or when `HEINZEL_NO_UPDATE=1`

## 1.0.2 — 2026-04-14

- Changelog rule now records the *why* of an action
  (inline `— because <reason>` or separate `Reason:`
  entry) when the motivation is known

## 1.0.0 — 2026-04-13

- Initial versioned release
- Auto-update hook with version awareness
- Version pinning support via git tags
- Standalone update script for OpenCode users
