# Housekeeping — Routine Server Inspection

Checklist for routine health checks on servers and
macOS machines. Run these checks when the user asks
for a housekeeping inspection. Never run automatically
— only on explicit request.

Read both this file (baseline) and
`memory/housekeeping.md` (custom checks, if it exists)
before starting a housekeeping run.

## Report Format

Present results in this format:

```
## Housekeeping Report: hostname

Date: YYYY-MM-DD HH:MM
OS: Debian 12 (Bookworm) | Last boot: 14 days ago

### Issues

CRITICAL  Disk / at 97%
WARN      12 security updates pending
WARN      SSL cert expires in 12 days

### Services

PostgreSQL    OK — 4 databases, 2.1 GB total
nginx         OK — config valid
Backups       OK — latest 6 hours ago

### System

Disk       / 58% (1.0 TB / 1.8 TB)
Memory     8.2 GB / 64 GB available
Load       0.42 / 0.38 / 0.35 (4 cores)
Firewall   ufw active, deny incoming
NTP        synchronized
Kernel     6.1.0-31 (matches installed — no reboot
           needed)
Updates    0 pending
Auto-updates  unattended-upgrades active
Versions   2 updates available (see below)
```

**Rules:**

- **Issues section** only appears if problems exist.
  Sort by severity: CRITICAL first, then WARN, then
  INFO.
- **Services section** only appears if the server has
  services in its memory file.
- **One line per item.** Keep it scannable.
- Severity levels:
  - `CRITICAL` — needs immediate attention
  - `WARN` — should be addressed soon
  - `INFO` — informational, not urgent

## Baseline Checks — Linux

Run these on every Linux server.

### Disk Usage

```bash
df -h --output=target,pcent,size,used,avail \
  -x tmpfs -x devtmpfs -x overlay
```

- **WARN** if any filesystem > 85% used
- **CRITICAL** if any filesystem > 95% used

### Memory and Swap

```bash
free -h
```

Report total, used, and available memory.

- **WARN** if available memory < 10% of total
- **WARN** if swap usage > 50% of total swap

### System Load

```bash
uptime
nproc
```

Report 1m, 5m, 15m load averages and core count.

- **WARN** if 15-minute load average > core count

### Uptime and Reboot Detection

```bash
uptime -s
last reboot | head -5
```

Report uptime. If the server rebooted since the last
housekeeping or last session, flag it:

- **INFO** unexpected reboot detected (compare with
  memory file's last known uptime or last connected
  date)

### Pending Security Updates

Use the distro-specific command from the loaded
`rules/<family>.md` file.

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

### Automatic Security Updates

Verify the auto-update mechanism is active. Use the
distro-specific check from `rules/<family>.md`.

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

Check if `zypper-patch` or equivalent auto-update
timer is configured.

- **WARN** if auto-update mechanism is not active

### Firewall Status

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

- **CRITICAL** if the firewall is inactive or not
  installed

### Failed systemd Units

```bash
systemctl --failed --no-pager --no-legend
```

- **WARN** for each failed unit — list them by name

### NTP / Time Sync

```bash
timedatectl show \
  --property=NTPSynchronized --value
```

- **WARN** if NTP is not synchronized

### Log Anomalies

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
- **INFO** if > 100 failed SSH logins in 24 hours
  (may indicate brute-force attempts)

### SSL/TLS Certificate Expiry

Only check if the server runs a web server or any
TLS-enabled service (check memory.md for nginx,
Apache, etc.).

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

If no Let's Encrypt certs exist, try checking via
the listening port:

```bash
echo | openssl s_client -connect localhost:443 \
  -servername "$(hostname -f)" 2>/dev/null \
  | openssl x509 -enddate -noout 2>/dev/null
```

- **CRITICAL** if any cert expires in < 7 days
- **WARN** if any cert expires in < 30 days

### Kernel: Running vs Installed

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

- **INFO** if running kernel differs from installed
  (reboot recommended)

## Baseline Checks — macOS

Run these on macOS machines.

### Disk Usage

```bash
df -h /
```

- **WARN** if > 85% used
- **CRITICAL** if > 95% used

### Memory

```bash
vm_stat
sysctl -n hw.memsize
```

Parse `vm_stat` output to calculate used/free pages.
Multiply by page size (usually 16384 on Apple
Silicon, 4096 on Intel — get from `vm_stat` header).

- **WARN** if available memory < 10% of total

### System Load and Uptime

```bash
uptime
sysctl -n hw.ncpu
```

- **WARN** if 15-minute load average > core count

### Pending Software Updates

```bash
softwareupdate -l 2>&1
```

- **WARN** if updates are available

### Critical Auto-Updates

Check that critical security updates install
automatically — see `rules/macos.md` for the
specific check.

- **WARN** if critical auto-updates are disabled

### Homebrew Packages

Only check if `brew` is available on the system.

```bash
command -v brew &>/dev/null && brew outdated
```

- **WARN** if any outdated packages are found —
  report the count and list them

### Application Firewall

```bash
/usr/libexec/ApplicationFirewall/socketfilterfw \
  --getglobalstate
```

- **INFO** if the firewall is off (not WARN — common
  and less critical on macOS behind NAT)

### SMART Disk Status

```bash
diskutil info disk0 | grep "SMART Status"
```

- **CRITICAL** if SMART status is not "Verified"

### Time Sync

```bash
sntp -t 1 time.apple.com 2>&1
```

- **WARN** if time offset > 5 seconds

## Version Status

Run the version check procedure from
`rules/version-check.md` for all Tier 1 software.
Include the "Versions" section in the report.

## Service-Specific Checks

These checks are triggered by services listed in the
server's `memory.md`. Only run checks for services
that are actually present.

### PostgreSQL

Triggered when memory.md mentions PostgreSQL.

```bash
pg_isready
sudo -u postgres psql -t -A -c \
  "SELECT datname, pg_size_pretty(pg_database_size(datname))
   FROM pg_database
   WHERE datistemplate = false
   ORDER BY pg_database_size(datname) DESC;"
```

- **CRITICAL** if `pg_isready` reports not accepting
  connections
- Report database names and sizes

### Backups (autopostgresqlbackup)

Triggered when memory.md mentions
autopostgresqlbackup or PostgreSQL backups.

```bash
# Find the most recent backup file
ls -lt /var/backups/postgresql/ 2>/dev/null \
  | head -5
```

- **WARN** if latest backup is older than 25 hours
- **CRITICAL** if no backup found or older than 48
  hours

### Cross-Backup (rsync)

Triggered when memory.md mentions cross-backup or
rsync backups.

Check the age of the most recent backup pull by
looking at the timestamp of the latest file or log
entry. The specific path depends on the server's
backup configuration — check memory.md for details.

- **WARN** if latest pull is older than 25 hours
- **CRITICAL** if older than 48 hours

### Docker

Triggered when memory.md mentions Docker.

```bash
docker ps --format \
  "table {{.Names}}\t{{.Status}}\t{{.Ports}}" \
  2>/dev/null
```

- **WARN** for any container not in "Up" state
- Report container names and status

### nginx

Triggered when memory.md mentions nginx.

```bash
nginx -t 2>&1
systemctl is-active nginx
```

- **WARN** if config test fails
- **CRITICAL** if nginx is not running

### Ollama

Triggered when memory.md mentions Ollama.

```bash
curl -s -o /dev/null -w "%{http_code}" \
  http://localhost:11434/api/tags
```

- **WARN** if API does not respond with 200

### node_exporter

Triggered when memory.md mentions node_exporter or
Prometheus.

```bash
curl -s -o /dev/null -w "%{http_code}" \
  http://localhost:9100/metrics
```

- **WARN** if metrics endpoint does not respond with
  200

### NVIDIA GPU

Triggered when memory.md mentions NVIDIA or GPU.

```bash
nvidia-smi \
  --query-gpu=temperature.gpu,utilization.gpu,\
utilization.memory,memory.used,memory.total \
  --format=csv,noheader,nounits 2>/dev/null
```

- **WARN** if GPU temperature > 85°C
- **CRITICAL** if GPU temperature > 95°C
- Report temperature, GPU utilization, memory usage

### MariaDB / MySQL

Triggered when memory.md mentions MariaDB or MySQL.

```bash
mysqladmin status 2>/dev/null \
  || mariadb-admin status 2>/dev/null
```

- **CRITICAL** if the database is not responding
- Report uptime and thread count

### WireGuard

Triggered when memory.md mentions WireGuard.

```bash
wg show 2>/dev/null
```

Check each peer's latest handshake timestamp.

- **WARN** if any peer's last handshake was > 5
  minutes ago (may indicate connectivity issues)
- Report interface names and peer handshake ages

## Unprivileged Mode

When running in unprivileged mode (no sudo, no root
SSH), run every check that works as a regular user
and skip those that require root.

At the end of the report, add a section:

```
### Skipped (needs root)

- Pending security updates (apt-get update)
- Firewall status (ufw requires root)
- SSL certificate files (/etc/letsencrypt/)
```

List each skipped check with a brief reason.

## After the Report

1. **Update memory.md** if the checks revealed
   changed facts (e.g. disk usage changed
   significantly, a new service appeared, a service
   was removed).
2. **Log to changelog** — a one-line summary:
   ```
   logger -t heinzel "Housekeeping: 1 CRITICAL, \
   2 WARN, all services OK"
   ```
3. **Mirror to local changelog.log** in compressed
   form.

## Custom Checks

Users can add their own checks in
`memory/housekeeping.md` (gitignored). This file
is read alongside the baseline checks. Create it
when needed — do not pre-create an empty file.

Format: free-form Markdown. Describe what to check,
what commands to run, and what thresholds to use.
Claude reads the file and incorporates the checks
into the housekeeping run for all servers.

Example:

    ### Check LimeSurvey cron
    On servers with LimeSurvey, verify the cron job
    runs daily:
        crontab -l | grep limesurvey
    WARN if no cron entry found.
