# FreeBSD

Rules for FreeBSD (all versions).

## Package Manager

- Use `pkg` for binary package management.
- Bootstrap if missing: `pkg bootstrap -y`
- Update catalog: `pkg update`
- Dry-run before upgrading: `pkg upgrade -n`
- Non-interactive install: `pkg install -y <package>`
- Search: `pkg search <name>`
- Installed packages: `pkg info`
- Audit for vulnerabilities: `pkg audit -F`

## Version Detection

- `freebsd-version` — base system version
  (e.g. `15.0-RELEASE`)
- `freebsd-version -k` — running kernel version
- `uname -r` — kernel release string
- `uname -m` — architecture (e.g. `amd64`,
  `aarch64`)
- There is no `/etc/os-release` on FreeBSD.

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
- Minimal safe `/etc/pf.conf`:
  ```
  set skip on lo0
  block in all
  pass out all keep state
  pass in on egress proto tcp to port 22
  ```
- After enabling, verify the default policy blocks
  incoming traffic.
- Start/stop: `service pf start`, `service pf stop`

## Automatic Security Updates

- **Base system:** `freebsd-update fetch install`
  (non-interactive: `freebsd-update --not-running-
  from-cron fetch install`)
- **Packages:** `pkg upgrade -y`
- There is no built-in equivalent of
  `unattended-upgrades`. Flag this to the user.
- Recommend a daily cron job:
  ```
  # /etc/cron.d/freebsd-updates or root crontab
  @daily freebsd-update --not-running-from-cron \
    fetch install && pkg upgrade -y
  ```

## Service Manager

- FreeBSD uses `rc.d`, not systemd.
- **Service control:**
  - Start: `service <name> start`
  - Stop: `service <name> stop`
  - Restart: `service <name> restart`
  - Status: `service <name> status`
  - One-shot start (without enabling):
    `service <name> onestart`
- **Enable/disable services:**
  - `sysrc <name>_enable="YES"` (preferred)
  - Or manually in `/etc/rc.conf`
  - Check: `sysrc -a | grep <name>`
- **List enabled services:** `sysrc -a | grep _enable`
- `/etc/rc.conf` is the central service
  configuration file.

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

## Cross-OS Compatibility

- **ext2fs driver:** FreeBSD can mount ext2/ext3
  partitions (`mount -t ext2fs /dev/daXpY /mnt`).
  However, the driver cannot handle modern ext4
  features (`metadata_csum_seed`, `orphan_file`).
  Use plain ext2 for partitions shared between
  FreeBSD and Linux.
- **Swap:** FreeBSD and Linux swap formats are
  incompatible. Each OS needs its own swap partition
  or skip swap on one OS.
- **ZFS:** Linux (OpenZFS) and FreeBSD ZFS are
  compatible at the pool level, but mixing is not
  recommended for root pools.

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
  Config is in `/boot/loader.conf`.
- **No `journalctl`** — logs are in `/var/log/`.
  Use `tail`, `grep`, or `less`. Heinzel changelog
  uses `logger` which writes to syslog.
- **`sudo` is not installed by default** — install
  with `pkg install sudo` and configure
  `/usr/local/etc/sudoers`.
