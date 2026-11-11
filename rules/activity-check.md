# Activity Check

On **every** connection to a server (remote or
local), check for recent heinzel activity in the
system journal. This keeps the user informed about
changes made by other team members or previous
sessions.

## When to run

After reading the server memory file and before
starting any requested work. This applies to every
connection, not just the first of the day.

## How to check

Run the command from the **Journal** section of the
host's OS file: `rules/linux.md` for every systemd
Linux, `rules/unraid.md` → Journal Replacement,
else `rules/freebsd.md`, `rules/netbsd.md`,
`rules/openbsd.md` or `rules/macos.md`. The section
also says how far back the command reaches and when
its result is incomplete; pass that on to the user.

If the command returns nothing — and it actually ran,
and journal visibility is not limited (see the
Journal section) —
skip silently: no activity to report.

An empty result only means "no activity" when the
command succeeded. If it errored, was shadowed by a
shell alias, or you sent its stderr to `/dev/null`,
you have no result at all — tell the user the check
did not run, rather than reporting silence. A failed
check that reads as a clean host is how a concurrent
session's work goes unnoticed.

## What to show

If there are entries, show a brief summary to the
user:

```
Recent heinzel activity (last 7 days):
- [2026-04-12 14:32] [alice as root] Installed nginx,
  opened port 443 — because static site launch
- [2026-04-11 09:15] [bob as bob] Updated Node.js
  22.14 → 22.15
```

- Group related entries when possible.
- Keep it concise — summarize, don't dump raw logs.
- If there are more than 10 entries, summarize the
  oldest and show the most recent 5 in detail.

## No activity

If the journal has no heinzel entries, say nothing.
Do not report "no recent activity" — silence means
no news.
