# Baseline Checks — macOS

Run these on macOS machines.

## Disk Usage

```bash
df -h /
```

- **WARN** if > 85% used
- **CRITICAL** if > 95% used

## Memory

```bash
vm_stat
sysctl -n hw.memsize
```

Parse `vm_stat` output to calculate used/free pages. Multiply by
page size (usually 16384 on Apple Silicon, 4096 on Intel — get
from `vm_stat` header).

- **WARN** if available memory < 10% of total

## System Load and Uptime

```bash
uptime
sysctl -n hw.ncpu
```

- **WARN** if 15-minute load average > core count

## Pending Software Updates

```bash
softwareupdate -l 2>&1
```

- **WARN** if updates are available

## Critical Auto-Updates

Check that critical security updates install automatically — see
`rules/macos.md` for the specific check.

- **WARN** if critical auto-updates are disabled

## Homebrew Packages

Only check if `brew` is available on the system.

```bash
command -v brew &>/dev/null && brew outdated
```

- **WARN** if any outdated packages are found — report the count
  and list them

## Application Firewall

```bash
/usr/libexec/ApplicationFirewall/socketfilterfw \
  --getglobalstate
```

- **INFO** if the firewall is off (not WARN — common and less
  critical on macOS behind NAT)

## SMART Disk Status

```bash
diskutil info disk0 | grep "SMART Status"
```

- **CRITICAL** if SMART status is not "Verified"

## Time Sync

```bash
sntp -t 1 time.apple.com 2>&1
```

- **WARN** if time offset > 5 seconds
