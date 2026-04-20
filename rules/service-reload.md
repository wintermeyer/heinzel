# Service Reload & Restart Policy

When the user asks heinzel to reload or restart a
service, this rule decides whether to run silently,
ask first, or refuse. The goal is to drop the noise
on truly low-risk operations (mainly
`systemctl reload` on things like nginx) while
keeping user control over anything that can drop
connections, lose state, or fail to come back up.

## Reload vs Restart

- **Reload** (`systemctl reload <svc>`,
  `nginx -s reload`, `service <name> reload`) tells a
  running service to re-read its config without
  dropping active connections or worker state. When
  the service supports it, reload is effectively
  zero-downtime and reversible.
- **Restart** (`systemctl restart <svc>`,
  `service <name> restart`) stops and starts the
  service. Connections drop, in-memory state is lost,
  and the restart can fail halfway (config bug,
  missing dependency, port still bound).

Prefer reload whenever the service supports it.

## Default Behavior

| Action                         | Default                              |
|--------------------------------|--------------------------------------|
| `reload <svc>`                 | auto-proceed                         |
| `restart <svc>`                | ask (with learn-this-choice options) |
| reboot / halt / poweroff       | always ask                           |
| service start (from stopped)   | always ask                           |
| failed reload or restart       | always surface, never auto-retry     |

Auto-proceed on reload requires ALL of:

- the command is `reload` (or
  `reload-or-restart` where only reload will
  execute), not `restart`.
- `<svc>` is NOT in the user's `reload-always-ask`
  list.
- we are not in read-only mode (already blocked by
  `rules/access-control.md`).
- the host is not blacklisted.
- a config test exists for the service and passes —
  see "Config Test Before Reload" below.
- the reload is not part of a firewall, SSH, or
  sshd config change (those always ask; see
  "Always Ask" below).

Auto-proceed on restart requires the service to be
explicitly listed in `restart-auto`. No heuristics.

## Config: `memory/service-policy.md`

Optional. Missing file = defaults apply. The format
mirrors `memory/blacklist.md` / `memory/readonly.md`
— plain markdown, three sections, one service name
per line, lines starting with `#` ignored.

```markdown
# Service Policy

## reload-always-ask
# Claude will ask before `systemctl reload` on these.
- postgresql

## restart-auto
# Claude may `systemctl restart` these without asking.
- nginx
- caddy

## restart-never
# Claude refuses to restart these outright, without
# prompting. Tell the user to do it manually or
# remove the entry.
- mariadb
```

Matching is by systemd unit name without the
`.service` suffix. For templated units, match the
full instance (`nginx@default`). No wildcards in v1.

On FreeBSD and macOS, match the `service` /
`brew services` / `launchctl` service name.

## Prompt Shape When Asking

When heinzel has to ask (restart not on
`restart-auto`, or reload on `reload-always-ask`),
use `AskUserQuestion` with these four options:

1. **Yes, just this once** — run the action now.
   Policy file unchanged.
2. **Yes, always (no more asking)** — run now, AND
   add the service to the right list:
   - restart → add to `restart-auto`
   - reload on `reload-always-ask` → remove from
     `reload-always-ask`
3. **No** — abort. Policy file unchanged.
4. **No, never ask again for this service** —
   abort, AND:
   - restart → add to `restart-never` (future
     restart requests for this service are refused
     outright).
   - reload → add to `reload-always-ask` (this option
     only appears if the reload was not already on
     the list).

After a write, confirm in one short line, e.g.
`Added nginx to restart-auto in memory/service-policy.md.`

### Write-Back Rules

- Preserve comments, blank lines, and section order.
- Only edit the specific list the answer affects.
- If `memory/service-policy.md` is missing, create
  it from the `.example` template with the one new
  entry added (and all commented examples intact).
- Deduplicate — never add a service already in the
  list.
- Never reorder or touch other sections.

## Config Test Before Reload

Before auto-proceeding a reload, run the service's
config test if one exists. Refuse the reload and
show the test output if it fails.

| Service        | Test command                       |
|----------------|------------------------------------|
| nginx          | `nginx -t`                         |
| caddy          | `caddy validate --config <file>`   |
| apache / httpd | `apachectl configtest`             |
| postfix        | `postfix check`                    |
| bind / named   | `named-checkconf`                  |
| sshd           | `sshd -t` (but sshd is "always ask" — see below) |
| haproxy        | `haproxy -c -f <file>`             |
| unbound        | `unbound-checkconf`                |

If the service has no known test, proceed with the
reload (they're rare; most daemons with reload
support ship a test).

## Always Ask (overrides auto-proceed)

Some reloads are too consequential to run silently,
even when the service is not in `reload-always-ask`:

- **sshd / ssh reload or restart.** A broken config
  can lock you out of the server. Always ask, even
  after `sshd -t` passes.
- **Firewall reloads** (`ufw reload`,
  `firewall-cmd --reload`, `pfctl -f`,
  `service pf reload`). A rule error can drop SSH.
  Always ask. Covered by the "firewall changes"
  rule in `CLAUDE.md`.
- **Reload as part of a config change heinzel is
  making.** If heinzel just edited
  `/etc/nginx/...` in the same session, the
  reload is still auto-proceed (the user approved
  the edit; the reload is the natural next step).
  But if heinzel is reloading to pick up changes
  from an unknown source, ask first.
- **Starting a stopped service.** Auto-proceed
  only applies to reload/restart of a service that
  is currently active. Starting from stopped is
  "ask".

## On Failure

If an auto-proceeded reload or restart fails:

- Surface the full stderr / journal output.
- Do **not** auto-fallback to `restart` when
  `reload` fails — ask the user. A failed reload
  often means broken config; a blind restart can
  turn a degraded state into a down state.
- Offer to roll back the config file from the
  backup written per `rules/backups.md`.

## Override Chain

This rule follows the standard heinzel override
chain. Later wins:

1. **Base:** `rules/service-reload.md`
2. **Global custom:** `memory/custom-rules/service-reload.md`
   (with `## Add:`, `## Replace:`, `## Remove:`
   prefixes)
3. **Per-server:** `memory/servers/<hostname>/rules.md`

The policy lists themselves
(`reload-always-ask`, `restart-auto`,
`restart-never`) can also be overridden per-server
by putting `## Replace: reload-always-ask` (or
similar) in the per-server rules file.

## Logging

Every auto-proceeded action still goes to the
changelog per `rules/changelog.md`:

```bash
logger -t heinzel "Reloaded <svc> (auto, policy)"
logger -t heinzel "Restarted <svc> (auto, policy)"
```

For asked actions, log the user's answer too:

```bash
logger -t heinzel "Restarted <svc> (user: once)"
logger -t heinzel "Restarted <svc> (user: always, added to restart-auto)"
```
