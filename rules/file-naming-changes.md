# Changing How Files Are Named or Where They Live

Retention settings, rotation schemes, backup suffixes
and directory moves all change *strings that other
code matches on*. The change itself is visible and
usually tested; the breakage it causes elsewhere is
silent. Two mandatory steps.

## 1. Find every consumer that matches by pattern

Before applying a naming or location change, search
the host for code that identifies those files by
pattern rather than by name:

```
grep -rn '<old-path-or-stem>' /etc /usr/local \
  /root /home/*/bin 2>/dev/null
```

Check at least: cleanup and deletion scripts, cron
jobs and systemd units, log shippers and parsers,
backup include/exclude lists, `find` invocations, and
monitoring checks. For each hit, ask whether its glob
or regex still matches after the change.

A deletion that no longer matches is the dangerous
case, because nothing fails: the command exits 0,
having deleted nothing, and the data it was supposed
to remove stays on disk under the new retention — the
longer retention you just configured. A cleanup
script written for numbered rotations
(`rm -f "$LOG" "$LOG".*`) silently stops covering
date-stamped ones (`app.log-20260731.gz` — hyphen,
not dot) the moment `dateext` is switched on.

Match the *thing*, not one spelling of it. Widen the
consumer's pattern in the same change that alters the
naming, never as a follow-up. Where the consumer
handles sensitive data, confirm afterwards that no
file survives under either spelling.

## 2. Dry-run any bulk rename, with collision checks

Never rename or move files in bulk in one pass. First
produce the full old→new list, count collisions, and
print it. Refuse to proceed while any collision
remains — a collision means the derivation rule is
wrong, not that one file is awkward.

Derive the new name from something authoritative, and
**verify the derivation against file content, not
just metadata**. Timestamps are suggestive, content is
proof: open the first and last record of a sample and
confirm they fall where the new name claims. Deriving
a log's date from mtime alone breaks on sparsely
written files, where mtime may sit either side of the
rotation window; the resulting duplicates are how you
find out the rule was wrong.

Write the mapping to `/var/backups/heinzel/` as
`<scheme>-rename-map-<timestamp>.txt` (new TAB old) so
the rename can be replayed backwards, and use
`mv -n` so an unforeseen collision cannot overwrite.

## 3. Say what the retention now costs

When retention grows, state the measured volume per
day and the resulting total, and check it against free
space — measure from files already on disk, never
estimate. Two consequences deserve their own mention
to the user because they are easy to miss:

- **File count.** Daily rotation over years produces
  thousands of files per directory.
- **Personal data.** Web server access logs hold full
  client IP addresses. Extending retention extends how
  long those are kept, which is a data protection
  question, not a disk space one. Raise it; offer
  truncation at rotation time; let the user decide.
