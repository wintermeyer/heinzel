# openSUSE & SLES

Rules for openSUSE (Leap, Tumbleweed) and SUSE Linux
Enterprise Server (SLES).

## Package Manager

- Use `zypper`
- Update repos: `zypper refresh`
- Upgrade all: `zypper update`
- Install: `zypper install <package>`
- Dry-run before upgrading: `zypper update --dry-run`
  (`--dry-run` goes after the command — verify with
  `zypper help update` first)
- Non-interactive: `zypper --non-interactive install <pkg>`

## Version Detection

- `/etc/os-release` — full distro info
- `/etc/SuSE-release` — on older versions (deprecated)

## Firewall

- **Expected:** `firewalld`
- Check status: `firewall-cmd --state`
- List rules: `firewall-cmd --list-all`
- Add rule: `firewall-cmd --permanent --add-service=http`
- Reload: `firewall-cmd --reload`
- Some systems may use SuSEfirewall2 (older) — if so,
  flag it to the user as it's deprecated.
- **Critical:** before `systemctl start firewalld` on
  a remote host, verify the `ssh` service is in the
  active/default zone's permanent config:
  `firewall-cmd --permanent --zone=<zone>
  --list-services`. Add it if missing:
  `firewall-cmd --permanent --zone=<zone>
  --add-service=ssh`. Starting `firewalld` without it
  cuts off the SSH session immediately.
- Verify the default zone drops unsolicited traffic:
  `firewall-cmd --get-default-zone` (should be `public`).
  Then `firewall-cmd --info-zone=public` — the target
  should be `default` (which means reject). If the zone
  target is `ACCEPT`, fix with
  `firewall-cmd --permanent --zone=public
  --set-target=default` and `firewall-cmd --reload`.

## Automatic Security Updates

- Prefer **security-only** patching via a cron job or
  systemd timer, e.g.
  `zypper --non-interactive patch --category security`
  — verify the exact syntax with `zypper help patch`
  first; it varies between versions.
- Do **not** schedule a full
  `zypper --non-interactive update` — that upgrades
  every package nightly, not just security fixes.
- On SLES, YaST Online Update is the supported
  mechanism for configuring automatic updates.
- If no auto-update is configured, flag it to the user.

## Service Manager

- `systemctl` (systemd)
- Check service: `systemctl status <service>`
- Logs: `journalctl -u <service>`
- Reload vs restart: prefer `systemctl reload` when
  the service supports it. See
  `rules/service-reload.md` for the auto-proceed
  policy and `memory/service-policy.md` opt-out /
  opt-in lists.

## YaST

- SUSE uses YaST for system configuration. Prefer command-
  line tools for scripted operations, but be aware that YaST
  may have configured things in non-standard ways. Check
  existing config before assuming defaults.

## Directory Conventions

- Config files: `/etc/`
- Web roots: `/srv/www/htdocs/` (different from most distros)
- Logs: `/var/log/`
- Nginx config: `/etc/nginx/conf.d/`

## Vendor Defaults under /usr (Tumbleweed)

Tumbleweed ships some defaults under `/usr` instead of
`/etc`: `/usr/etc/nsswitch.conf`, `/usr/etc/sudoers`
(mode `0444`), `/usr/lib/pam.d/`. A file of the same
name in `/etc` replaces the default. Probes read both,
`/etc` first. Edit only in `/etc`: an update overwrites
`/usr`. `visudo -c` calls the `0444` vendor file "bad
permissions" and exits 1; sudo still reads it, and
that alone is not a finding. Leap keeps them in `/etc`.

## Notes

- openSUSE Tumbleweed is a rolling release — package
  versions change frequently.
- openSUSE Leap and SLES share the same base and are more
  stable/predictable.

## Common Pitfalls

- `zypper` is interactive by default — always use
  `--non-interactive` for scripted/SSH commands.
- Web root is `/srv/www/htdocs/`, not `/var/www/`.
  Nginx config is in `/etc/nginx/conf.d/`, not
  `sites-available/`.
- `firewalld` is shared with RHEL but zone defaults
  may differ. Check `firewall-cmd --get-active-zones`
  before making changes.
- YaST quirks: see the YaST section above.
