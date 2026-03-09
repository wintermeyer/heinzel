# Session Lock

A courtesy lock to prevent two Claude Code sessions
from making overlapping changes on the same server.

**Lock file:** `/tmp/heinzel.lock` on the target
machine.

**Contents** (plain text, 3 lines):

```
Started: 2026-03-09 14:30
Task: Upgrading packages and configuring nginx
Expiry: at:42
```

The third line records the expiry mechanism:
`Expiry: at:<job_id>` or `Expiry: pid:<pid>`.

## When to Skip

Read-only sessions (housekeeping, security audits,
inspections, status checks) never acquire or check
the lock.

## Acquiring the Lock

Before the first modifying action on a server:

1. Check if `/tmp/heinzel.lock` exists.
2. **If it exists:** show contents. If older than
   3 hours, note it is likely stale. Ask the user:
   proceed (override) or abort.
3. **If it does not exist** (or user overrides):
   create the lock file, then start auto-expiry.

## Auto-Expiry

Set a timer to remove the lock after 3 hours:

1. Try `at` first:
   ```
   echo "rm -f /tmp/heinzel.lock" \
     | at now + 3 hours 2>/dev/null
   ```
   Parse the job ID and record `Expiry: at:<id>`.

2. If `at` fails, fall back to:
   ```
   nohup sh -c 'sleep 10800 && rm -f \
     /tmp/heinzel.lock' >/dev/null 2>&1 &
   ```
   Capture `$!` and record `Expiry: pid:<pid>`.

## Cleanup

On normal session end, read the `Expiry:` line and
cancel the timer:

- `at:<job_id>` -> `atrm <job_id>`
- `pid:<pid>` -> `kill <pid> 2>/dev/null`

Then `rm -f /tmp/heinzel.lock`.

This is a soft/courtesy mechanism. The user can
always override.
