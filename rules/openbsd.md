# OpenBSD

Rules for OpenBSD (checked on 8.0/arm64). Read
`rules/bsd.md` with it.

Over SSH, `PATH` already holds `/sbin` and
`/usr/sbin`, unlike NetBSD. Root's shell is `ksh`
and `/bin/sh` is the same binary. There is no
`bash` in base: a script with `#!/bin/bash` fails.

## Version Detection

- `uname -r` — release (`8.0`); `uname -m` and
  `uname -p` — port and CPU (`arm64`, `aarch64`).
- `sysctl -n kern.version | head -1` — the running
  kernel with its build number
  (`OpenBSD 8.0 (GENERIC.MP) #3: …`).
- There is no `/etc/os-release` and no
  `/etc/release`.
- Hardware: `sysctl hw.model hw.ncpuonline
  hw.physmem`, `df -h`, `swapctl -l`,
  `top -b -d 1 | head -5` for memory. No `free`.
- Lifecycle: errata go to the two most recent
  releases only (openbsd.org/errata.html). Anything
  older gets no security fixes.

## Package Manager

- Base tools: `pkg_info` (installed),
  `pkg_add <pkg>`, `pkg_delete <pkg>`. The mirror
  comes from `/etc/installurl`.
- Search: `pkg_info -Q <name>`. Dry run:
  `pkg_add -n <pkg>`.
- A fresh install has no packages: no `sudo`,
  `bash`, `curl`, `wget`, `rsync`, `python3` or
  `lsof`. Base has `doas`, `ftp` (fetches https
  URLs: `ftp -o <file> <url>`), `perl`, `mail`
  and `nohup`.
- Packages install under `/usr/local/`, but their
  config lives in `/etc/` (`/etc/nginx/`), not in
  `/usr/local/etc/` as on FreeBSD. Web roots are
  under `/var/www/`.
- Read `/usr/local/share/doc/pkg-readmes/<pkg>`
  after an install: it names the steps the package
  does not do itself.
- Updates: `pkg_add -un` (dry run), `pkg_add -u`
  only on request. Package security fixes exist for
  the most recent release only.

## Firewall

- **Expected:** `pf`, in base and enabled by default
  (`pf=YES`). Config `/etc/pf.conf`.
- **The stock ruleset is no firewall.** It reads
  `block return` followed by a bare `pass`, which
  lets every inbound connection through. `pf
  enabled` therefore says nothing: read
  `pfctl -sr`, and flag a bare `pass` or `pass in`
  without a port (`CLAUDE.md` → default incoming
  policy).
- Status: `pfctl -si`; loaded rules: `pfctl -sr`.
- **Mandatory before any load:**
  `pfctl -nf /etc/pf.conf` (parse only).
- Load: `pfctl -f /etc/pf.conf`. Never `pfctl -d`
  as a way out: it leaves the host without a
  filter.
- Minimal inbound-SSH-only config (list every port
  sshd listens on). Tested on 8.0: a fresh login,
  a new DHCP lease and IPv6 neighbours all work
  with it:
  ```
  set skip on lo
  block return
  pass out
  pass in proto tcp to port 22
  pass in inet6 proto icmp6
  block return in on ! lo0 proto tcp to port 6000:6010
  block return out log proto {tcp udp} user _pbuild
  ```
  The last two lines are stock; keep them. DHCP
  needs no pass rule here. Without the ICMPv6 line
  the host loses its IPv6 neighbours.
- The SSH pass names no interface on purpose: a
  login through a tunnel (`wg*`, `tun*`) needs it
  too. The `egress` group follows the default route
  and is usually populated (`ifconfig egress`), but
  `pass in on egress` still locks out a tunnel
  login.
- A reload keeps existing states, so the running
  session survives rules that block new logins. Arm
  the rollback timer (`rules/rollback-timer.md`,
  Rollback Timer below) and confirm with a fresh
  login. The rollback reloads the saved file
  (`pfctl -f /var/backups/heinzel/pf.conf.<ts>`).
- `sysctl kern.securelevel`: at `2` pf rules cannot
  be changed until a reboot. The default is `1`.
  Report a `2`, never lower it.
- Blocked packets marked `log` land in
  `/var/log/pflog`, a pcap file: read it with
  `tcpdump -n -e -ttt -r /var/log/pflog`.

## Automatic Security Updates

- Nothing applies updates on its own, base or
  packages. Flag this to the user.
- **Base system:** `syspatch -c` lists pending
  patches, `syspatch -l` the installed ones.
  `syspatch` installs all pending ones (no subset),
  `syspatch -r` reverts the newest. Only amd64,
  arm64 and i386 have it.
- **Reboot pending:** a kernel patch ends with
  `reboot to load the new kernel`. Later, compare
  the build numbers:
  ```
  sysctl -n kern.version | head -1   # running
  what /bsd | tail -1                # on disk
  ```
  Different lines mean the patched kernel is not
  running yet. The reboot asks first. A patched
  library reaches a daemon only when the daemon
  restarts; that asks too.
- **Notify-only baseline:** `/etc/daily` mails root
  every night but does not look for patches. One
  line `syspatch -c` in `/etc/daily.local` adds
  them to that mail (daily(8)). Offer it, never
  auto-apply.
- **New release:** `sysupgrade` downloads the sets
  and then **reboots on its own** into the
  upgrade. `sysupgrade -n` only stages it. A
  decision for the user, never a default; run
  `pkg_add -u` afterwards.

## Service Manager

- `rcctl`. There is no `service`, `systemctl` or
  `sysrc`.
- Control: `rcctl check|start|stop|restart|reload
  <name>`.
- Enable: `rcctl enable <name>`; flags:
  `rcctl set <name> flags <flags>`; read:
  `rcctl get <name>`.
- `rcctl` writes `/etc/rc.conf.local`, which does
  not exist until the first change. **Never edit
  `/etc/rc.conf`**: it holds the defaults and every
  upgrade replaces it.
- Lists: `rcctl ls on` (enabled), `rcctl ls failed`
  (enabled but not running), `rcctl ls started`.
- Config test before a reload:
  `rcctl configtest <name>` (`sshd(ok)`). Not every
  script has one (`ntpd`: `configtest is not
  supported`): then use the daemon's own test
  (`httpd -n`, `smtpd -n`, `relayd -n`,
  `nginx -t`). An unsupported test is not a pass
  (`rules/service-reload.md`).

## Service Classes

Installed members (`rules/service-class-check.md`,
phase 1):

```bash
pkg_info | grep -E \
  '^(nginx|apache-httpd|caddy|lighttpd)-[0-9]'
pkg_info | grep -E \
  '^(postgresql-server|mariadb-server)-[0-9]'
pkg_info | grep -E \
  '^(postfix|msmtp|dnsmasq|isc-bind)-[0-9]'
rcctl ls on | grep -E \
  '^(httpd|relayd|smtpd|unbound|unwind|nsd|ntpd)$'
```

The `rcctl` line is not optional: `httpd`, `relayd`,
`smtpd`, `unbound`, `nsd` and `ntpd` ship in base
and never show up as packages. `smtpd` (on
localhost) and `ntpd` are enabled after a plain
install. pf is in base, no frontend packages
compete.

Install dry run (phase 2):

```bash
pkg_add -n <pkg>
```

## Listening Ports

```bash
netstat -ln -f inet -p tcp | grep -E '\.<port> '
fstat | grep -E 'internet6? (stream|dgram) .*:<port>$'
```

`netstat` shows the socket but no process (repeat
with `-f inet6`); the port follows a dot (`*.22`).
`fstat` names user, command and PID. The `$` keeps
established connections out: their line goes on
with `<--`. There is no `sockstat`, `ss` or `lsof`
in base.

## Journal

```
grep -ah heinzel /var/log/messages 2>/dev/null \
  | tail -20
```

`/var/log/messages` rotates at 300 KB into gzipped
copies (`messages.0.gz`, read with `zgrep`). On a
busy host the file reaches back only hours; say so
when it matters.

## Rollback Timer

- Arm: the generic `nohup` variant in
  `rules/rollback-timer.md`. There is no `daemon(8)`.
- Disarm:
  `kill "$(cat /var/run/heinzel-rollback-<ts>.pid)"`.
  `pkill` has no `-F` here.
- Did it run: `grep -a 'rollback-<ts> ran'
  /var/log/messages`.

## Privileges

- `doas` is in base, but `/etc/doas.conf` does not
  exist after an install,
  so `doas` refuses everybody. Probe with
  `doas -n true` (`rules/privilege-escalation.md`).
- Check a rule without running anything:
  `doas -C /etc/doas.conf <command>`.
- A line in `doas.conf` is sudo work and Heinzel
  Pro's: write it into the report. The guard blocks
  every write to the file.

## Networking

- `ifconfig`, `route -n show -inet`, no `ip`.
- One file per interface: `/etc/hostname.<if>`.
  `inet autoconf` is DHCP (`dhcpleased`),
  `inet6 autoconf` is SLAAC (`slaacd`); a static
  address is `inet 192.0.2.10 255.255.255.0`.
- Gateway: `/etc/mygate` (absent with DHCP).
  Hostname: `/etc/myname`.
- Apply: `sh /etc/netstart <if>`. The rollback
  timer applies.
- `/etc/resolv.conf` is managed by `resolvd`: lines
  ending in `# resolvd: <if>` are rewritten, do not
  edit them.
- Lease: `dhcpleasectl -l <if>`.

## Logs

- Syslog only: `/var/log/messages`, `authlog`,
  `daemon`, `maillog`. `newsyslog` rotates them
  hourly by size or age into gzipped copies.
- `/etc/daily`, `/etc/weekly` and `/etc/monthly`
  mail their findings to root, the daily one
  including security(8). Read root's mailbox
  during housekeeping.

## Filesystem

- FFS. The installer's auto layout cuts the disk
  into many small filesystems (`/`, `/tmp`, `/var`,
  `/usr`, `/usr/local`, `/home`, …). One fills up
  while the others are empty: read `df -h` per
  mount point before an install, never the total.
- `/usr/local` is the only filesystem mounted
  `wxallowed`. A program that needs memory both
  writable and executable (JIT runtimes) is killed
  when it starts from anywhere else, `/home`
  included (mount(8)).
- Layout, read-only: `disklabel -h sd0`,
  `sysctl hw.disknames`. `fdisk sd0` only prints
  here, but the guard cannot tell it from the Linux
  form and blocks it.
- Moving or growing a partition is `disklabel`
  work: partition table, Heinzel Pro's.

## Programming Language Runtimes

mise publishes no OpenBSD binary and 8.0 has no
mise package (`pkg_info -Q mise`). Say so, and use
the package (`node`, `python`, `ruby`) when the
user agrees: `rules/mise.md` does not apply here.
Python and Ruby come in several versions; take the
exact name from `pkg_info -Q <name>`
(`pkg_add ruby-3.4.11`).

## Common Pitfalls

- **No GNU userland:** `date -d`, `stat -c` and
  `grep -P` do not exist. Use `stat -f`.
- **`/bsd` changes at every boot.** The kernel is
  relinked in random order on each start, so a new
  mtime and checksum on `/bsd` are normal and no
  sign of tampering. `/bsd.booted` is the kernel
  that is running.
- **Time is OpenNTPD:** `ntpctl -s status`.
  `clock unsynced` is normal for the first minutes
  after a boot (about 15 on the test host).

## Boot

`/bsd` is the kernel, `/bsd.rd` the install and
rescue ramdisk. Boot loader, `installboot` and the
EFI entries are Heinzel Pro's (`CLAUDE.md` → What
Heinzel does not do). Read them, report them.
