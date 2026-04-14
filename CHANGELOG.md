# Changelog

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
