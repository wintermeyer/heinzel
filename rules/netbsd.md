# NetBSD

Rules for NetBSD (10.x and 11.x, the supported
series). Read `rules/bsd.md` with it.

## PATH Over SSH

A command sent as `ssh root@host '<cmd>'` runs with
`PATH=/usr/bin:/bin:/usr/pkg/bin:/usr/local/bin`.
`/sbin` and `/usr/sbin` are missing: `npfctl`,
`ifconfig`, `route`, `ping`, `ntpq`, `pkg_add` and
`service` answer `not found` although they are
installed; only `/root/.profile` adds them, and a
command over SSH does not read it. Start every
remote command with
`export PATH=/sbin:/usr/sbin:/usr/pkg/sbin:$PATH;`
and never read `not found` as "not installed"
without it.

## Package Manager

- Packages come from pkgsrc and live under
  `/usr/pkg/` (config in `/usr/pkg/etc/`). A fresh
  install has none: no `pkgin`, `sudo`, `bash` or
  `lsof`.
- Base tools: `pkg_info` (installed),
  `pkg_add <pkg>`, `pkg_delete <pkg>`.
- `pkgin` is the apt-like front end. Installing it
  asks first, like any package:
  ```
  rel=$(uname -r | cut -f '1 2' -d. | cut -f 1 -d_)
  cdn=https://cdn.NetBSD.org/pub/pkgsrc/packages/NetBSD
  PKG_PATH="$cdn/$(uname -p)/$rel/All" pkg_add pkgin
  ```
- With `pkgin`: `pkgin update`, `pkgin -n upgrade`
  (dry run), `pkgin -y install <pkg>`,
  `pkgin search <name>`.
- Vulnerabilities: `pkg_admin fetch-pkg-vulnerabilities`,
  then `pkg_admin audit`.

## Version Detection

- `uname -r` — release (`11.0`); `uname -m` and
  `uname -p` — port and CPU (`evbarm`, `aarch64`).
- `head -1 /etc/release` — `NetBSD 11.0/evbarm`.
- There is no `/etc/os-release`.
- Hardware: `sysctl hw.model hw.ncpu
  hw.physmem64`, `df -h`.
- Lifecycle: netbsd.org/releases lists the
  supported series; older ones get no security
  fixes.

## Firewall

- **Expected:** `npf`. Config `/etc/npf.conf`,
  enabled by `npf=YES` in `/etc/rc.conf`. No
  default config exists; the base example is
  `/usr/share/examples/npf/host-npf.conf`.
- Status: `npfctl show` (`filtering: active`).
- **Mandatory before any load:**
  `npfctl validate /etc/npf.conf`.
- Load: `npfctl reload`; on/off: `npfctl start`,
  `npfctl stop`.
- **`npfctl start` cuts the running SSH session.**
  npf has no state for a connection opened before
  it was active, and `pass stateful … port ssh`
  matches only the opening SYN. Arm the rollback
  timer (`rules/rollback-timer.md`, Rollback Timer
  below) and start npf in the same detached
  command, then confirm with a fresh login.
- Minimal inbound-SSH-only config (list every port
  sshd listens on):
  ```
  $ext_if = "vioif0"   # see ifconfig -l
  alg "icmp"
  group "external" on $ext_if {
      pass stateful in proto tcp to ifaddrs($ext_if) port ssh
  }
  group default {
      block all
      pass stateful in proto tcp to any port ssh   # tunnels
      pass on lo0 all
      pass in family inet4 proto udp from any port bootps to any port bootpc
      pass family inet6 proto ipv6-icmp all
      pass stateful out all
  }
  ```
  Without the DHCP line the host loses its lease;
  without ICMPv6 it loses IPv6 neighbours.
- `group "<name>" on <ifname>` takes only traffic
  on that interface; everything else, tunnels (`tun*`,
  `wg*`) included, lands in `group default`. A pass
  for a tunnel peer in `group default` is therefore
  no duplicate of the SSH pass in an interface
  group (npf.conf(5)). Without the SSH pass in
  `group default`, a login through a tunnel
  (Heinzel's `wg*` or `tun*`) is cut off the moment
  the rules load.
- `npfctl show` prints the loaded ruleset, in its
  own syntax: compare it with `/etc/npf.conf` to
  see whether the file on disk is what runs.
  `npfctl validate` checks a file without loading.
- `npfctl start` may warn that it cannot load the
  `bpfjit` module. The filter still works.
- NetBSD 11 renamed blacklistd to **blocklistd**
  (`/sbin/blocklistd`).

## Automatic Security Updates

- Nothing applies updates on its own, base or
  packages. Flag this to the user.
- `/etc/security` runs daily and audits installed
  packages (`check_pkg_vulnerabilities=YES` by
  default) and mails root: the notify-only
  baseline. Check `/etc/security.conf` keeps it on.
- **Base system:** binary updates to a new point
  release (11.0 → 11.1) go through `sysupgrade`
  (pkgsrc `sysutils/sysupgrade`). It replaces the
  kernel and needs a reboot: a decision for the
  user, never a default.
- **Packages:** `pkgin -n upgrade` to see what is
  pending, `pkgin upgrade` only on request.

## Service Manager

- `rc.d`, like FreeBSD, but **no `sysrc`**.
- Control: `service <name> start|stop|restart|status`
  or `/etc/rc.d/<name> <cmd>`. `onestart` runs a
  service that is not enabled.
- Enable: `<name>=YES` in `/etc/rc.conf`
  (`sshd=YES`, not `sshd_enable`). Back up, then
  append; the last assignment wins, and the
  installer often wrote the variable already.
- Flags: `<name>_flags="…"`; defaults in
  `/etc/defaults/rc.conf`.
- Enabled services: `service -e`.
- Own scripts in `/etc/rc.d/` need the
  `PROVIDE` / `REQUIRE` / `BEFORE` header that
  `rcorder` sorts by.

## Service Classes

Installed members (`rules/service-class-check.md`,
phase 1):

```bash
pkg_info | grep -E \
  '^(nginx|apache|caddy|lighttpd|postgresql|mariadb)'
pkg_info | grep -E \
  '^(postfix|exim|msmtp|chrony|dnsmasq|unbound|bind)-'
service -e | grep -E \
  '/(httpd|named|ntpd|postfix|unbound)$'
```

The `service -e` line is not optional: `httpd`,
`named`, `ntpd`, `postfix` and `unbound` ship in
base and never show up as packages. `postfix` is
enabled after a plain install.

Install dry run (phase 2):

```bash
pkgin -n install <pkg>
```

## Listening Ports

```bash
sockstat -n -4 -6 -l | grep -E '\.<port> '
```

`-n` is required: without it NetBSD prints service
names (`*.ssh`). The port follows a dot, not a
colon.

## Journal

```
grep -ah heinzel /var/log/messages 2>/dev/null \
  | tail -20
```

`-a` is required: after an unclean shutdown
`/var/log/messages` can hold NUL bytes, and plain
`grep` then prints only `Binary file matches`.
Rotated copies are gzipped (`messages.0.gz`).

## Rollback Timer

- Arm: the generic `nohup` variant in
  `rules/rollback-timer.md`. There is no `daemon(8)`.
- Disarm:
  `pkill -F /var/run/heinzel-rollback-<ts>.pid`,
  never `pkill -f '<pattern>'` (`rules/bsd.md`).
- Did it run: `grep -a 'rollback-<ts> ran'
  /var/log/messages`.

## Networking

- `ifconfig`, `route -n show`, no `ip`.
- DHCP is `dhcpcd` (`dhcpcd=YES`). Hooks go in
  `/etc/dhcpcd.exit-hook`.
- Static address: `/etc/ifconfig.<if>` (one line:
  `inet 192.168.1.10/24`) plus `defaultroute=` in
  `/etc/rc.conf`; the rollback timer applies.
- Hostname: `hostname=` in `/etc/rc.conf`. Without
  one the host is `Amnesiac` and **postfix fails at
  boot** (`unable to use my own hostname`).

## Logs

- Syslog only: `/var/log/messages`,
  `/var/log/authlog`; rotated copies are gzipped
  (`messages.0.gz`). Use `grep -a` on them, for the
  reason given under Journal.

## Common Pitfalls

- **No `doas` either** in base (`rules/bsd.md` for
  `sudo`).
- **ntpd and IPv6**: where the host has an IPv6
  route that does not reach the internet (UTM's
  shared network, many home routers), ntpd solicits
  only IPv6 pool servers and never syncs. Check with
  `ntpdate -q -4` against `-6`; the fix is
  `ntpd_flags="-4"` and `ntpdate_flags="-4 -b -s"`.
  `ntpq` then needs `ntpq -4 -pn 127.0.0.1`.
- **The console is the serial port** on evbarm
  (`constty` in `/etc/ttys`). getty prints
  `/etc/issue` only with `if=/etc/issue` in the
  `default` entry of `/etc/gettytab`.

## Boot

`/boot` is the EFI system partition (msdos), with
`/boot/EFI/BOOT/bootaa64.efi` and an optional
`/boot/boot.cfg`. Boot loader, `boot.cfg` and EFI
entries are Heinzel Pro's (`CLAUDE.md` → What
Heinzel does not do). Read them, report them.

One known case to report: NetBSD 11.0 under Apple's
Hypervisor.framework (UTM, QEMU with HVF) panics at
boot in `vmt_probe` (`Illegal Instruction`), and the
display only shows "Display output is not active".
The fix is `userconf=disable vmt` in
`/boot/boot.cfg`; `vmt*` does not match.
