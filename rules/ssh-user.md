# SSH User

All SSH usernames are stored in `memory/user.md` —
never in server memory files. Read this file at the
start of every session.

The file has two parts:
- **Default** — the fallback username.
- **Per-server overrides** — `- hostname: username`
  entries.

## Interview format

All interviews use a **three-option picker — no
improvisation, no bundling unrelated questions
into the same prompt**.

**Preferred (Claude Code):** use the
`AskUserQuestion` tool so the user gets a real
selectable picker. **Fallback (OpenCode or any
tool without AskUserQuestion):** print the ASCII
form and wait for `1`, `2`, or `3`.

Detect the current OS user with `whoami`
(or `$USER`).

## When to ask

### Case A — fresh install, server already specified

`memory/user.md` does not exist **and** the user
has already named a specific server
(`<hostname>`). Ask **one** combined question so
the user doesn't get two near-identical pickers
in a row. Make it explicit in the question text
that the answer becomes both the default and the
per-server entry. Question:
*"Which SSH username should heinzel use for
`<hostname>`? (This will also become your heinzel
default — you can override per server later.)"*

Options:

1. `<current-os-user>` — "you, the user running heinzel"
2. `root` — "connect as root directly"
3. `Other…` — "type a different name"

ASCII form:

```
Which SSH username should heinzel use for <hostname>?
(Also saved as your heinzel default.)

  1. <current-os-user>   (you, the user running heinzel)
  2. root
  3. other…              (type a different name)

[1/2/3]:
```

Write `memory/user.md` with the chosen name as
**both** `Default:` and the `- <hostname>:` entry,
in a single file write.

### Case B — fresh install, no server specified yet

`memory/user.md` does not exist and the user ran
`claude` / `opencode` with no target in mind.
Ask only for the default:
*"Which SSH username should heinzel use by
default?"* with the same three options. Write
only `Default:` to `memory/user.md`; do not
invent a per-server entry.

### Case C — default exists, first connection to a new server

`memory/user.md` exists but has no entry for
`<hostname>`. Ask the per-server question:
*"Which SSH username should heinzel use for
`<hostname>`?"* with:

1. `<memory-default>` — "your heinzel default"
2. `root` — "connect as root directly"
3. `Other…` — "type a different name"

If the memory default is already `root`, collapse
options 1 and 2 into a single `root` entry and
keep `Other…` as option 2. Save the choice as a
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
