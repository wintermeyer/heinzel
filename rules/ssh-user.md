# SSH User

All SSH usernames are stored in `memory/user.md` —
never in server memory files. Read this file at the
start of every session.

The file has two parts:
- **Default** — the fallback username.
- **Per-server overrides** — `- hostname: username`
  entries.

**If `memory/user.md` does not exist:** ask the
user which username to use as the default. Detect
the current OS user with `whoami` (or `$USER`) and
present a **three-option interview — no
improvisation, no bundling extra questions into
the prompt**.

**Preferred (Claude Code):** use the
`AskUserQuestion` tool so the user gets a real
selectable picker. Question:
*"Which SSH username should heinzel use by
default?"* with options:

1. `<current-os-user>` — "you, the user running heinzel"
2. `root` — "connect as root directly"
3. `Other…` — "type a different name" (user fills
   in via the Other field)

**Fallback (OpenCode or any tool without
AskUserQuestion):** print the ASCII form and wait
for `1`, `2`, or `3`:

```
Which SSH username should heinzel use by default?

  1. <current-os-user>   (you, the user running heinzel)
  2. root
  3. other…              (type a different name)

[1/2/3]:
```

Save the chosen name as the `Default:` in
`memory/user.md`.

**On first connection to a new server:** ask which
SSH username to use, again as a three-option
interview. Same tool preference as above —
`AskUserQuestion` in Claude Code, ASCII fallback
elsewhere. ASCII form:

```
Which SSH username should heinzel use for <hostname>?

  1. <memory-default>    (your heinzel default)
  2. root
  3. other…              (type a different name)

[1/2/3]:
```

If the memory default is already `root`, collapse
options 1 and 2 into a single `root` entry and
keep `other…` as option 2. Save the choice as a
per-server override in `memory/user.md`.

**On subsequent connections:** look up the server in
`memory/user.md`. Do not ask again.

When the user explicitly specifies a username on the
command line, skip the interview, use that name, and
update `memory/user.md`.

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
