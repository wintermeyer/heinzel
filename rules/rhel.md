# RHEL, CentOS, Fedora, Rocky Linux, AlmaLinux

Rules for the Red Hat family of distributions.

## Package Manager

- **RHEL 8+, Fedora, Rocky, Alma:** use `dnf`
- **RHEL 7, CentOS 7:** use `yum`
- Dry-run before upgrading: `dnf --assumeno update`
  (or `yum --assumeno update`)
- Non-interactive install: `dnf install -y <package>`

To determine which to use, check the OS version from
`/etc/os-release`. RHEL/CentOS 7 uses `yum`; everything
newer uses `dnf`.

## Version Detection

- `/etc/redhat-release` — distro and version string
- `/etc/os-release` — full distro info

## Firewall

- **Expected:** `firewalld`
- Check status: `firewall-cmd --state`
- List rules: `firewall-cmd --list-all`
- Add rule: `firewall-cmd --permanent --add-service=http`
- Reload: `firewall-cmd --reload`
- If `firewalld` is not running, flag it to the user.
- Verify the default zone drops unsolicited traffic:
  `firewall-cmd --get-default-zone` (should be `public`).
  Then `firewall-cmd --info-zone=public` — the target
  should be `default` (which means reject). If the zone
  target is `ACCEPT`, fix with
  `firewall-cmd --permanent --zone=public
  --set-target=default` and `firewall-cmd --reload`.

## Automatic Security Updates

- **Expected:** `dnf-automatic`
- Config: `/etc/dnf/automatic.conf`
- Check if active:
  `systemctl status dnf-automatic-install.timer`
- On RHEL 7/CentOS 7: `yum-cron` instead

## Service Manager

- `systemctl` (systemd)
- Check service: `systemctl status <service>`
- Logs: `journalctl -u <service>`

## SELinux

- RHEL-family systems typically have SELinux enabled.
- Check status: `getenforce`
- If a service isn't working after configuration, SELinux
  may be blocking it. Check: `ausearch -m avc -ts recent`
- Do **not** disable SELinux without discussing with the
  user. Prefer adding proper SELinux policies.

## Directory Conventions

- Config files: `/etc/`
- Web roots: `/var/www/` or `/usr/share/nginx/html/`
- Logs: `/var/log/`
- Nginx config: `/etc/nginx/conf.d/`
  (no sites-available/sites-enabled pattern)

## Notes

- EPEL (Extra Packages for Enterprise Linux) is a common
  third-party repo on RHEL/CentOS. Only enable it if
  needed and with user approval.
- Fedora is a fast-moving distro — package versions and
  available packages differ significantly from RHEL.

## Common Pitfalls

- `dnf` vs `yum` — check the OS version first.
  RHEL/CentOS 7 uses `yum`, everything newer uses
  `dnf`. Running the wrong one may fail or behave
  unexpectedly.
- `firewall-cmd` changes are temporary by default.
  Always use `--permanent` and then `--reload`.
  Forgetting `--permanent` means rules vanish on
  reboot.
- SELinux blocks are silent by default. If a service
  fails after correct configuration, check
  `ausearch -m avc -ts recent` before assuming the
  config is wrong.
- RHEL 8+ uses `nftables` as the backend for
  `firewalld`. Do not mix `iptables` commands with
  `firewalld` — they will conflict.
- EPEL is not enabled by default. Do not assume EPEL
  packages are available without first checking.
