# Linux (all families)

What every systemd Linux shares. Read it together
with the family file (`rules/debian.md`,
`rules/rhel.md`, `rules/suse.md`, `rules/arch.md`);
where the two disagree, the family file wins.
Unraid has no systemd: `rules/unraid.md` replaces
the Journal and Rollback Timer sections there.

## Version Detection

- `/etc/os-release` — full distro info. The family
  file names what else to read.
- Hardware: `lscpu`, `free -h`, `df -h`.

## Firewall

- Over SSH, arm a rollback timer before any firewall
  or network change (`rules/rollback-timer.md`).
- The firewall tool's `ssh` or `OpenSSH` shortcut
  covers port 22 only: allow every port sshd listens
  on (`CLAUDE.md` → Firewall & network).

## Service Manager

- `systemctl` (systemd).
- Check service: `systemctl status <service>`
- Logs: `journalctl -u <service>`
  (`rules/log-queries.md`).
- Reload vs restart: prefer `systemctl reload` when
  the service supports it. See
  `rules/service-reload.md` for the auto-proceed
  policy and `memory/service-policy.md` opt-out /
  opt-in lists.

## Service Classes

Two class members ship inside systemd itself and are
not visible to the package DB:

- `systemd-timesyncd` (time sync)
- `systemd-resolved` (DNS resolver)

On most Debian/Ubuntu hosts they are present but
only count as a real conflict when the unit is
actually running. Probe the unit state:

```bash
systemctl is-active systemd-timesyncd 2>/dev/null
systemctl is-active systemd-resolved 2>/dev/null
```

Treat the member as "installed" only when the
output is `active`. A unit that is `inactive`,
`masked`, or absent is not a conflict — the user
already disabled it (often when they installed
chrony or unbound the first time).

The package probe and the install dry run are in
the family file.

## Listening Ports

```bash
ss -tulnp 'sport = :<port>'
```

The `-p` flag requires root to show process names.
Unprivileged fallback:

```bash
ss -tuln 'sport = :<port>'
```

## Journal

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

## Rollback Timer

- Pending window:

      systemctl list-timers --all 'heinzel-rollback-*'

- Arm:

      systemd-run --unit=heinzel-rollback-<ts> \
        --on-active=120 \
        /var/backups/heinzel/rollback-<ts>.sh

  Check it shows up in `systemctl list-timers`.
- Disarm: `systemctl stop heinzel-rollback-<ts>.timer`
- Did it run:
  `journalctl -t heinzel --since '-10 min'`

A Linux without systemd (OpenRC) uses the generic
variant in `rules/rollback-timer.md`.

## Directory Conventions

- Config files: `/etc/`
- Logs: `/var/log/`

## Common Pitfalls

- `systemctl restart` drops connections where
  `systemctl reload` would not. Reload when the
  service supports it (`rules/service-reload.md`).
- `journalctl` as a non-root user shows only that
  user's entries and says so only without `-q`.
