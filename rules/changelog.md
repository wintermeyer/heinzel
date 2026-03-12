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

## Local

Mirror entries to
`memory/servers/<hostname>/changelog.log`.
Compress the description text but keep the full
`[YYYY-MM-DD HH:MM]` timestamp.

Trim entries older than 2 years when writing.
