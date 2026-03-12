# SSH User

All SSH usernames are stored in `memory/user.md` —
never in server memory files. Read this file at the
start of every session.

The file has two parts:
- **Default** — the fallback username.
- **Per-server overrides** — `- hostname: username`
  entries.

**If `memory/user.md` does not exist:** ask the user
their typical username, then save it.

**On first connection to a new server:** ask which
SSH username to use, suggesting the default. Save as
a per-server override in `memory/user.md`.

**On subsequent connections:** look up the server in
`memory/user.md`. Do not ask again.

When the user explicitly specifies a username, use
that and update `memory/user.md`.

## User Language

**File:** `memory/user.md` (same file as SSH
usernames).

heinzel communicates in the user's preferred
language. The preference is set under a
`# Preferences` heading (e.g. `Language: German`).
Default to English if missing.

**What to translate:** all conversational output.

**What stays in English:** shell commands, file
paths, package names, technical terms, server memory
files, log entries, config files, rule files.

**When the user writes in a specific language:**
respond in that language regardless of the setting.
