# Changelog

Two layers for two audiences:

1. **System journal** (on the server) — one-line,
   plain-language headlines for *other admins*.
   `journalctl -t heinzel` should read like a
   colleague's handover notes, not a debug dump.
2. **Local changelog**
   (`memory/servers/<hostname>/changelog.log`) — the
   full technical detail for future heinzel sessions
   and audits.

The journal headline answers *who, what, why*. The
local changelog additionally answers *how, where,
and how to undo it*.

## Journal Headlines (remote)

Log to the system journal:
`logger -t heinzel "message"`. Do not add timestamps
(the system logger handles them).

Every session gets at least one entry — sessions
that change nothing log a single `read-only:`
summary.

Reading back:
- systemd: `journalctl -t heinzel`
- macOS: `log show --predicate
  'senderImagePath CONTAINS "logger"'
  --info --last 7d | grep heinzel`
- Unraid: `grep heinzel /var/log/syslog*` — tmpfs,
  lost at every reboot (`rules/unraid.md`)

If `logger` fails, log to the local changelog only.

### Entry format

One sentence, written for a sysadmin who has never
heard of heinzel and was not part of the session:

    [<operator> as <unix-user>] <what changed, in
    plain language> — because <why>

```
logger -t heinzel "[alice as root] app.example.com \
now deploys via two alternating app slots \
(blue/green), so new releases go live without \
dropping requests — because deploys used to restart \
the app and interrupt visitors"
```

- `<operator>` is the operator name from
  `memory/user.md`; `<unix-user>` is the account the
  commands ran as (`root`, `alice`, …). Always
  include both, even when they are identical — the
  prefix is what lets admins tell each other's work
  apart.
- **Plain language.** Name the service and the
  effect an outsider can understand. No abbreviation
  soup, no command lines, no flag dumps. A version
  or path may appear when it *is* the news
  ("upgraded nginx 1.26.3-3+deb13u2 → u5").
- **One sentence, ~250 characters max.** If you are
  tempted to write more, the overflow belongs in the
  local changelog, not in the journal.
- **One entry per change, not per command.** Ten
  commands that together set up one backup job log
  one entry. Unrelated changes log separately.
- **Include the why** in the single fixed shape
  `— because <reason>` whenever the reason is known
  (from the user's request or the surrounding
  context). If the reason is not known, omit it —
  never invent one.
- **Flags for other admins get their own entry.** A
  constraint a colleague must know ("database
  migrations must now stay backward-compatible")
  deserves its own headline, not a subordinate
  clause buried in another entry.

Other rule files and skills show example message
*bodies* (e.g. `Reloaded <svc> (auto, policy)`); the
envelope above — identity prefix and `— because` —
always applies on top of them.

### What stays out of the journal

Backup file paths, commit hashes, CI run IDs,
rollback recipes, port lists, intermediate failures
and their workarounds. All of that is valuable —
record it in the local changelog (below) and in
`memory.md`, never in the headline.

## No Secrets

Credential values never go into journal or
`changelog.log` entries — record location and
permissions instead. See `rules/secrets.md`.

## Local Changelog (full detail)

Mirror every journal headline to
`memory/servers/<hostname>/changelog.log` with a
full `[YYYY-MM-DD HH:MM]` timestamp, then indent the
technical detail the journal omitted:

    [2026-06-11 09:50] [alice as root]
    app.example.com now deploys blue/green …
    — because deploys interrupted visitors
      Detail: templated app@.service (blue :4003,
      green :4005); nginx upstream moved to
      /etc/nginx/snippets/app-upstream.conf; sudoers
      rewritten for slot management.
      Rollback: re-enable app.service, restore vhost
      backup from /var/backups/heinzel/….
      Verify: ~135 HTTPS probes during two slot
      switches, all 200.
      Flags: migrations must now stay
      backward-compatible.

A new entry starts with `[` in column 1; indented
lines continue the previous entry. Use the labels
`Detail:`, `Rollback:`, `Verify:`, `Flags:` as
applicable — skip empty ones.

Trim entries older than 2 years when writing.
