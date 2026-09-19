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
  ext_if = "vtnet0"  # set to the real interface, see ifconfig
  set skip on lo0
  block in all
  pass out all keep state
  pass in on $ext_if proto tcp to port 22
  ```
- sshd not on 22? See `rules/ssh-port.md` →
  Firewall.
- Do **not** rely on the `egress` interface group in
  rules unless `ifconfig -g egress` shows it is
  populated on this host. If the group is missing or
  empty, a `pass in on egress` rule matches nothing
  and `block in all` kills SSH the moment the rules
  load.
- **Mandatory before any load:** the parse-only
  config test `pfctl -nf /etc/pf.conf` must pass
  first.
- When changing pf rules over SSH, schedule a safety
  net before loading, e.g.:
  ```
  echo "pfctl -d" | at now + 5 minutes
  ```
  If the new rules cut you off, pf disables itself
  and you can get back in. After confirming the
  session survived, cancel the job (`atq`, then
  `atrm <job>`) — do not leave it behind.
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

## Console Configuration

The correct `console` setting in `/boot/loader.conf`
depends on the platform and architecture:

| Platform                    | Console setting   |
|-----------------------------|-------------------|
| Physical server (VGA)       | `vidconsole`      |
| Physical server (serial)    | `comconsole`      |
| UTM / QEMU **x86_64** (EFI)| `vidconsole`      |
| UTM / QEMU **ARM64** (EFI) | `efi`             |
| QEMU with `-nographic`      | `comconsole`      |

**x86_64 QEMU/UTM:** QEMU emulates a VGA text-mode
adapter on x86_64, so `vidconsole` works. Using
`console="efi"` on x86_64 causes "Display output is
not active" in UTM — the EFI framebuffer console is
not initialized by x86_64 QEMU firmware.

**ARM64 UTM:** No VGA text mode exists on ARM64.
`vidconsole` fails. The `efi` console uses the EFI
framebuffer — this is the one that shows the boot
menu on the VM display. **Use `console="efi"` only
for ARM64 UTM/QEMU EFI VMs.**

If the wrong console is set, the loader prints
"console ... is unavailable" and "no valid
consoles!" and falls back to `spinconsole` (which
discards all output). The kernel may boot but
produce no visible output and potentially fail
silently. SSH may still work if the kernel fully
boots.

**Quick fix from the loader prompt:**
```
set console="vidconsole"   # x86_64
set console="efi"          # ARM64
boot
```

## Boot Loader (Lua-based, 14.x+)

Starting with FreeBSD 14.x, the boot loader uses
Lua scripts in `/boot/lua/`. The entry point is
`/boot/lua/loader.lua`.

- **If `/boot/lua/loader.lua` is missing,** the
  loader drops to an `OK` prompt instead of booting
  the kernel. This looks like a boot failure but the
  kernel and root filesystem may be intact.
- **Quick fix from the `OK` prompt:**
  ```
  load kernel
  load -t rootfs ufs:/dev/ada0p2
  boot
  ```
  (Replace `ada0p2` with the actual root partition.)
- **Permanent fix:** re-extract `base.txz` which
  contains `/boot/lua/`.
- **When extracting `base.txz` manually** (e.g.
  during SSH-only OS replacement), always verify
  `/boot/lua/loader.lua` exists after extraction.
  A tar truncation error can silently skip files.

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
  Config is in `/boot/loader.conf`. Always set
  `vfs.root.mountfrom` explicitly (e.g.
  `vfs.root.mountfrom="ufs:/dev/ada0p3"`) —
  auto-detection can fail after cross-OS
  replacement or when EFI boot entries change.
- **No `journalctl`** — logs are in `/var/log/`.
  Use `tail`, `grep`, or `less`. The heinzel
  changelog uses `logger`, which writes to syslog.
- **`sudo` is not installed by default** — install
  with `pkg install sudo` and configure
  `/usr/local/etc/sudoers`.

## QEMU/UTM Emulated x86_64 Workarounds

**OpenSSL SIGSEGV on emulated Skylake CPU:**
FreeBSD's base `sshd` (and `openssh-portable`)
crash with signal 11 when OpenSSL's hardware-
accelerated crypto (AES-NI, AVX assembly) runs on
QEMU's emulated Skylake CPU. The crash occurs
during RSA key loading.

**Fix:** disable OpenSSL hardware acceleration with
`OPENSSL_ia32cap=0`. Replacing `/usr/sbin/sshd` with
a wrapper touches an SSH binary — get **explicit
user confirmation** before doing this:

```
# For base sshd (only with user confirmation):
mv /usr/sbin/sshd /usr/sbin/sshd.real
cat > /usr/sbin/sshd << 'EOF'
#!/bin/sh
export OPENSSL_ia32cap=0
exec /usr/sbin/sshd.real "$@"
EOF
chmod +x /usr/sbin/sshd
```

Base-system updates restore the real binary —
re-check the wrapper after every
`freebsd-update install`.

This affects ANY program using OpenSSL crypto on
emulated x86_64 QEMU. If other services crash with
SIGSEGV in libcrypto, apply the same workaround.

**Does not affect:** native ARM64 UTM VMs (Apple
Silicon with HVF), physical servers, or QEMU VMs
with KVM hardware virtualization.
