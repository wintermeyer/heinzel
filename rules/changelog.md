# Changelog

## Remote

Log to the system journal:
`logger -t heinzel "message"`. Do not add timestamps
(the system logger handles them).

Every session gets at least one entry. Reading back:
- systemd: `journalctl -t heinzel`
- macOS: `log show --predicate
  'senderImagePath CONTAINS "logger"'
  --info --last 7d | grep heinzel`

If `logger` fails, log to local `changelog.log`
only.

## Include the Why

When the reason for an action is known (from the
user's request or the surrounding context), record
it alongside the what. A future reader should be
able to tell *why* something was done, not just
that it happened.

Two acceptable shapes:

1. **Inline** — append a short `— because <reason>`
   clause to the action entry:

   ```
   logger -t heinzel \
     "Installed nginx — because user is migrating \
   vutuv.de from frankfurt2"
   ```

2. **Separate entry** — when the reason is longer
   or covers several actions, log it as its own
   entry right before or after:

   ```
   logger -t heinzel \
     "Reason: preparing bremen2 to host abuuba.de \
   podcast platform"
   logger -t heinzel "Installed postgresql-16"
   logger -t heinzel "Created database abuuba_prod"
   ```

If the reason is not known, do not invent one.
Log only the what.

## Local

Mirror entries to
`memory/servers/<hostname>/changelog.log`.
Compress the description text but keep the full
`[YYYY-MM-DD HH:MM]` timestamp.

Trim entries older than 2 years when writing.
