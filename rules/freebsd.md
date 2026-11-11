# FreeBSD

Rules for FreeBSD (all versions). Read
`rules/bsd.md` with it.

## Package Manager

- Use `pkg` for binary package management.
- Bootstrap if missing: `pkg bootstrap -y`
- Update catalog: `pkg update`
- Dry-run before upgrading: `pkg upgrade -n`
- Non-interactive install: `pkg install -y <package>`
- Search: `pkg search <name>`
- Installed packages: `pkg info`
- Audit for vulnerabilities: `pkg audit -F`
- Check which pkg branch the host uses (`quarterly`
  or `latest`) in `/etc/pkg/FreeBSD.conf` before
  installing, and stick to the branch the host
  already uses (CLAUDE.md: stable release tracks).

## Version Detection

- `freebsd-version` — base system version
  (e.g. `N.N-RELEASE`)
- `freebsd-version -k` — running kernel version
- `uname -r` — kernel release string
- `uname -m` — architecture (e.g. `amd64`,
  `aarch64`)
- There is no `/etc/os-release` on FreeBSD.
- Hardware: `sysctl` for CPU and RAM, `df -h`,
  `zpool status` if ZFS.
- Lifecycle: freebsd.org/security

## Firewall

- **Expected:** `pf` (Packet Filter)
- Config: `/etc/pf.conf`
- Check if enabled: `pfctl -s info`
- Enable in `/etc/rc.conf`: `pf_enable="YES"`
- Load rules: `pfctl -f /etc/pf.conf`
- Show current rules: `pfctl -s rules`
- **Critical:** before enabling `pf`, always add a
  rule to pass SSH traffic first. A `pf` config
  without an SSH rule locks you out immediately.
  The example below passes port 22 only: list every
  port sshd listens on (`to port { 22 2222 }`,
  `CLAUDE.md` → Firewall & network).
- Minimal safe `/etc/pf.conf`:
  ```
  set skip on lo0
  block in all
  pass out all keep state
  pass in proto tcp to port 22
  ```
- The SSH pass names no interface on purpose. A
  login that arrives through a tunnel (Heinzel's
  WireGuard interface `heinzel`, any `wg*` or
  `tun*`) needs it there too; `pass in on $ext_if`
  locks that login out the moment the rules load.
  `$SSH_CONNECTION` shows the address this session
  came in on.
- Do **not** rely on the `egress` interface group in
  rules unless `ifconfig -g egress` shows it is
  populated on this host. If the group is missing or
  empty, a `pass in on egress` rule matches nothing
  and `block in all` kills SSH the moment the rules
  load.
- **Mandatory before any load:** the parse-only
  config test `pfctl -nf /etc/pf.conf` must pass
  first.
- When changing pf rules over SSH, arm a rollback
  timer first (`rules/rollback-timer.md`). It
  reloads the saved ruleset
  (`pfctl -f /var/backups/heinzel/pf.conf.<ts>`)
  rather than disabling pf, which would leave the
  host without a firewall.
- After enabling, verify the default policy blocks
  incoming traffic.
- Start/stop: `service pf start`, `service pf stop`

## Automatic Security Updates

- **Base system:** `freebsd-update fetch install`
  (non-interactive:
  `freebsd-update --not-running-from-cron fetch install`)
- **Packages:** `pkg upgrade` (dry-run: `pkg upgrade -n`)
- There is no built-in equivalent of
  `unattended-upgrades`. Flag this to the user.
- Unattended upgrades are a **decision for the
  user**, not a default. Prefer a notify-only cron
  job that audits pending updates without applying
  them:
  ```
  # root crontab (crontab -e) — no user field:
  @daily pkg upgrade -n 2>&1 | mail -s "pkg updates" root
  ```
  ```
  # /etc/cron.d/pkg-audit — user field required:
  @daily root pkg upgrade -n 2>&1 | mail -s "pkg updates" root
  ```
- If the user explicitly wants auto-applying
  updates, warn first: unattended
  `freebsd-update install` can stage kernel updates
  that silently require a reboot, and `pkg upgrade -y`
  full-upgrades every package, not just security
  fixes.

## Service Manager

- FreeBSD uses `rc.d`, not systemd.
- **Service control:**
  - Start: `service <name> start`
  - Stop: `service <name> stop`
  - Reload (when supported): `service <name> reload`
  - Restart: `service <name> restart`
  - Status: `service <name> status`
  - One-shot start (without enabling):
    `service <name> onestart`
  - Reload vs restart: see `rules/service-reload.md`
    for the auto-proceed policy and
    `memory/service-policy.md` opt-out / opt-in
    lists.
- **Enable/disable services:**
  - `sysrc <name>_enable="YES"` (preferred)
  - Or manually in `/etc/rc.conf`
  - Check: `sysrc -a | grep <name>`
- **List enabled services:** `sysrc -a | grep _enable`
- `/etc/rc.conf` is the central service
  configuration file.

## Service Classes

Installed members (`rules/service-class-check.md`,
phase 1):

```bash
pkg info -E 'apache*' 'nginx*' 'caddy*' \
            'postgresql*-server' 'mariadb*-server' \
            'mysql*-server' \
            'postfix*' 'exim*' 'sendmail*' \
            'opensmtpd*' \
            'msmtp*' 'nullmailer*' 'dma*' \
            'chrony*' 'openntpd*' \
            'unbound*' 'bind9*' 'dnsmasq*' \
            'knot-resolver*' \
            'podman*' 'containerd*' \
            2>/dev/null
```

`ntpd` and `local_unbound` ship in base, not as
packages: check
`service -e | grep -E 'ntpd|local_unbound'` as well.
pf and ipfw are in base too, no frontend packages
compete.

Install dry run (phase 2):

```bash
pkg install -n <pkg>
```

## Listening Ports

```bash
sockstat -4 -6 -l | grep -E ':<port>\b'
```

No root needed. Shows user, command, PID, protocol,
and local address.

## Journal

```
grep -h heinzel /var/log/messages.0 \
  /var/log/messages 2>/dev/null | tail -20
```

This shows the last 20 matches, not a strict 7-day
window, and only reaches one rotation back
(`messages.0`). Older rotated logs are usually
compressed; mention the limitation if relevant.

## Rollback Timer

- Arm:

      daemon -f -p /var/run/heinzel-rollback-<ts>.pid \
        sh -c 'sleep 120; sh /var/backups/heinzel/rollback-<ts>.sh'

  Not `at`: `atrun` runs from cron every five
  minutes, so the window becomes unpredictable.
- Disarm:
  `pkill -F /var/run/heinzel-rollback-<ts>.pid`
- Did it run: the `rollback-<ts> ran` line in
  `/var/log/messages`.

## Filesystem

### ZFS

- ZFS is the default filesystem on modern FreeBSD.
- Pool status: `zpool status`
- Pool list: `zpool list`
- Datasets: `zfs list`
- Snapshots: `zfs list -t snapshot`
- Create snapshot:
  `zfs snapshot pool/dataset@name`
- **Boot environments** (`bectl`):
  - List: `bectl list`
  - Create: `bectl create <name>`
  - Activate: `bectl activate <name>`
  - Use boot environments before major changes
    (upgrades, config changes).
- Common pool layout:
  ```
  zroot/ROOT/default    /
  zroot/tmp             /tmp
  zroot/usr/home        /usr/home
  zroot/var/log         /var/log
  ```

### UFS

- Older installations may use UFS.
- Check: `mount` — UFS shows as `ufs`.
- `fsck` for filesystem checks (not `e2fsck`).

## Directory Conventions

- **Third-party config:** `/usr/local/etc/`
  (not `/etc/` — that's for base system only)
- **Third-party binaries:** `/usr/local/bin/`,
  `/usr/local/sbin/`
- **Web roots:** `/usr/local/www/`
- **Logs:** `/var/log/`
- **Ports tree:** `/usr/ports/` (if installed)
- **Base system config:** `/etc/`
  (`rc.conf`, `pf.conf`, `fstab`, `loader.conf`)
- **Boot loader config:** `/boot/loader.conf`

## Networking

- **Use `ifconfig`**, not `ip` (Linux-only).
- Interface list: `ifconfig`
- Set static IP: edit `/etc/rc.conf`:
  ```
  ifconfig_vtnet0="inet 192.168.1.10 \
    netmask 255.255.255.0"
  defaultrouter="192.168.1.1"
  ```
- DNS: `/etc/resolv.conf`
- Hostname: `sysrc hostname="myhost.example.com"`
- Restart networking: `service netif restart &&
  service routing restart`

## Common Pitfalls

- **No `systemctl`** — use `service` and `sysrc`.
- **No `/etc/os-release`** — use `freebsd-version`.
- **No `ip` command** — use `ifconfig`.
- **No `apt-get`/`dnf`/`zypper`** — use `pkg`.
- **Config in `/usr/local/etc/`** — third-party
  software (nginx, PostgreSQL, etc.) keeps its
  config under `/usr/local/etc/`, not `/etc/`.
- **`/etc/rc.conf` is central** — services, network,
  hostname, and many system settings live here.
  Back up before editing.
- **`freebsd-update` vs `pkg`** — `freebsd-update`
  patches the base system (kernel, userland);
  `pkg` manages third-party packages. Both need
  separate maintenance.
- **Boot loader:** FreeBSD uses its own loader
  (`/boot/loader.efi`), not GRUB or systemd-boot.
  Config is in `/boot/loader.conf`. A kernel module
  or a tunable there is an ordinary edit (back up
  first); the loader itself, `vfs.root.mountfrom`,
  the `console` setting and the EFI entries are
  boot work and Heinzel Pro's (`CLAUDE.md` → What
  Heinzel does not do). Read them, report them.
- **No `journalctl`** — logs are in `/var/log/`.
  Use `tail`, `grep`, or `less`. The heinzel
  changelog uses `logger`, which writes to syslog.
- **`sudo` is not installed by default** — install
  with `pkg install sudo`. The `sudoers` line for a
  user is sudo work and Heinzel Pro's: write it
  into the report (`/usr/local/etc/sudoers.d/`,
  checked with `visudo -c -f`).
