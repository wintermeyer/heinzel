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

**systemd (Linux, FreeBSD with systemd):**

```
journalctl -t heinzel --since "7 days ago" \
  --no-pager -q 2>/dev/null
```

**macOS:**

```
log show --predicate 'senderImagePath CONTAINS "logger"' \
  --info --last 7d 2>/dev/null | grep heinzel
```

**FreeBSD without systemd:**

```
grep heinzel /var/log/messages 2>/dev/null | \
  tail -20
```

If the command fails or returns nothing, skip
silently — no activity to report.

## What to show

If there are entries, show a brief summary to the
user:

```
Recent heinzel activity (last 7 days):
- [2026-04-12 14:32] Installed nginx, opened port 443
- [2026-04-11 09:15] Updated Node.js 22.14 → 22.15
```

- Group related entries when possible.
- Keep it concise — summarize, don't dump raw logs.
- If there are more than 10 entries, summarize the
  oldest and show the most recent 5 in detail.

## No activity

If the journal has no heinzel entries, say nothing.
Do not report "no recent activity" — silence means
no news.
