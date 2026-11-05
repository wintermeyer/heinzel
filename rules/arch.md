# Arch Linux & CachyOS

Rules for Arch Linux and distributions with
`ID_LIKE=arch` in `/etc/os-release` (CachyOS,
EndeavourOS and others). Derivatives add their own
repos to `/etc/pacman.conf`; read it on first
contact.

## Rolling Release

Arch has no releases, no stable branch and no
security-only channel. The supported state is "every
package at the version the repos hold today". So:

- An upgrade is always the whole system:
  `pacman -Syu --noconfirm`. Ask first, it is never
  a small change.
- **Never a partial upgrade.** Never `pacman -Sy`,
  `pacman -Sy <pkg>`, or `pacman -Syuw`: they sync
  the database without upgrading, and the next
  install links against libraries the system does
  not have.
- If `pacman -Syu` fails halfway, finish that
  upgrade before any other package operation.
- Before an upgrade, check the Arch news
  (archlinux.org/news) for a manual step, and follow
  every alert `pacman` prints during the run.
- The stable track is the plain repos without the
  testing ones. Flag `[core-testing]`,
  `[extra-testing]` or any other `*-testing` section
  enabled in `/etc/pacman.conf` as **WARN**.
- Do not hold packages back with `IgnorePkg` or
  `IgnoreGroup`: a held package is a partial upgrade
  that lasts.

## Package Manager

- Use `pacman` as root. AUR helpers (`paru`, `yay`)
  refuse to run as root and build from the AUR.
- Pending updates without touching the system
  database: `checkupdates` (package
  `pacman-contrib`, no root needed). Exit 0 lists
  updates, 2 means none, 1 is an error.
- Install: `pacman -S --needed --noconfirm <pkg>`,
  only when `checkupdates` reports nothing.
  Otherwise the install is a full upgrade
  (`pacman -Syu --needed --noconfirm <pkg>`) and is
  asked for as one.
- Dry-run: `pacman -S --print --print-format
  '%n %v' <pkg>` lists every package the install
  would bring, dependencies included.
- Known vulnerabilities: `arch-audit -u` lists
  installed packages with a fixed version in the
  repos (package `arch-audit`, reads
  security.archlinux.org). That count stands in for
  "pending security updates".
- History: `/var/log/pacman.log`. Last full upgrade:
  `grep 'starting full system upgrade'
  /var/log/pacman.log | tail -1`.
- Foreign packages (AUR, hand-built):
  `pacman -Qm`. Orphans: `pacman -Qdtq`.
- Package cache: `/var/cache/pacman/pkg/`. It is the
  way back for an upgrade
  (`pacman -U /var/cache/pacman/pkg/<file>`), so
  trimming it asks first: `paccache -rk2` keeps two
  versions per package.

## AUR

The AUR is user-submitted build scripts, not an
official repo. Install from it only on explicit user
request, read the `PKGBUILD` first, and record each
AUR package in server memory: AUR packages do not
upgrade with `pacman -Syu` and break silently on a
library soname bump.

## Config Files (.pacnew)

`pacman` never overwrites a changed config file. It
writes the new default beside it as `.pacnew` (or
keeps the old one as `.pacsave` on removal):

```
find /etc -name '*.pacnew' -o -name '*.pacsave'
```

Merge by hand, with a backup (`rules/backups.md`).
Never run `pacdiff` over SSH: it opens `vimdiff` and
waits for a terminal.

## Version Detection

- `/etc/os-release`: `ID`, `ID_LIKE`, `BUILD_ID`.
  There is no `VERSION_ID`; a rolling host has no
  version to compare. Report the date of the last
  full upgrade instead.
- Running kernel: `uname -r`. Kernel package:
  `linux`, `linux-lts`, on CachyOS `linux-cachyos`
  and variants (`pacman -Qq | grep '^linux'`).

## Firewall

- **Arch:** installs no firewall. Flag it like any
  Linux host without one.
- **CachyOS:** ufw is enabled after installation,
  default deny incoming.
- ufw works as in `rules/debian.md` (allow every sshd
  port before `ufw enable`), plus: `ufw.service`
  must be enabled to survive a reboot, and must not
  run beside an enabled `iptables.service`.
- **Native nftables:** Arch's stock
  `/etc/nftables.conf` drops input and allows
  `tcp dport ssh`, which is port 22 only. On a host
  whose sshd listens elsewhere, starting
  `nftables.service` with it locks you out. Read the
  file and the sshd ports (`CLAUDE.md` → Firewall &
  network) before enabling it.
- Over SSH, arm a rollback timer before any firewall
  or network change (`rules/rollback-timer.md`).

## Automatic Updates

Arch ships no unattended upgrade and does not expect
one: an upgrade can need a manual step from the news.
heinzel does not install one and does not flag its
absence. It reports instead:

- the days since the last full upgrade (**WARN**
  past 30 days),
- `arch-audit -u` findings (**WARN** if any).

**CachyOS** offers optional timers: the system units
`pacman-offline-prepare.timer` (downloads updates)
and `pacman-offline-reboot.timer` (reboots to apply
them, default 03:00 plus up to two hours), and the
user unit `arch-update.timer` (update check with a
desktop notification). Report their state. Enabling them is the
user's decision: the reboot timer restarts the host
unattended.

## Kernel and Reboots

Installing a new kernel package deletes
`/usr/lib/modules/<running version>/`. Until the
reboot, no new module loads: a USB disk, a new
filesystem type or a network driver not yet in use
fails. Check:

```
[ -d "/usr/lib/modules/$(uname -r)" ] \
  || echo "reboot needed: running kernel's modules removed"
```

After an upgrade that touched a kernel package, tell
the user a reboot is due (asking per `CLAUDE.md`).
Services keep old libraries mapped until restarted;
use the binary-vs-process check from
`heinzel-housekeeping` → `baseline-linux.md`.

## Service Manager

- `systemctl` (systemd). SSH daemon: `sshd.service`.
- Logs: `journalctl -u <service>`
  (`rules/log-queries.md`).
- Reload vs restart: `rules/service-reload.md`.

## Directory Conventions

- Web root: `/srv/http/`. nginx serves
  `/usr/share/nginx/html/` out of the box.
- nginx: `/etc/nginx/nginx.conf`, which by default
  includes only `modules.d/`, no `sites-available/`
  or `conf.d/`. Check what the main file includes before
  adding a site.
- Apache: package `apache`, config
  `/etc/httpd/conf/httpd.conf`, unit `httpd.service`.

## CachyOS

- Repos: `[cachyos]` plus a CPU-level set such as
  `[cachyos-v3]`, `[cachyos-core-v3]`,
  `[cachyos-extra-v3]` (v4 and Zen 4 variants exist),
  ahead of Arch's own. Record the level in server
  memory: on a CPU without that instruction set
  (a moved disk or VM) its binaries stop with
  "illegal instruction".
- No server edition exists; a headless host is the
  desktop installer without a desktop. Report
  desktop-oriented services you find as INFO, never
  remove them unasked.
- If `snapper list-configs` shows a root config, a
  snapshot before an upgrade is a way back
  (`rules/way-back.md`).

## Common Pitfalls

- `pacman -Sy <pkg>`: a partial upgrade. See Rolling
  Release.
- A missing module after a kernel upgrade is not a
  broken driver. It is the pending reboot.
- `.pacnew` files pile up unseen; a service then
  runs on an old config that newer defaults expect
  to have changed.
- `pacman` without `--noconfirm` waits for an answer
  that never comes over a non-interactive SSH call.
