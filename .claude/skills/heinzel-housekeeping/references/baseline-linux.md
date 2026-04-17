# Baseline Checks — Linux

Run these on every Linux server.

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
file.

**Debian/Ubuntu:**

```bash
apt-get update -qq 2>/dev/null
apt-get --just-print upgrade 2>/dev/null \
  | grep -c "^Inst"
```

**RHEL/CentOS/Fedora:**

```bash
dnf check-update --quiet 2>/dev/null \
  | grep -c "^\S"
```

**SUSE:**

```bash
zypper --quiet list-updates 2>/dev/null \
  | grep -c "^v"
```

- **WARN** if any security updates are pending
- Report the count

## Automatic Security Updates

Verify the auto-update mechanism is active. Use the distro-specific
check from `rules/<family>.md`.

**Debian/Ubuntu:**

```bash
systemctl is-active unattended-upgrades.service
dpkg -l unattended-upgrades 2>/dev/null \
  | grep -q "^ii" && echo "installed" \
  || echo "not installed"
```

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
