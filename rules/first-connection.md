# First-Connection Checklist

The ordered pipeline that runs on **every** remote
connection — and on every local-mode session, with
the remote-only steps skipped — before any
user-requested command.

**There is no "quick question" exception.** `df -h`,
`uptime`, `uname -a`, and every other "one-liner"
runs this pipeline first. If following the pipeline
will visibly delay the answer, say so up front
("first-contact onboarding on this host — one
moment") — don't skip.

## Order

A target written with a port (`host:2222`,
`ssh://user@host:2222`) is split first: every step
below uses the bare hostname, and step 5 takes the
port (`rules/ssh-port.md` → Known port).

1. **Blacklist check.** Refuse if listed. See
   `rules/access-control.md`.
2. **Read-only check.** Switch to read-only mode if
   listed. See `rules/access-control.md`.
3. **Path access control.** Load the host's section
   of `memory/protected-paths.md`, if present, and
   apply it for the rest of the session. See
   "Path Access Control" below.
4. **DNS check.** New hostname (no
   `memory/servers/<hostname>/` yet): run alias
   detection. Known hostname: verify the current IP
   still matches the `- IP:` field in server memory.
   See `rules/dns-aliases.md` for both.
5. **SSH user and port lookup.** User: first
   connection only, see `rules/ssh-user.md`. Port:
   the one the user named, else `- SSH port:` from
   the memory read in step 4; a new host without one
   goes through `rules/ssh-port.md` → first contact.
6. **OS detection.** See `rules/os-detection.md`.
7. **Server memory file.** Create on first
   connection, read on every subsequent connection.
   See `rules/server-memory.md`.
8. **Activity check.** Every connection, not just
   the first. See `rules/activity-check.md`.
9. **Then** execute the user's request.

## Local mode

In local mode (`localhost`, the user's own
hostname), skip steps 1, 2, 4 and 5 — they are
remote-only
(see `CLAUDE.md` → How It Works → Local mode).
Still run OS detection, server memory, and activity
check.

## Path Access Control

Some paths on a server need more care than the
server as a whole: a directory with family data that
must not change, a file with secrets, a config that
only the user may touch. `memory/protected-paths.md`
lists them per server. It is personal, like
`memory/blacklist.md`, and created on first need.

One `##` section per server, matched like the
entries in `rules/access-control.md` (hostname or
IP, DNS aliases resolved). Each section has up to
three lists, one glob per line; an optional leading
`- `, `#` comments and blank lines are ignored:

```markdown
## 192.0.2.10

### readonly
- /srv/photos/**

### hidden
- **/.env

### confirm
- /etc/nginx/sites-enabled/**
```

- **`readonly`** — reading, listing and `stat` are
  fine. Writing, deleting, moving, renaming,
  `chmod`/`chown` and any command that changes
  content or permissions are refused: "`<path>` is
  marked read-only in `memory/protected-paths.md`."
  No override in the session; carry on with the
  rest of the task.
- **`confirm`** — before any command that touches
  the path, show the exact command and wait for the
  user to reply with the word `CONFIRM`. Approving
  the tool call is not enough.
- **`hidden`** — the content is never read or
  shown. See `rules/secrets.md` → "Paths Marked
  Hidden".

Precedence, strongest first: server blacklist and
read-only list > `hidden` > `confirm` > `readonly`
> no entry. A glob is a hint, not a sandbox: also
treat commands that reach a protected path
indirectly (a recursive copy of its parent, a
`find … -delete` above it) as touching it.

## Why it's mandatory

Skipping steps has caused real incidents: stale
memory files masking ownership changes, activity
checks missing concurrent teammate work, and
blacklisted hosts getting commands they should
never receive. The overhead of a few extra commands
is acceptable; silent skipping is a bug.
