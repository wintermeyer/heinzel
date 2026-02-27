# openSUSE & SLES

Rules for openSUSE (Leap, Tumbleweed) and SUSE Linux
Enterprise Server (SLES).

## Package Manager

- Use `zypper`
- Update repos: `zypper refresh`
- Upgrade all: `zypper update`
- Install: `zypper install <package>`
- Dry-run before upgrading: `zypper --dry-run update`
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
- Verify the default zone drops unsolicited traffic:
  `firewall-cmd --get-default-zone` (should be `public`).
  Then `firewall-cmd --info-zone=public` — the target
  should be `default` (which means reject). If the zone
  target is `ACCEPT`, fix with
  `firewall-cmd --permanent --zone=public
  --set-target=default` and `firewall-cmd --reload`.

## Automatic Security Updates

- openSUSE/SLES can use a cron job or systemd timer with
  `zypper --non-interactive update --auto-agree-with-licenses`
- SLES may also use `yast2` for auto-update configuration.
- If no auto-update is configured, flag it to the user.

## Service Manager

- `systemctl` (systemd)
- Check service: `systemctl status <service>`
- Logs: `journalctl -u <service>`

## YaST

- SUSE uses YaST for system configuration. Prefer command-
  line tools for scripted operations, but be aware that YaST
  may have configured things in non-standard ways.

## Directory Conventions

- Config files: `/etc/`
- Web roots: `/srv/www/htdocs/` (different from most distros)
- Logs: `/var/log/`
- Nginx config: `/etc/nginx/conf.d/`

## Notes

- openSUSE Tumbleweed is a rolling release — package
  versions change frequently.
- openSUSE Leap and SLES share the same base and are more
  stable/predictable.
- The `zypper` package manager is interactive by default —
  always use `--non-interactive` for scripted operations.

## Common Pitfalls

- `zypper` is interactive by default — always use
  `--non-interactive` for scripted/SSH commands.
- Web root is `/srv/www/htdocs/`, not `/var/www/`.
  Nginx config is in `/etc/nginx/conf.d/`, not
  `sites-available/`.
- `firewalld` is shared with RHEL but zone defaults
  may differ. Check `firewall-cmd --get-active-zones`
  before making changes.
- YaST may have configured things in non-standard
  ways. Check existing config before assuming defaults.
- Tumbleweed is rolling release — package versions
  and behavior change frequently. Leap/SLES are
  stable.
