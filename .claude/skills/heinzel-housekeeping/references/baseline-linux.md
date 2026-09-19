# Baseline Checks — Linux

Run these on every Linux server.

## Backup Presence

Run the generic "any backup at all?" check — see
`references/backup-presence.md`. It runs on every host,
independent of `memory.md` service entries.

## Disk Usage

```bash
df -h --output=target,pcent,size,used,avail \
  -x tmpfs -x devtmpfs -x overlay
```

- **WARN** if any filesystem > 85% used
- **CRITICAL** if any filesystem > 95% used

## Memory and Swap

```bash
free -h
```

Report total, used, and available memory.

- **WARN** if available memory < 10% of total
- **WARN** if swap usage > 50% of total swap

## System Load

```bash
uptime
nproc
```

Report 1m, 5m, 15m load averages and core count.

- **WARN** if 15-minute load average > core count

## Uptime and Reboot Detection

```bash
uptime -s
last reboot | head -5
```

Report uptime. If the server rebooted since the last housekeeping
or last session, flag it:

- **INFO** unexpected reboot detected (compare with memory file's
  last known uptime or last connected date)

## Pending Security Updates

Use the distro-specific command from the loaded `rules/<family>.md`
file. Report two numbers where cheap: total pending upgrades and
the security-only subset. Do not present the total as "security
updates" — that overstates the finding.

The security-filter syntax varies by distro release. Per "Verify
Before Running" in `CLAUDE.md`, verify the flags with `--help` on
the target before relying on them.

**Debian/Ubuntu:**

```bash
apt-get update -qq 2>/dev/null

# Total pending upgrades.
apt-get --just-print upgrade 2>/dev/null \
  | grep -c "^Inst"

# Security-only subset: filter the Inst lines for
# security origins (Debian-Security on older
# releases, <codename>-security on newer ones,
# <codename>-security on Ubuntu).
apt-get --just-print upgrade 2>/dev/null \
  | grep "^Inst" \
  | grep -ciE "debian-security|[a-z]+-security"
```

**RHEL/CentOS/Fedora:**

```bash
# Total pending updates.
dnf check-update --quiet 2>/dev/null \
  | grep -c "^\S"

# Security-only subset.
dnf updateinfo --security 2>/dev/null
dnf check-update --security --quiet 2>/dev/null \
  | grep -c "^\S"
```

**SUSE:**

```bash
# Total pending updates.
zypper --quiet list-updates 2>/dev/null \
  | grep -c "^v"

# Security-only subset.
zypper list-patches --category security 2>/dev/null
```

- **WARN** if any security updates are pending
- Report both counts (total pending and security-only)

## Automatic Security Updates

Verify that auto-updates are actually installing security
updates, not just that the unit is enabled. A unit can be
"active" while the daily run does nothing. Real-world failure
modes that the simple `is-active` check misses:

- `/etc/apt/apt.conf.d/20auto-upgrades` missing or zeroed
  out: the timer fires but `APT::Periodic::Unattended-Upgrade`
  is `0`, so the daily run exits after one second.
- `Origins-Pattern` missing the `${distro_codename}-security`
  codename on Debian Trixie or later: `security.debian.org`
  publishes there with the `-security` codename, so security
  packages fail the filter even though
  `apt-cache policy` shows them as the install candidate.
- No `Mail` or `MailReport` set: UA errors never surface.
- Timer alive but only installing third-party packages
  (e.g. `mise`): the Debian security archive is unreachable
  for some reason and nobody knows.

**Debian/Ubuntu:**

```bash
# 1. Package present.
dpkg -l unattended-upgrades 2>/dev/null \
  | grep -q "^ii" && echo "pkg=ok" || echo "pkg=MISSING"

# 2. Daily timer enabled.
systemctl is-enabled apt-daily-upgrade.timer 2>/dev/null

# 3. APT::Periodic actually turns the runs on.
apt-config dump APT::Periodic 2>/dev/null \
  | grep -E "(Update-Package-Lists|Unattended-Upgrade) "

# 4. Origins-Pattern covers the codename-security archive
#    (Debian Trixie+ publishes Codename: <release>-security).
codename=$(. /etc/os-release && echo "$VERSION_CODENAME")
pattern="codename=\\\$\{distro_codename\}-security"
pattern="${pattern}|codename=${codename}-security"
apt-config dump Unattended-Upgrade::Origins-Pattern \
  2>/dev/null \
  | grep -qE "$pattern" \
  && echo "origins=ok" \
  || echo "origins=MISSING ${codename}-security pattern"

# 5. Notification destination set (else failures are silent).
apt-config dump 2>/dev/null \
  | grep -E "Unattended-Upgrade::(Mail |MailReport)"

# 6. Recent real activity: did a Debian package upgrade run
#    in the last 30 days, not just no-op runs?
zgrep -h "Pakete, welche aktualisiert werden\|Packages that will be upgraded" \
  /var/log/unattended-upgrades/unattended-upgrades.log* \
  2>/dev/null | tail -5
```

Severity rules (Debian-specific):

- **CRITICAL** if `20auto-upgrades` is missing or any of its
  values is `0`. The timer fires but does nothing — silent
  total failure.
- **CRITICAL** if `Origins-Pattern` is missing the
  `${distro_codename}-security` entry on Trixie or later.
  Every Debian security update is silently skipped.
- **WARN** if neither `Mail` nor `MailReport` is set. UA
  errors will be invisible.
- **WARN** if the log shows no Debian package upgrade lines
  in the last 30 days despite the timer running daily. UA is
  alive but accomplishing nothing for the Debian archive.
- **INFO** if `Automatic-Reboot-Time` is set to a fixed
  HH:MM: this defers the post-kernel reboot to that time
  the next day, leaving the new userland on the old kernel
  for up to ~24 hours (vulnerability window plus risk of
  userland/kernel ABI mismatch). Prefer the default ("now")
  so reboot follows the apt-daily-upgrade morning slot.

**RHEL/CentOS/Fedora:**

```bash
systemctl is-active dnf-automatic.timer 2>/dev/null \
  || systemctl is-active yum-cron.service 2>/dev/null
```

**SUSE:**

Check if `zypper-patch` or equivalent auto-update timer is
configured.

- **WARN** if auto-update mechanism is not active

## Firewall Status

Check that the firewall is still active.

**Debian/Ubuntu (ufw):**

```bash
ufw status
```

**RHEL/CentOS/Fedora (firewalld):**

```bash
firewall-cmd --state
```

**SUSE (firewalld):**

```bash
firewall-cmd --state
```

- **CRITICAL** if the firewall is inactive or not installed

## Failed systemd Units

```bash
systemctl --failed --no-pager --no-legend
```

- **WARN** for each failed unit — list them by name

## NTP / Time Sync

```bash
timedatectl show \
  --property=NTPSynchronized --value
```

- **WARN** if NTP is not synchronized

## Log Anomalies

Check for recent critical events:

```bash
# OOM kills in the last 7 days
journalctl --since "7 days ago" -k \
  --grep="Out of memory" --no-pager -q 2>/dev/null \
  | wc -l

# Disk errors in the last 7 days
journalctl --since "7 days ago" -k \
  --grep="I/O error" --no-pager -q 2>/dev/null \
  | wc -l

# Failed SSH auth in the last 24 hours
journalctl --since "24 hours ago" -u ssh -u sshd \
  --grep="Failed password" --no-pager -q 2>/dev/null \
  | wc -l
```

- **WARN** if any OOM kills found
- **WARN** if any disk I/O errors found
- **INFO** if > 100 failed SSH logins in 24 hours (may indicate
  brute-force attempts)

## SSL/TLS Certificate Expiry

Only check if the server runs a web server or any TLS-enabled
service (check `memory.md` for nginx, Apache, etc.).

```bash
# Check all certs in /etc/letsencrypt/live/
for cert in /etc/letsencrypt/live/*/cert.pem; do
  domain=$(basename "$(dirname "$cert")")
  expiry=$(openssl x509 -enddate -noout \
    -in "$cert" 2>/dev/null \
    | cut -d= -f2)
  days=$(( ($(date -d "$expiry" +%s) \
    - $(date +%s)) / 86400 ))
  echo "$domain: ${days}d remaining"
done
```

If no Let's Encrypt certs exist, try checking via the listening
port:

```bash
echo | openssl s_client -connect localhost:443 \
  -servername "$(hostname -f)" 2>/dev/null \
  | openssl x509 -enddate -noout 2>/dev/null
```

- **CRITICAL** if any cert expires in < 7 days
- **WARN** if any cert expires in < 30 days

## SSH Host Certificate Expiry

Only when `memory.md` has an `SSH host cert:` line.
Run the loop from `rules/ssh-certificates.md` → Host
certificate (no root) in the same call as the TLS
check above, and rate it with the severities listed
there.

## Kernel: Running vs Installed

Check whether a reboot is needed for a kernel update.

**Debian/Ubuntu:**

```bash
running=$(uname -r)
installed=$(dpkg -l 'linux-image-*' 2>/dev/null \
  | grep "^ii" | awk '{print $2}' \
  | sed 's/linux-image-//' | sort -V | tail -1)
echo "Running: $running"
echo "Installed: $installed"
```

**RHEL/CentOS/Fedora:**

```bash
running=$(uname -r)
installed=$(rpm -q kernel --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' \
  | sort -V | tail -1)
echo "Running: $running"
echo "Installed: $installed"
```

- **INFO** if running kernel differs from installed (reboot
  recommended)

## Critical Services: Running Binary vs Installed Package

A package upgrade installs new bytes on disk, but the
already-running master keeps the old binary mapped in
memory until the service is reloaded or restarted. After
a package upgrade, `needrestart` may also defer some
services because restarting them is risky (notably
`docker.service`, `dbus.service`, `getty@*`,
`systemd-logind`). The result: the security fix is
installed but not active, and nothing complains.

**Debian/Ubuntu** (needrestart is in the default
install since Bookworm):

```bash
if command -v needrestart >/dev/null 2>&1; then
  needrestart -b -p 2>&1
fi
```

`needrestart -b` (batch) emits machine-readable
`NEEDRESTART-VER`, `NEEDRESTART-KCUR`, `NEEDRESTART-KEXP`,
`NEEDRESTART-KSTA`, `NEEDRESTART-UCSTA`, and one
`NEEDRESTART-SVC:` line per service that wants a restart.
Exit code: 0 = nothing, 1 = containers, 2 = services,
3 = kernel.

Manual fallback (any Linux), works without needrestart by
comparing the on-disk binary's mtime against the running
process's start time via `/proc/<pid>/exe`:

```bash
for svc in nginx postfix sshd postgres docker ollama \
           opendkim dovecot mariadbd; do
  pid=$(pgrep -o -x "$svc" 2>/dev/null) || continue
  bin=$(readlink -f "/proc/$pid/exe" 2>/dev/null) \
    || continue
  bin_time=$(stat -c %Y "$bin" 2>/dev/null) || continue
  proc_time=$(stat -c %Y "/proc/$pid" 2>/dev/null) \
    || continue
  if [ "$bin_time" -gt "$proc_time" ]; then
    echo "$svc: on-disk binary newer than running \
process (pkg installed after process started)"
  fi
done
```

- **WARN** for each critical service whose on-disk binary
  is newer than the running master. The security patch is
  installed but the running process has not picked it up.
- **INFO** if `needrestart` reports kernel or services
  that want a reboot/restart (`NEEDRESTART-KSTA` not 1, or
  any `NEEDRESTART-SVC:` line). For deferred services,
  reload is usually enough; for the kernel, only a reboot
  helps.
