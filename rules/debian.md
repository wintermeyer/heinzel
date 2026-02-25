# Debian & Ubuntu

Rules for Debian, Ubuntu, and derivatives.

## Package Manager

- Use `apt-get` (not `apt`) — it's more reliable for
  non-interactive/scripted use.
- Always run `apt-get update` before installing or upgrading.
- Dry-run before upgrading: `apt-get --dry-run upgrade`
- Non-interactive install: `apt-get install -y <package>`

## Version Detection

- `/etc/debian_version` — Debian version number
- `/etc/os-release` — full distro info
- `lsb_release -a` — if `lsb-release` is installed

## Firewall

- **Expected:** `ufw` (Uncomplicated Firewall)
- Check status: `ufw status verbose`
- If `ufw` is not installed, flag it to the user.

## Automatic Security Updates

- **Expected:** `unattended-upgrades`
- Config: `/etc/apt/apt.conf.d/50unattended-upgrades`
- Check if active: `systemctl status unattended-upgrades`
- If not installed, flag it to the user.

## Service Manager

- `systemctl` (systemd)
- Check service: `systemctl status <service>`
- Logs: `journalctl -u <service>`

## Directory Conventions

- Config files: `/etc/`
- Web roots: `/var/www/`
- Logs: `/var/log/`
- Sites config (nginx): `/etc/nginx/sites-available/` and
  `/etc/nginx/sites-enabled/`
- Sites config (Apache): `/etc/apache2/sites-available/` and
  `/etc/apache2/sites-enabled/`

## Notes

- Debian and Ubuntu use the same package manager and mostly
  the same conventions, but package names and available
  versions may differ.
- Ubuntu may have `snap` packages — prefer `apt-get` unless
  the user specifically wants snaps.
