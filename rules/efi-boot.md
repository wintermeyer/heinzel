# EFI Boot Management

Cross-OS rules for EFI boot management, dual-boot
setups, and boot loader configuration.

## When to Read

Read this file when:
- EFI is mentioned or relevant
- Setting up dual-boot
- Managing boot entries or boot order
- Installing or configuring a boot loader
- Troubleshooting boot issues

## Safety

- **Prefer BootNext** (one-shot) over BootOrder
  changes for testing.
- **Never delete boot entries** without asking the
  user first.
- **Verify before changing** — always show current
  state before modifying.
- **Keep the current default** until the new OS is
  confirmed working.
- A wrong BootOrder change can make the system
  unbootable (fixable via EFI shell or rescue, but
  disruptive).

## Inspecting EFI State

### Linux (efibootmgr)

```
efibootmgr -v          # all entries with paths
efibootmgr             # summary (BootOrder,
                        # BootCurrent, BootNext)
```

Key fields:
- `BootCurrent` — entry that booted this session
- `BootOrder` — persistent boot priority
- `BootNext` — one-shot override (cleared after use)

### FreeBSD (efibootmgr)

```
efibootmgr -v          # same command, same output
```

FreeBSD's `efibootmgr` has the same interface as
Linux. Install with `pkg install efibootmgr` if
missing.

## BootNext (One-Shot Boot)

The safe way to test a new OS or boot loader.
Boots the specified entry exactly once, then
reverts to the normal BootOrder.

```
# Linux
efibootmgr -n XXXX     # XXXX = boot entry number

# FreeBSD
efibootmgr -n XXXX
```

**Always use BootNext for the first boot into a
new OS.** If the new OS fails to boot, the next
reboot returns to the working OS automatically.

## BootOrder (Persistent)

Changes the default boot priority. Riskier than
BootNext — if the new entry doesn't work, the
system may boot into a broken OS repeatedly.

```
# Set new order (comma-separated entry numbers)
efibootmgr -o XXXX,YYYY,ZZZZ
```

**Only change BootOrder after BootNext has
confirmed the new entry works.**

## Boot Loaders

### systemd-boot

- Best choice for Linux on ARM64 and UEFI systems.
- Simple, reliable, no BIOS/CSM compatibility
  baggage.
- Config: `/boot/efi/loader/loader.conf` (or
  `/efi/loader/loader.conf` depending on mount).
- Entries: `/boot/efi/loader/entries/*.conf`
- Install: `bootctl install`
- Update: `bootctl update`
- Status: `bootctl status`
- Entry format:
  ```
  title   Debian 13
  linux   /vmlinuz
  initrd  /initrd.img
  options root=UUID=... rw
  ```

### GRUB (EFI)

- Works on x86_64 UEFI systems.
- **Does NOT work on ARM64/QEMU/UTM.** GRUB's
  ARM64 EFI support is unreliable in virtual
  machines — it fails silently or hangs.
  Use systemd-boot instead.
- Config: `/boot/grub/grub.cfg` (generated)
- Update: `update-grub` (Debian) or
  `grub2-mkconfig -o /boot/grub2/grub.cfg` (RHEL)
- Install to EFI: `grub-install --target=arm64-efi`
  (do not use on ARM64 VMs)

### FreeBSD Loader

- FreeBSD's native EFI boot loader.
- Binary: `/boot/loader.efi`
- Default EFI path: `/efi/freebsd/loader.efi` or
  `/efi/boot/bootaa64.efi` (ARM64) /
  `/efi/boot/bootx64.efi` (x86_64)
- Config: `/boot/loader.conf`
- The loader can also be installed as the default
  EFI boot entry at `/efi/boot/boot*.efi`.

## GRUB ARM64/QEMU Warning

**GRUB does not work reliably on ARM64 virtual
machines (UTM, QEMU).** This includes both aarch64
Linux guests and FreeBSD guests.

Symptoms:
- GRUB installs without errors but fails to boot
- Black screen or immediate reboot
- EFI shell drops to prompt instead of booting

**Use systemd-boot for Linux on ARM64 VMs.** For
FreeBSD, use the native FreeBSD loader.

## EFI System Partition Layout

The EFI System Partition (ESP) is typically the
first partition, formatted as FAT32, mounted at
`/boot/efi` (Linux) or `/boot/msdos` (FreeBSD).

Recommended layout for dual-boot:
```
/efi/
├── boot/
│   └── bootaa64.efi    # default fallback
├── freebsd/
│   └── loader.efi      # FreeBSD loader
├── systemd/
│   └── systemd-bootaa64.efi
├── loader/
│   ├── loader.conf     # systemd-boot config
│   └── entries/
│       ├── debian.conf
│       └── freebsd.conf
├── vmlinuz             # Linux kernel
└── initrd.img          # Linux initramfs
```

Both OSes share the same ESP. Each boot loader
gets its own subdirectory.

## Dual-Boot Considerations

- **Shared ESP:** Both OSes use the same EFI
  partition (typically p1). Do not create separate
  ESPs.
- **Boot entry per OS:** Create a separate EFI boot
  entry for each OS using `efibootmgr -c`.
- **systemd-boot menu:** Can include entries for
  both Linux and FreeBSD (chain-load FreeBSD's
  `loader.efi`).
- **FreeBSD entry in systemd-boot:**
  ```
  title   FreeBSD
  efi     /efi/freebsd/loader.efi
  ```
- **Default OS:** Set via BootOrder after both OSes
  are confirmed working.

## Kernel Updates with systemd-boot

systemd-boot does not auto-detect new kernels like
GRUB does. After a kernel update, copy the new
kernel and initramfs to the ESP manually:

```
cp /boot/vmlinuz-* /boot/efi/debian/vmlinuz
cp /boot/initrd.img-* /boot/efi/debian/initrd.img
```

If the boot entry uses specific filenames, update
the entry file in `/boot/efi/loader/entries/` to
match. Consider setting up a pacman/apt hook to
automate this.

## Display Issues on ARM64 VMs

On ARM64 virtual machines (UTM/QEMU), the boot
loader or early kernel may not produce visible
console output. This does not mean the boot failed.

- systemd-boot menu may not display — it still
  works, just boots the default entry silently.
- FreeBSD loader menu may not display on serial
  console.
- Add `console=ttyAMA0` (Linux) or configure
  serial console in `loader.conf` (FreeBSD) if
  console output is needed.

## Memory Convention

When recording boot configuration in server memory:
```
- Boot: EFI (systemd-boot)
- Boot: EFI (FreeBSD loader)
- Boot: EFI dual-boot (systemd-boot + FreeBSD)
```
