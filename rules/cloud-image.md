# Cloud Image Deployment

Rules for deploying Linux from pre-built cloud
images (qcow2, raw, VMDK).

## When to Read

Read this file when:
- Deploying a VM from a cloud image
- Working with qcow2, raw, or VMDK images
- User mentions "cloud image" or "cloud-init"
- Troubleshooting a freshly deployed VM that won't
  boot or accept SSH

## Common Issues

Cloud images are built for cloud environments
(AWS, GCP, Azure) and expect cloud-init to
configure them on first boot. When used outside
a cloud provider, several things break.

### 1. Missing SSH Host Keys

Cloud images ship without SSH host keys — they
expect cloud-init to generate them on first boot.
If cloud-init is disabled or broken, `sshd` fails
to start.

**Fix:**
```
ssh-keygen -A
systemctl restart sshd
```

### 2. cloud-init Hanging

cloud-init tries to contact a metadata service
(e.g. `169.254.169.254`) that doesn't exist
outside a cloud provider. It retries for minutes,
blocking boot.

**Fix — disable permanently:**
```
touch /etc/cloud/cloud-init.disabled
systemctl disable cloud-init.service \
  cloud-init-local.service \
  cloud-config.service \
  cloud-final.service
```

**Or mask all units:**
```
systemctl mask cloud-init.service \
  cloud-init-local.service \
  cloud-config.service \
  cloud-final.service
```

### 3. networkd-wait-online Blocking Boot

`systemd-networkd-wait-online.service` waits for
all network interfaces to be fully configured.
If the network isn't set up correctly, this blocks
boot for up to 2 minutes.

**Fix:**
```
systemctl mask systemd-networkd-wait-online.service
```

### 4. Wrong or No IP Address

Cloud images expect DHCP from a cloud provider's
network. On a local VM or bare metal, the network
may not be configured correctly.

**Check:**
```
ip addr show
networkctl status
```

**Fix:** Configure static IP via
`/etc/systemd/network/*.network` or
`/etc/network/interfaces` depending on the distro.

### 5. No Root Password / No SSH Access

Cloud images typically have no root password set
and expect SSH key injection via cloud-init.

**Fix (from console or rescue):**
```
passwd root
# or
mkdir -p /root/.ssh
cat >> /root/.ssh/authorized_keys <<'EOF'
ssh-ed25519 AAAA... user@host
EOF
chmod 700 /root/.ssh
chmod 600 /root/.ssh/authorized_keys
```

### 6. Nocloud Images: No SSH Server

Debian `nocloud` cloud images do **not** include
`openssh-server`. They are designed for console
access with an empty root password. If deploying
a nocloud image for SSH-only access, openssh-server
must be installed before the first boot.

When installing packages into an offline rootfs
(e.g. mounting the image from a different OS),
read `rules/os-replacement.md` §"Manual Package
Extraction into Offline Rootfs" — extracting
`.deb` files without `dpkg` skips critical postinst
steps like creating the `sshd` system user.

**Minimum steps for SSH-ready nocloud image:**

1. Extract openssh-server and dependencies into
   the rootfs
2. Create the `sshd` system user:
   `useradd -r -d /run/sshd -s /usr/sbin/nologin sshd`
3. Copy default config:
   `cp usr/share/openssh/sshd_config etc/ssh/`
4. Set `PermitRootLogin yes` in sshd_config
5. Generate SSH host keys: `ssh-keygen -A`
   (or generate from the host OS — key format is
   compatible across OSes)
6. Inject authorized_keys for root
7. Enable the service:
   `ln -sf /lib/systemd/system/ssh.service
   etc/systemd/system/multi-user.target.wants/`
8. Set a root password in `/etc/shadow`

## Post-Deployment Checklist

After deploying a cloud image, verify:

1. [ ] `sshd` is installed (nocloud images may
       lack it — see §6 above)
2. [ ] SSH host keys exist
       (`ls /etc/ssh/ssh_host_*`)
3. [ ] `sshd` is running
4. [ ] `sshd` system user exists
       (`id sshd`)
5. [ ] cloud-init is disabled or masked
6. [ ] `networkd-wait-online` is masked
7. [ ] Network is configured (static IP or DHCP)
8. [ ] Root access works (password or SSH key)
9. [ ] Hostname is set (`hostnamectl set-hostname`)
10. [ ] Package manager works (`apt-get update` or
       equivalent)

## Image Conversion

Convert between image formats:

```
# qcow2 to raw
qemu-img convert -f qcow2 -O raw image.qcow2 \
  image.raw

# raw to qcow2
qemu-img convert -f raw -O qcow2 image.raw \
  image.qcow2

# Write raw image to disk/partition
dd if=image.raw of=/dev/sdX bs=4M status=progress
```

When writing to a partition (not a full disk),
mount and extract — do not `dd` a full-disk image
onto a single partition.

## ARM64 / QEMU Considerations

Debian ARM64 cloud images use GRUB as the default
bootloader. GRUB fails silently on ARM64 QEMU/UTM
VMs — the VM hangs at boot with no error output.
See `rules/efi-boot.md` for details.

**After deploying an ARM64 cloud image on
QEMU/UTM, replace GRUB with systemd-boot before
the first boot.** This applies to both genericcloud
and nocloud images.

### Modifying the image from a non-Linux OS

When preparing the rootfs from a different OS
(e.g. FreeBSD), standard Linux mount tools are
unavailable. Use `debugfs` (from the `e2fsprogs`
package) to inject files into an ext4 rootfs
without mounting it:

```
# Write a local file into the image's filesystem
debugfs -w -R \
  "write /tmp/local-file /etc/target-path" \
  /dev/vtbd0p4
```

This is useful for injecting SSH keys, network
configs, and bootloader files into a Debian rootfs
from FreeBSD. Install e2fsprogs via `pkg install
e2fsprogs` on FreeBSD.

## Memory Convention

When recording cloud image origin in server memory:
```
- Origin: cloud image (Debian 13 genericcloud)
```
