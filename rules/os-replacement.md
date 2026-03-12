# OS Replacement

Workflow rule for replacing one OS with another on
the same server (wipe and reinstall).

## When to Read

Read this file when the user asks to:
- Replace the OS on a server (e.g. CentOS → Debian)
- Reinstall the OS from scratch
- Migrate a server to a different distribution
- Wipe and start fresh on an existing machine

This is NOT dual-boot — the old OS is removed
entirely. See `rules/dual-boot.md` for running
two OSes side by side.

## Prerequisites

Before starting:

1. **Confirm with the user.** This is destructive
   and irreversible. Make sure they understand the
   old OS will be wiped.
2. **Backup.** Verify the user has a full backup or
   snapshot. For VMs, suggest a VM-level snapshot
   before starting.
3. **Inventory the current system.** Capture
   everything needed to rebuild (see next section).

## Pre-Replacement Inventory

Gather and save this information from the running
system before it is wiped. Store it in
`memory/servers/<hostname>/pre-replacement.md`.

### System Facts

- OS, version, architecture
- Partition layout (`lsblk`, `gpart show`,
  `zpool status`)
- Filesystem types and mount points
- Bootloader type (GRUB, systemd-boot, FreeBSD
  loader)

### Network Configuration

- IP addresses (static or DHCP)
- Gateway, DNS servers
- Interface names and bonding/VLAN config
- Firewall rules (export full ruleset)
- `/etc/hosts` entries
- WireGuard or VPN configs

### Installed Services

- List all enabled services
  (`systemctl list-unit-files --state=enabled`,
  `sysrc -a | grep _enable`)
- For each service: config files, data directories,
  listening ports
- Database dumps (PostgreSQL, MySQL, etc.)
- Web server configs (sites, SSL certs)
- Cron jobs (`crontab -l`, `/etc/cron.d/`)

### User Accounts

- System users with login shells
- SSH authorized keys
- sudo/doas configuration
- Home directory contents (if relevant)

### Package List

- Explicitly installed packages
  (`apt-mark showmanual`, `pkg info -o`,
  `dnf history userinstalled`)
- Custom repositories

### Certificates

- SSL/TLS certificates and keys
  (`/etc/letsencrypt/`, `/usr/local/etc/ssl/`)
- SSH host keys (`/etc/ssh/ssh_host_*`) — save if
  you want to avoid host key change warnings

### Config File Backups

Back up all modified config files. Use the backup
procedure from `rules/backups.md`. At minimum:
- `/etc/` (or `/usr/local/etc/` on FreeBSD)
- Firewall config
- Web server configs
- Database configs
- Any custom application configs

## Boot Configuration Safety (CRITICAL)

**Never modify the bootloader or EFI fallback path
until the new OS root filesystem is confirmed
written to disk.**

Violating this rule can brick the server: if the
new root filesystem write fails but the bootloader
already points to it, the system reboots into a
bootloader that references a non-existent root.
With SSH-only access and no console, the server
becomes unrecoverable.

### Mandatory order of operations

1. **Write the new root filesystem first.** Confirm
   the write completed successfully (check exit
   code, verify bytes written).
2. **Verify the new root filesystem.** If possible,
   mount or probe it to confirm it is valid.
3. **Only then modify boot configuration.** Install
   the new bootloader, update EFI entries, or
   change BootOrder/BootNext.
4. **Keep the old bootloader intact as fallback**
   until the new OS is confirmed bootable. Use
   BootNext (one-shot) for the first boot into
   the new OS. See `rules/efi-boot.md`.

### What this means in practice

- Do NOT replace `/efi/boot/bootaa64.efi` (or
  `bootx64.efi`) with a new bootloader before the
  new OS is on disk.
- Do NOT change BootOrder to prioritize the new
  OS before confirming it boots.
- Do NOT remove old boot entries before the new
  OS is confirmed working.
- If the root filesystem write fails (dd error,
  permission denied, I/O error), **stop
  immediately**. Do not reboot. The old OS is
  still intact and bootable — keep it that way.

## Installation

### Method

**Prefer debootstrap** (or the equivalent bootstrap
tool for the target distro) over cloud images
whenever possible. debootstrap produces a clean,
minimal system with full control over installed
packages and configuration. Cloud images carry
cloud-init baggage, may lack `openssh-server`
(nocloud variants), and use GRUB which fails on
ARM64 QEMU/UTM.

Fall back to cloud images only when debootstrap is
not feasible (e.g. no network access from the
server, target distro has no bootstrap tool, or
the user explicitly requests a cloud image).

Choose installation method based on access:

- **Console/IPMI/KVM:** boot from ISO, run
  installer. Most reliable.
- **Cloud provider:** use provider's reinstall
  feature or deploy a new image.
- **VM (UTM/QEMU/VMware):** boot from ISO, or use
  debootstrap via rescue/chroot. Cloud images are
  a fallback — see `rules/cloud-image.md`.
  **ARM64 QEMU/UTM:** cloud images use GRUB, which
  fails silently on these platforms. Replace GRUB
  with systemd-boot before first boot (see
  `rules/efi-boot.md`, `rules/cloud-image.md`).
- **SSH-only replacement:** use debootstrap (or
  QEMU + debootstrap for cross-OS). See
  §"SSH-Only Replacement via Hot-Migration".
- **Network install (PXE):** if available in the
  datacenter.
- **In-place via rescue mode:** some providers offer
  a rescue system — boot into it, partition, and
  install via debootstrap or equivalent.

### Partition Planning

- Reuse the existing partition layout if it was
  working well.
- Keep the EFI partition if present (reformat only
  if necessary).
- Match or exceed previous partition sizes for
  services that will be restored.

### Freeing Partitions for Staging

Read `rules/partition-staging.md` for the full
strategy. Key techniques:

1. **Reclaim swap** — `swapoff` frees a partition
   for staging (images, backups, debootstrap).
2. **Hot-migrate** — on ZFS, LVM, or btrfs, add
   the freed swap to the pool, migrate data off
   the original partition, remove it. Now the
   original partition is free for the new OS.

Always check RAM before disabling swap (free RAM
after absorbing used swap must be >= 512 MB).

### Static IP

Configure the same IP address the old OS used.
The server's DNS records and firewall rules on
other servers depend on this IP staying the same.

## Post-Replacement Checklist

After the new OS is installed and accessible:

1. [ ] SSH access works
2. [ ] OS detected and server memory updated
3. [ ] Hostname set correctly
4. [ ] Network configured (same IP as before)
5. [ ] Firewall installed and configured
6. [ ] Automatic security updates enabled
7. [ ] SSH host keys restored (optional — avoids
       host key warnings for other users/scripts)
8. [ ] User accounts and SSH keys restored
9. [ ] Services reinstalled and configured
10. [ ] Data restored (databases, web content, etc.)
11. [ ] SSL certificates restored or renewed
12. [ ] Cron jobs restored
13. [ ] Firewall rules match pre-replacement config
14. [ ] All services tested and running
15. [ ] GPT partition types match the new OS
        (see §"GPT Partition Type Codes")
16. [ ] `pre-replacement.md` reviewed — nothing
        missed
17. [ ] Changelog entry logged
18. [ ] `pre-replacement.md` deleted after
        everything is confirmed working

## SSH-Only Replacement via Hot-Migration

When no console, IPMI, or rescue mode is available
and the server uses ZFS, LVM, or btrfs, use
hot-migration to free the main partition while the
old OS keeps running. This is the safest SSH-only
replacement method because the old OS remains
bootable as a fallback throughout the process.

### Overview

1. **Reclaim swap** — `swapoff` frees the swap
   partition.
2. **Add swap to pool** — add the freed partition
   to the filesystem pool (ZFS, LVM, btrfs).
3. **Evacuate main partition** — hot-remove the
   original root partition from the pool. All data
   migrates to the former swap partition. The old
   OS now runs entirely from the swap partition.
4. **Delete and repartition** — delete the freed
   main partition. Create new partitions: swap +
   new root for the replacement OS.
5. **Install new OS** — write the new OS to the
   new root partition (debootstrap, cloud image
   extraction, etc.) while the old OS is still
   running.
6. **Set up bootloader** — install systemd-boot on
   the EFI partition. See `rules/efi-boot.md`.
7. **BootNext for safe first boot** — use
   `efibootmgr -n` (one-shot) so the system tries
   the new OS once. On failure, it automatically
   falls back to the old OS bootloader.
8. **Clean up after confirmation** — once the new
   OS is confirmed working, remove the old OS from
   the swap partition and restore swap.

See `rules/partition-staging.md` for hot-migration
details. See `rules/efi-boot.md` for BootNext
setup.

### When hot-migration fails

Hot-migration requires the staging partition to
hold all data from the evacuated partition. If the
swap partition is too small (e.g. 2 GB swap, 1.5 GB
ZFS data + metadata overhead), `zpool remove` will
fail with "out of space." In that case, fall back
to the **tmpfs rescue + full-disk dd** method
described below.

## SSH-Only Replacement via Tmpfs Rescue

When hot-migration is not feasible (swap too small,
no volume manager, cross-OS replacement), use a
tmpfs-based rescue environment to keep SSH alive
while overwriting the entire disk with the new OS
image.

### Safety Rules (CRITICAL)

1. **Never overlay system library paths.** Do NOT
   mount tmpfs at `/lib`, `/libexec`, `/bin`, or
   `/sbin` on a live system's chroot. Overlaying
   with an incomplete library set kills the ability
   to fork new processes (including sshd-session),
   permanently locking you out with no recovery
   path.

2. **Build the rescue root from scratch on tmpfs.**
   Create a self-contained root filesystem on a
   tmpfs mount. Every path the rescue sshd and its
   child processes need (`/libexec/ld-elf.so.1`,
   `/lib/*.so.*`, `/bin/*`, `/sbin/*`,
   `/usr/sbin/sshd`, `/etc/ssh/*`, `/etc/passwd`,
   `/etc/pwd.db`, `/etc/spwd.db`, etc.) must exist
   inside the tmpfs root.

3. **Copy ALL of `/lib`, not a subset.** Missing a
   single library (e.g. `libpam.so`, `libz.so`)
   causes `sshd-session` to abort on every new
   connection. Copy the entire `/lib/` directory.
   On FreeBSD this is ~10 MB — always affordable.

4. **Start the rescue sshd on a new port, then
   VERIFY it works before proceeding.** Connect to
   the new port from a separate terminal. Run a
   test command. Only after confirmation, proceed
   with destructive operations.

5. **Never kill the original sshd until the rescue
   sshd is verified.** The original sshd is your
   last lifeline. Keep it running until you have
   confirmed the rescue sshd accepts connections
   and runs commands.

### Building the Tmpfs Rescue Root

```
T=/mnt/tmpfs_rescue
mkdir -p $T
mount -t tmpfs -o size=200m tmpfs $T

# Full directory tree
mkdir -p $T/{bin,sbin,lib,libexec,dev,tmp,mnt,etc}
mkdir -p $T/etc/ssh $T/root/.ssh $T/var/run/sshd
mkdir -p $T/var/empty $T/var/log
mkdir -p $T/usr/{bin,sbin,lib,libexec}

# Copy ALL of /lib (not a subset!)
cp -a /lib/* $T/lib/

# Dynamic linker
cp /libexec/ld-elf.so.1 $T/libexec/

# Binaries (adjust paths for Linux vs FreeBSD)
cp /bin/{sh,dd,mkdir,cp,cat,chmod,ls,rm,mv,ln,df} \
   $T/bin/
cp /sbin/{mount,umount,mdconfig,reboot,sysctl} \
   $T/sbin/
cp /sbin/{mount_msdosfs,newfs_msdos,gpart} \
   $T/sbin/
cp /usr/bin/fetch $T/usr/bin/
cp /usr/sbin/sshd $T/usr/sbin/
cp /usr/libexec/sftp-server $T/usr/libexec/

# Copy any /usr/lib dependencies not in /lib
ldd $T/usr/sbin/sshd $T/usr/bin/fetch \
  2>/dev/null | grep '/usr/lib/' | \
  awk '{print $3}' | sort -u | \
  xargs -I{} cp -n {} $T/usr/lib/

# Auth databases and config
cp /etc/passwd /etc/master.passwd \
   /etc/pwd.db /etc/spwd.db /etc/group \
   $T/etc/
cp /etc/ssh/ssh_host_* $T/etc/ssh/
cp /root/.ssh/authorized_keys \
   $T/root/.ssh/
chmod 700 $T/root/.ssh
chmod 600 $T/root/.ssh/authorized_keys

# Devfs
mount -t devfs devfs $T/dev

# sshd config on a new port
cat > $T/etc/ssh/sshd_config_rescue <<EOF
Port 2223
HostKey /etc/ssh/ssh_host_ed25519_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_rsa_key
PermitRootLogin yes
AuthorizedKeysFile .ssh/authorized_keys
PasswordAuthentication no
UseDNS no
Subsystem sftp /usr/libexec/sftp-server
EOF
```

### Starting and Verifying the Rescue sshd

```
chroot $T /usr/sbin/sshd \
  -f /etc/ssh/sshd_config_rescue

# === STOP. Verify from a second terminal: ===
# ssh -p 2223 root@hostname "id && echo OK"
# Only proceed after "OK" is confirmed.
```

### Streaming the New OS Image

After rescue sshd is verified, connect via the
rescue port and stream the cloud image to disk:

```
sysctl kern.geom.debugflags=0x10   # FreeBSD only
fetch -o - "https://url/to/image.raw" | \
  dd of=/dev/vtbd0 bs=1M
```

All processes run from tmpfs — the disk overwrite
does not affect them.

### Post-dd EFI Partition Modification

After the dd, the disk has the new OS layout but
GEOM still caches the old partition table. To
modify the new EFI partition from tmpfs:

```
# Copy EFI partition to a memory-backed device
mdconfig -a -t swap -s 130m -u 1
dd if=/dev/vtbd0 bs=512 skip=EFI_START \
   count=EFI_SECTORS of=/dev/md1
mount -t msdosfs /dev/md1 /mnt/efi

# Modify GRUB config, add systemd-boot, etc.

umount /mnt/efi
dd if=/dev/md1 of=/dev/vtbd0 bs=512 \
   seek=EFI_START count=EFI_SECTORS
mdconfig -d -u 1
```

Replace `EFI_START` and `EFI_SECTORS` with the
values from the cloud image's partition table
(inspected before the dd).

### SSH Access for Cloud Images

Cloud images (nocloud variant) boot with root
console login but no SSH key. To inject SSH access
when the rootfs is ext4 (unmountable from FreeBSD),
use QEMU to configure the image before writing it
to disk. See §"QEMU as a Cross-OS Chroot
Alternative."

If QEMU is not available, try mounting the image's
ext4 partition from FreeBSD (`mount -t ext2fs`).
Modern ext4 features often prevent this, but some
images work. If it mounts, inject
`/root/.ssh/authorized_keys` directly.

## Why dd-to-Live-Disk Fails

**Never dd a full disk image over the running
system's own disk.** This approach is tempting but
fails catastrophically:

- The running OS crashes when its root filesystem
  is overwritten mid-write. Buffers, metadata, and
  open files become inconsistent instantly.
- If dd does not complete (crash, I/O error, power
  loss), the disk is left in an inconsistent state
  — partially old OS, partially new image. The
  server is bricked with no recovery path.
- Even if the entire image is cached in RAM, the
  reboot command may not execute after the
  filesystem corruption that dd causes. The kernel
  panics or hangs instead of rebooting.
- On ZFS or other CoW filesystems, overwriting the
  underlying device corrupts pool metadata first,
  causing an immediate pool fault before dd
  finishes.

**Use hot-migration instead:** keep the old OS
running on a different partition while the new OS
is written to the freed partition. The old OS
remains intact as a fallback at every step.

**Exception:** dd to the live disk IS safe when a
fully self-contained tmpfs rescue environment is
running (see §"SSH-Only Replacement via Tmpfs
Rescue"). The rescue sshd and all its binaries
live in RAM — the disk overwrite does not affect
running processes. The old OS is lost, so a backup
is mandatory.

## QEMU as a Cross-OS Chroot Alternative

When the old and new OS are entirely different
(e.g. FreeBSD → Linux), `chroot` into the new
rootfs does not work — the running kernel cannot
execute binaries built for a different OS. Manual
package extraction (see next section) is one
workaround, but it is tedious and error-prone
because every postinst script must be replicated
by hand.

**Install QEMU on the old OS** and use it to boot
the new rootfs in a lightweight VM instead:

1. Install QEMU (`pkg install qemu` on FreeBSD,
   `apt-get install qemu-system-aarch64` on
   Debian, etc.).
2. Boot the new rootfs partition or image directly
   in QEMU, passing the real disk/partition as a
   block device.
3. Inside the QEMU VM, the new OS runs its own
   kernel — `dpkg`, `apt`, `chroot`, `useradd`,
   and all postinst scripts work normally.
4. Install and configure packages, generate SSH
   host keys, enable services, set up users — all
   with the real package manager.
5. Shut down the VM. The rootfs on the partition
   is now fully configured and ready to boot
   natively.

### When to prefer QEMU over manual extraction

- The new OS needs many packages installed or
  configured (manual extraction does not scale).
- Package postinst scripts are complex (e.g.
  `initramfs-tools`, kernel hooks, `dbus`
  machine-id generation).
- Same architecture but different OS kernel
  (e.g. FreeBSD aarch64 → Linux aarch64). QEMU
  uses KVM/HVF when available (near-native speed)
  or TCG software emulation (slow but functional
  — expect 5–15 minutes for a debootstrap).

### When manual extraction is still fine

- Only a few packages are needed (e.g. just
  `openssh-server`).
- The rootfs comes from a cloud image that already
  has most packages pre-installed.
- QEMU is not available or cannot be installed on
  the old OS.

## Manual Package Extraction into Offline Rootfs

When installing packages into a rootfs that cannot
be booted yet (e.g. cross-OS replacement via SSH,
where you mount the new root from the old OS),
`dpkg`/`apt`/`pkg` cannot run because the target
architecture or OS doesn't match the running host.
The workaround is to download `.deb` (or equivalent)
packages, extract their file contents, and place
them into the target rootfs manually.

**This bypasses all package manager scripts.** The
following critical steps are skipped and must be
handled manually:

### 1. System Users and Groups

Many services require dedicated system users
(e.g. `sshd` needs the `sshd` user). These are
normally created by the package's postinst script.

**Always check the package's postinst for
`adduser`/`useradd` calls** and create the required
users manually:

```
# Common service users to create:
useradd -r -d /run/sshd -s /usr/sbin/nologin sshd
useradd -r -d /var/lib/ntp -s /usr/sbin/nologin ntp
```

Write `useradd` commands directly into the target
rootfs's `/etc/passwd`, `/etc/shadow`, and
`/etc/group` if `chroot` is not possible (different
architecture or OS). Use the next available UID in
the system range (100–999).

### 2. Configuration Files

Package postinst scripts often generate config
files from templates or run `ucf` to manage them.
Copy the default config from the package's
`/usr/share/` directory:

```
# Example: openssh-server
cp <rootfs>/usr/share/openssh/sshd_config \
   <rootfs>/etc/ssh/sshd_config
```

### 3. Systemd Service Enablement

Extracting a `.deb` places the service unit files
in `/lib/systemd/system/`, but does **not** create
the symlinks in `/etc/systemd/system/*.wants/` that
enable the service. Create them manually:

```
ln -sf /lib/systemd/system/ssh.service \
  <rootfs>/etc/systemd/system/\
multi-user.target.wants/ssh.service
```

### 4. State Directories and Permissions

Some services need specific directories with
specific ownership:

```
mkdir -p <rootfs>/run/sshd
```

### Summary Checklist

Before rebooting into a rootfs with manually
extracted packages:

- [ ] All required system users/groups created
- [ ] Config files copied from defaults and
      customized
- [ ] Systemd services enabled via symlinks
- [ ] State/runtime directories created
- [ ] File ownership correct (especially for
      service users)

**If in doubt**, inspect the package's postinst
script. On Debian: download the `.deb`, run
`ar x <package>.deb`, extract `control.tar.*`,
and read the `postinst` file.

## GPT Partition Type Codes

When replacing one OS with another, the GPT
partition table retains the old OS's type codes.
For example, replacing FreeBSD with Linux leaves
partitions marked as `freebsd-swap` and
`freebsd-zfs` even though they now contain Linux
swap and ext4. **Always fix partition type codes
after a cross-OS replacement.**

Wrong type codes can confuse tools, installers,
and rescue systems that rely on them to identify
partition contents.

### Expected type codes by OS

| Partition    | Linux          | FreeBSD          |
|--------------|----------------|------------------|
| Root / data  | `8300` (Linux) | `516e7cb5-...`   |
| Swap         | `8200` (swap)  | `516e7cb5-...`   |
| EFI          | `ef00` (EFI)   | `ef00` (EFI)     |

### How to fix

**From Linux** (after replacement):

```
# sgdisk: -t PARTNUM:TYPECODE
sgdisk -t 2:8200 -t 3:8300 /dev/vda
partprobe /dev/vda
```

**From FreeBSD** (after replacement):

```
# gpart modify: -t TYPE -i PARTNUM DEVICE
gpart modify -t freebsd-swap -i 2 vtbd0
gpart modify -t freebsd-zfs -i 3 vtbd0
```

### When to fix

Fix partition types as a post-replacement step,
after the new OS is booted and confirmed working.
Verify with `fdisk -l` or `gpart show` — look for
type names that belong to the old OS.

## Cross-Family Considerations

When switching OS families (e.g. RHEL → Debian,
FreeBSD → Linux):

- **Package names differ.** `httpd` (RHEL) vs
  `apache2` (Debian) vs `apache24` (FreeBSD).
- **Config paths differ.** `/etc/nginx/` (Linux) vs
  `/usr/local/etc/nginx/` (FreeBSD).
- **Service managers differ.** systemd (Linux) vs
  rc.d (FreeBSD).
- **Firewall tools differ.** ufw/firewalld (Linux)
  vs pf (FreeBSD).
- **Config file syntax may differ** between
  versions of the same software on different
  distros. Don't blindly copy configs — review
  and adapt.

Read the rule file for the new OS family before
restoring services.

## Memory Updates

After replacement:
- Update `memory.md` with the new OS, services,
  and configuration.
- Keep the changelog — add an entry for the OS
  replacement.
- Delete `pre-replacement.md` once everything is
  confirmed working.
