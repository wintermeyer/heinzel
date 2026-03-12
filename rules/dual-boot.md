# Dual-Boot Setup

Workflow rule for installing a second OS alongside
an existing one on the same machine.

## When to Read

Read this file when the user asks to:
- Install a second OS alongside an existing one
- Set up dual-boot (any combination of Linux,
  FreeBSD, macOS)
- Add Linux to a FreeBSD system or vice versa

Also read:
- `rules/efi-boot.md` — EFI boot management
- `rules/cloud-image.md` — if using a cloud image
- `rules/<family>.md` — for each OS involved

## Prerequisites

Before starting any dual-boot setup:

1. **Backup/snapshot.** Confirm the user has a
   backup of the existing system. If ZFS, suggest
   `zfs snapshot` of the root dataset.
2. **Know the partition layout.** Use the OS
   partition tool in read-only mode (`lsblk` on
   Linux, `gpart show` on FreeBSD, `diskutil list`
   on macOS).
3. **EFI required.** Dual-boot needs an EFI System
   Partition. Legacy BIOS dual-boot is not covered.
4. **Plan the layout** with the user before touching
   any partitions.

## Partition Planning

### Shared EFI Partition

Both OSes share the same EFI System Partition
(typically the first partition, FAT32, 260 MB+).
Do not create a second ESP.

### Separate Root Partitions

Each OS gets its own root partition. Never install
two OSes on the same partition.

### Swap

Linux and FreeBSD swap formats are incompatible.
Options:
- Each OS gets its own swap partition
- Skip swap on one OS (acceptable for VMs with
  enough RAM)
- Use a swap file instead of a partition (Linux
  only)

A swap partition can also be temporarily
repurposed as a staging filesystem during setup
(format as ext2, use for data transfer, then
reformat as swap when done).

### Sizing Guidelines

| Partition | Minimum | Recommended |
| --------- | ------- | ----------- |
| EFI (p1)  | 100 MB  | 260 MB      |
| OS root   | 8 GB    | 20+ GB      |
| Swap      | 0       | 1-2x RAM    |

## ZFS Root Repartitioning

When the existing OS uses ZFS on the entire disk
(common with FreeBSD), the ZFS pool must be shrunk
to make room for the second OS. ZFS does not
support shrinking, so a migration is required.

### The Problem

- `gpart resize` on a mounted ZFS partition fails
  with "Device busy".
- ZFS pools cannot be shrunk — the partition must
  be destroyed and recreated smaller.

### Migration Workflow

1. **Create a temporary small partition** in free
   space (or shrink an unused partition).
2. **Create a temporary ZFS pool** on it.
3. **Migrate data:** `zfs send -R pool@snap |
   zfs recv temppool`
4. **Reboot into the temporary pool.**
5. **Destroy the original pool and repartition.**
6. **Create the new (smaller) pool.**
7. **Migrate back:** `zfs send -R temppool@snap |
   zfs recv newpool`
8. **Reboot into the new pool.**
9. **Destroy the temporary pool** and reclaim its
   partition for the second OS.

### Pitfalls

- **Duplicate pool names:** When migrating, the
  temp pool and original pool may have the same
  name. Import by GUID:
  `zpool import -d /dev <guid> <name>`
- **Stale `zpool.cache`:** After migration, the
  cache file may reference the old pool. Clear it:
  `rm /boot/zfs/zpool.cache && zpool set
  cachefile=/boot/zfs/zpool.cache <pool>`
- **`loader.conf` on BOTH pools:** After migration,
  update `vfs.root.mountfrom` in `/boot/loader.conf`
  on the pool you're booting into.
- **Boot environment activation:** After `zfs recv`,
  activate the correct boot environment with
  `bectl activate`.

Reference: see `partitioning-howto.md` in
auto-memory for the exact command sequence used
on the UTM ARM64 setup.

## Filesystem Choice

When choosing a filesystem for the second OS
partition, consider cross-OS compatibility:

- **ext2:** FreeBSD can read and write via its
  `ext2fs` driver. Good for shared data or when
  the existing OS needs to write to the new
  partition during setup.
- **ext4:** Better for Linux-only partitions
  (journaling, performance, modern features).
  FreeBSD's `ext2fs` driver cannot handle modern
  ext4 features like `metadata_csum_seed` and
  `orphan_file`.
- **Conversion:** After the second OS boots
  successfully, ext2 can be converted to ext4:
  `tune2fs -O has_journal,extents,dir_index
  /dev/sdXn`
- **ZFS:** Usable on both FreeBSD and Linux
  (OpenZFS), but mixing root pools between OSes
  is not recommended.

## OS Installation Methods

### Cloud Image (Quickest)

Write a cloud image directly to the target
partition. See `rules/cloud-image.md` for post-
deployment steps (SSH keys, cloud-init, network).

Best when: the target filesystem doesn't need to
be accessed from the existing OS during setup.

### debootstrap in QEMU (Cleanest)

Boot a minimal Linux environment (e.g. via QEMU
or rescue mode), mount the target partition, and
use `debootstrap` to install a minimal Debian/
Ubuntu system.

Best when: FreeBSD is the existing OS and can't
mount the target filesystem (ext4), or when you
need fine-grained control over the installation.

### Network Install (Interactive)

Boot from an ISO and run the standard installer.
Hard to automate, but familiar to most users.

Best when: the user prefers the standard installer
experience.

## Boot Setup

See `rules/efi-boot.md` for detailed instructions.

Summary:
- **Linux on ARM64:** use systemd-boot (GRUB does
  not work on ARM64 VMs).
- **Linux on x86_64:** systemd-boot or GRUB both
  work.
- **FreeBSD:** use the native FreeBSD loader.
- **Both entries** go on the shared EFI partition.
- **systemd-boot** can chain-load FreeBSD's loader.

## Testing Safely

### BootNext (One-Shot)

**Always use BootNext for the first boot into the
new OS.** If it fails, the next reboot returns to
the original OS automatically.

```
efibootmgr -n XXXX    # boot entry for new OS
reboot
```

### Kernel Watchdog

Add to the Linux kernel command line for the first
test boot. If the system hangs, it reboots
automatically:

```
panic=30 hung_task_panic=1 softlockup_panic=1
```

### systemd Watchdog

In `/etc/systemd/system.conf`:
```
RuntimeWatchdog=60s
```

If systemd hangs for 60 seconds, the system
reboots.

### After Successful Test

Only after the new OS has booted successfully and
SSH access is confirmed:

1. Remove watchdog parameters from kernel cmdline.
2. Change BootOrder to set the desired default.

## Static IP

Both OSes should use the same IP address (only one
runs at a time). DHCP may assign different IPs per
OS because the DHCP client-id differs. Configure
a static IP on both OSes to avoid confusion.

## SSH Host Key Changes

When switching between OSes on a dual-boot system,
the SSH host keys change (each OS has its own).
The SSH client will warn about a "man-in-the-middle
attack" because the key for the IP changed.

Options:
- Accept the new key when prompted.
- Use `ssh -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null` for quick
  switches (less secure, acceptable on local VMs).
- Maintain separate `known_hosts` entries per OS
  (impractical with shared IP).

This is expected behavior, not a security issue,
as long as you initiated the OS switch yourself.

## Checklist

1. [ ] Backup or snapshot before starting
2. [ ] Partition layout planned and approved by user
3. [ ] Repartitioning complete, original OS boots
4. [ ] Second OS installed on target partition
5. [ ] Boot files on EFI partition
6. [ ] EFI boot entry created
7. [ ] SSH host keys present
8. [ ] cloud-init disabled (if cloud image)
9. [ ] Network configured (static IP)
10. [ ] BootNext test successful
11. [ ] Backup or snapshot of working dual-boot
