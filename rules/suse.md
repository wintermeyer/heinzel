# openSUSE & SLES

Rules for openSUSE (Leap, Tumbleweed) and SUSE Linux
Enterprise Server (SLES). Read `rules/linux.md` with
it: systemd, the journal, listening ports and the
rollback timer are there.

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

- `/etc/SuSE-release` — on older versions (deprecated)
- Lifecycle: suse.com/lifecycle

## Firewall

- **Expected:** `firewalld`. Commands, the SSH
  check before `systemctl start firewalld` and the
  runtime-first order are the same as in
  `rules/rhel.md` → Firewall. Read that section.
- Some systems may use SuSEfirewall2 (older) — if so,
  flag it to the user as it's deprecated.
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

## Service Classes

Installed members (`rules/service-class-check.md`,
phase 1): the `rpm -q` command from `rules/rhel.md`
→ Service Classes.

Install dry run (phase 2):

```bash
zypper --non-interactive install --dry-run <pkg>
```

## YaST

- SUSE uses YaST for system configuration. Prefer command-
  line tools for scripted operations, but be aware that YaST
  may have configured things in non-standard ways. Check
  existing config before assuming defaults.

## Directory Conventions

- Web roots: `/srv/www/htdocs/` (different from most distros)
- Nginx config: `/etc/nginx/conf.d/`

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
