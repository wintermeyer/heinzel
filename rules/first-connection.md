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

1. **Blacklist check.** Refuse if listed. See
   `rules/access-control.md`.
2. **Read-only check.** Switch to read-only mode if
   listed. See `rules/access-control.md`.
3. **DNS alias detection** (only when no
   `memory/servers/<hostname>/` exists yet). See
   `rules/dns-aliases.md`.
4. **SSH user lookup** (first connection only). See
   `rules/ssh-user.md`.
5. **OS detection.** See `rules/os-detection.md`.
6. **Server memory file.** Create on first
   connection, read on every subsequent connection.
   See `rules/server-memory.md`.
7. **Activity check.** Every connection, not just
   the first. See `rules/activity-check.md`.
8. **Then** execute the user's request.

## Local mode

In local mode (`localhost`, the user's own
hostname), skip steps 1–4 — they are remote-only
(see `CLAUDE.md` → How It Works → Local mode).
Still run OS detection, server memory, and activity
check.

## Why it's mandatory

Skipping steps has caused real incidents: stale
memory files masking ownership changes, activity
checks missing concurrent teammate work, and
blacklisted hosts getting commands they should
never receive. The overhead of a few extra commands
is acceptable; silent skipping is a bug.
