# Partition Staging

Strategy for freeing disk partitions for
repartitioning, OS replacement, or other disk
layout changes — without losing data and without
physical access.

## When to Read

Read this file when:
- Replacing an OS on a server (cross-reference
  with `rules/os-replacement.md`)
- Repartitioning a live system
- Needing temporary workspace on a partition that
  is currently in use (e.g. swap)
- Needing to free a partition that belongs to a
  volume manager or pooled filesystem

## Core Idea

Most servers have at least one partition that can
be temporarily repurposed: the swap partition.
Additionally, filesystems that support hot
add/remove of devices (ZFS, LVM, btrfs) allow
migrating data off a partition while the system
is running, freeing it for other use.

Combine both techniques for maximum flexibility:

1. **Reclaim swap** — turn off swap, gain a free
   partition.
2. **Hot-migrate** — if the root or data filesystem
   supports device hot-remove, add the former swap
   partition to the pool, migrate data off the
   original partition, then remove the original
   partition from the pool. Now the original
   partition is free for repartitioning.
3. **Reverse** (optional) — after repartitioning,
   add the repartitioned device back, migrate data
   onto it, remove the staging device, and restore
   swap.

## Prerequisites

### RAM Check

Before disabling swap, verify there is enough
free RAM to absorb any pages currently in swap.

```
# Linux
free -m    # compare: Free RAM > Used swap
swapon --show

# FreeBSD
swapinfo
sysctl hw.usermem
```

**Rule:** free RAM after absorbing used swap must
be at least **512 MB**. If not, free memory first
(stop non-essential services, drop caches) or
abort.

### Swap Usage Check

If swap usage is zero or near-zero, swapoff is
safe and instant. If swap is heavily used, the
kernel must page everything back into RAM — this
can take time and risks OOM kills on tight
systems.

## Step 1: Reclaim the Swap Partition

### Linux

```
swapoff /dev/sdXn          # or /dev/vdXn, etc.
```

### FreeBSD

```
swapoff /dev/vtbd0p2       # or /dev/ada0p2
```

Verify with `swapon --show` (Linux) or
`swapinfo` (FreeBSD). The partition is now free.

## Step 2: Use Swap as Simple Staging

For basic tasks (storing an image, backup
archive, debootstrap target), format and mount
the former swap partition:

```
# Linux
mkfs.ext2 /dev/sdXn
mount /dev/sdXn /mnt/staging

# FreeBSD (ext2 for cross-OS compatibility)
newfs /dev/vtbd0p2         # UFS
mount /dev/vtbd0p2 /mnt/staging
```

This is sufficient for many OS replacement
scenarios. Skip to "Restore Swap" when done.

## Step 3: Hot-Migrate with Pooled Filesystems

When the staging partition alone is too small,
or you need to free the *main* partition, use
the filesystem's hot add/remove capability.

### ZFS

```
# Add former swap to the pool
zpool add poolname /dev/sdXn

# Migrate data off the original device
# (ZFS mirrors: use zpool detach/attach;
#  ZFS stripes: use zpool remove if supported)
zpool remove poolname /dev/sdYn

# Verify removal is complete
zpool status poolname
```

**Note:** `zpool remove` requires ZFS pool
feature `device_removal`. Verify with:

```
zpool get feature@device_removal poolname
```

It works for **any top-level vdev** — including
the original root vdev, not just vdevs added
later — as long as:
- `feature@device_removal` is enabled
- Remaining vdevs have enough free space for the
  data being evacuated
- The vdev is not part of a mirror or raidz

For mirrors, use `zpool detach` instead.

After removal, the original partition is free.

### LVM

```
# Create a PV on the former swap partition
pvcreate /dev/sdXn

# Extend the VG
vgextend vgname /dev/sdXn

# Migrate data off the original PV
pvmove /dev/sdYn

# Remove the original PV from the VG
vgreduce vgname /dev/sdYn
pvremove /dev/sdYn
```

The original partition is now free.

### btrfs

```
# Add the former swap partition
btrfs device add /dev/sdXn /mountpoint

# Remove the original device (migrates data)
btrfs device delete /dev/sdYn /mountpoint
```

`btrfs device delete` rebalances data onto
remaining devices automatically.

### OS Replacement Use Case

After freeing the main partition via hot-migration,
delete it and create new partitions for the
replacement OS. For example on FreeBSD with GPT:

```
gpart delete -i 3 vtbd0       # remove old root
gpart add -t freebsd-swap -s 2G vtbd0  # new swap
gpart add -t linux-data vtbd0  # new root (rest)
```

The old OS continues running from the swap
partition. Install the new OS to the new root
partition, set up the bootloader, and reboot. See
`rules/os-replacement.md` §"SSH-Only Replacement
via Hot-Migration" for the full workflow.

## Step 4: Repartition

With the target partition freed, repartition as
needed using the appropriate tool for the OS and
partition table type.

**Caution:** repartitioning a live disk can
confuse the kernel's in-memory partition table.
On Linux, use `partprobe` or `kpartx` to reload.
On FreeBSD, the kernel may not see changes until
reboot.

## Step 5: Restore Swap (Optional)

After the task is complete, restore swap if
desired:

```
# Linux
mkswap /dev/sdXn
swapon /dev/sdXn

# FreeBSD
# Swap partition type is set via gpart;
# no formatting needed.
swapon /dev/vtbd0p2
```

Update `/etc/fstab` (Linux) or `/etc/rc.conf`
(FreeBSD) to match. Restoring swap is optional —
some administrators prefer to leave the space
for the filesystem.

## Reverse Migration (Optional)

To move data back to the original (now
repartitioned) device and free the staging
partition:

1. Add the repartitioned device to the pool.
2. Migrate data back (`pvmove`, `zpool remove`,
   `btrfs device delete` on the staging device).
3. Remove the staging device from the pool.
4. Restore it as swap or repurpose it.

This is useful for non-destructive repartitioning
where the final layout should match the original
device assignments.

## FreeBSD: Raw Disk Write Protection

FreeBSD's GEOM framework blocks writes to raw
disk devices (`/dev/vtbd0`, `/dev/ada0`) when
partitions are active. To override:

```
sysctl kern.geom.debugflags=0x10
```

This sets flag 16 (allow writes to active
providers). Required for `dd` to a raw disk
during OS replacement. **Reset after use:**

```
sysctl kern.geom.debugflags=0
```

## Decision Flowchart

```
Need to free a partition on a live system?
  |
  +-- Is there a swap partition?
  |     |
  |     +-- YES: Check RAM (free > used swap
  |     |        + 512 MB). swapoff.
  |     |     |
  |     |     +-- Is the freed swap enough?
  |     |           |
  |     |           +-- YES -> Use as staging
  |     |           |          (Step 2)
  |     |           +-- NO  -> Hot-migrate
  |     |                      (Step 3)
  |     +-- NO: Look for other reclaimable
  |              partitions (unused data,
  |              /boot if oversized, etc.)
  |
  +-- Does the filesystem support hot
       add/remove? (ZFS, LVM, btrfs)
        |
        +-- YES -> Add temp space, migrate,
        |          remove original (Step 3)
        +-- NO  -> Cannot free partition
                   without downtime.
```
