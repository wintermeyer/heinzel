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

**systemd (Linux):**

```
journalctl -t heinzel --since "7 days ago" \
  --no-pager -q 2>/dev/null
```

As a non-root user outside the `systemd-journal` /
`adm` groups, `journalctl` silently shows only the
user's own entries. When connected as non-root, try
`sudo -n journalctl -t heinzel ...` first. If sudo
is unavailable, run the command without `-q` and
watch for the "not seeing messages from other
users" hint. When visibility is limited, tell the
user the activity check may be incomplete — do not
stay silent.

**macOS:**

```
/usr/bin/log show --last 7d \
  --predicate 'process == "logger"' --info 2>&1 \
  | grep heinzel
```

Two details that are not optional here:

- **Call `/usr/bin/log` by absolute path.** `log` is a
  common shell alias or function (git log wrappers,
  oh-my-zsh plugins). A shadowed `log` fails with
  something like `(eval):log:1: too many arguments`,
  which looks nothing like a missing-entries result.
- **Never redirect stderr to `/dev/null`.** With
  `2>/dev/null` a shadowed or failing `log` produces
  empty output, and "no activity" is exactly what
  empty output means below — so a broken check reads
  as a clean host. Keep `2>&1` and treat any line that
  is not a log entry as a failed check, not silence.

`senderImagePath CONTAINS "logger"` also works but
matches more broadly; `process == "logger"` is the
narrower predicate.

**FreeBSD:**

```
grep -h heinzel /var/log/messages.0 \
  /var/log/messages 2>/dev/null | tail -20
```

Note: this shows the last 20 matches, not a strict
7-day window, and only reaches one rotation back
(`messages.0`). Older rotated logs are usually
compressed; mention the limitation if relevant.

If the command returns nothing — and it actually ran,
and journal visibility is not limited (see above) —
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
