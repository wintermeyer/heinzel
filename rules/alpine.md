# Alpine Linux

Rules for Alpine Linux.

## Package Manager

- Use `apk`
- Update index: `apk update`
- Upgrade all: `apk upgrade`
- Install: `apk add <package>`
- Dry-run before upgrading: `apk upgrade --simulate`

## Version Detection

- `/etc/alpine-release` — version number
- `/etc/os-release` — full distro info

## Firewall

- Alpine does not ship a firewall by default.
- Common options: `iptables`, `nftables`, or `awall`
  (Alpine Wall, a frontend for iptables).
- Check if iptables has rules: `iptables -L -n`
- If no firewall is configured, flag it to the user.

## Automatic Security Updates

- Alpine has no built-in auto-update mechanism.
- If the user wants automatic updates, a cron job running
  `apk upgrade` is the typical approach.
- Flag the lack of auto-updates to the user.

## Init System

- **Alpine uses OpenRC, not systemd.**
- Check service: `rc-service <service> status`
- Start/stop: `rc-service <service> start|stop|restart`
- Enable on boot: `rc-update add <service> default`
- List services: `rc-status`
- Logs: typically in `/var/log/` (no journalctl)

## Directory Conventions

- Config files: `/etc/`
- Alpine uses `busybox` — many standard tools are
  lightweight alternatives with fewer options.
- Default shell is `ash` (via busybox), not `bash`.
  Commands must be POSIX-compatible.

## Notes

- Alpine is minimal by design. Many tools you'd expect on
  other distros are not installed by default (e.g. `curl`,
  `bash`, `less`). Install them as needed.
- Alpine uses `musl libc` instead of `glibc`. Some binaries
  compiled for other distros won't work.
- Packages use a different naming convention — when in
  doubt, search with `apk search <keyword>`.
