# File Permissions — Linux

## World-Writable System Files

```bash
find /etc /usr /bin /sbin -xdev -type f \
  -perm -0002 2>/dev/null
```

No root needed (finds files based on permissions of
world-readable directories).

- Any file found → **WARN** per file
- None found → OK

## SUID/SGID Binary Audit

```bash
find / -xdev -type f \
  \( -perm -4000 -o -perm -2000 \) 2>/dev/null
```

No root needed. Report the total count.

**Known-good SUID/SGID binaries** (do not flag): `sudo`, `su`,
`passwd`, `chsh`, `chfn`, `newgrp`, `gpasswd`, `mount`,
`umount`, `ping`, `ping6`, `fusermount`, `fusermount3`,
`pkexec`, `unix_chkpwd`, `crontab`, `ssh-agent`, `at`, `expiry`,
`wall`, `write`, `dotlockfile`, `mount.nfs`, `mount.cifs`,
`staprun`.

Any binary not in this list → **INFO** with full path. The user
can assess whether it belongs.

## /tmp and /dev/shm Mount Options — Linux only

```bash
mount | grep -E '(/tmp |/dev/shm )'
```

Or use `findmnt`:

```bash
findmnt -n -o OPTIONS /tmp 2>/dev/null
findmnt -n -o OPTIONS /dev/shm 2>/dev/null
```

- `/dev/shm` lacks `noexec` → **WARN**
- `/tmp` lacks `noexec` → **INFO**
- `/tmp` is not a separate mount → **INFO** (note that it shares
  the root filesystem)

## Cron Directory Permissions

```bash
stat -c '%a %U %G %n' \
  /etc/crontab \
  /etc/cron.d \
  /etc/cron.daily \
  /etc/cron.hourly \
  /etc/cron.weekly \
  /etc/cron.monthly 2>/dev/null
```

- Any of these world-writable (xx7 or xx6 with group=other) →
  **CRITICAL**
- World-readable but not writable → **INFO**
- Owner root, no world access → OK

## Unowned Files

```bash
find /etc /usr /var -xdev \
  \( -nouser -o -nogroup \) 2>/dev/null
```

Limit to these key directories to avoid excessive scan time on
large filesystems.

- Any unowned file found → **INFO** per file
- None found → OK
