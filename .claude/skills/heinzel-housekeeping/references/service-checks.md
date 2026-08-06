# Service-Specific Checks

These checks are triggered by services listed in the server's
`memory.md`. Only run checks for services that are actually
present.

## PostgreSQL

Triggered when `memory.md` mentions PostgreSQL.

```bash
pg_isready
sudo -u postgres psql -t -A -c \
  "SELECT datname, pg_size_pretty(pg_database_size(datname))
   FROM pg_database
   WHERE datistemplate = false
   ORDER BY pg_database_size(datname) DESC;"
```

- **CRITICAL** if `pg_isready` reports not accepting connections
- Report database names and sizes

## Backups (autopostgresqlbackup)

Triggered when `memory.md` mentions autopostgresqlbackup or
PostgreSQL backups. (These are *specific* backup checks; the
generic "any backup at all?" presence check lives in
`references/backup-presence.md` and always runs.)

**Check every retention tier separately.** These tools write
`daily/`, `weekly/` and `monthly/` subtrees, each on its own
schedule. A single "newest file anywhere" check is always green
as long as the daily tier runs, so a dead weekly or monthly tier
stays invisible — on one host the monthly tier was dead for five
months behind fresh dailies. Age out each tier against its own
cadence.

Resolve `BACKUPDIR` from the config rather than assuming a path
(`/var/lib/autopostgresqlbackup` is the Debian default;
`/var/backups/postgresql` is *not*). The config is
`/etc/autopostgresqlbackup.conf`, or `/etc/default/
autopostgresqlbackup` — note the script prefers the latter
"compat" file when it exists and then ignores the former.

```bash
CONF=/etc/default/autopostgresqlbackup
[ -f "$CONF" ] || CONF=/etc/autopostgresqlbackup.conf
DEFAULTDIR=/var/lib/autopostgresqlbackup
BACKUPDIR=$(. "$CONF" 2>/dev/null && echo "${BACKUPDIR:-$DEFAULTDIR}")

# Newest dump in EACH tier, with its age in days
for tier in daily weekly monthly; do
  newest=$(find "$BACKUPDIR/$tier" -type f -name '*.sql*' \
    -printf '%T@ %TY-%Tm-%Td %p\n' 2>/dev/null \
    | sort -rn | head -1)
  echo "$tier: ${newest:-NONE}"
done
```

- **WARN** if the newest `daily/` dump is older than 25 hours;
  **CRITICAL** past 48 hours or if the tier is empty.
- **WARN** if the newest `weekly/` dump is older than 8 days;
  **CRITICAL** past 15 days.
- **WARN** if the newest `monthly/` dump is older than 32 days;
  **CRITICAL** past 62 days.
- A tier that exists but whose newest file predates a distro
  major upgrade is the classic signature of this bug — check
  `/var/log/apt/history.log*` for the tool being upgraded around
  that date.

**Known trap — `DOMONTHLY`/`DOWEEKLY` zero-padding.**
autopostgresqlbackup 2.x picks the period with a *string*
compare, `[ "${DNOM}" = "${DOMONTHLY}" ]`, where
`DNOM=$(date '+%d')` is **zero-padded**. So `DOMONTHLY=1` never
matches `01` and monthly backups silently never run; only
`DOMONTHLY="01"` works. Values 10-31 match by accident, and the
weekly gate is unaffected because `date '+%u'` is unpadded. It
fails silently: no error, no mail under
`REPORT_ERRORS_ONLY="yes"`, and daily/weekly keep working. The
Debian 12→13 upgrade (autopostgresqlbackup 1.1 → 2.5) is a
common trigger, because 1.x tolerated the unpadded value. When
this check runs on a v2.x host, read the effective config and
flag any `DOMONTHLY`/`DOWEEKLY` in 1-9 that is not zero-padded,
whether or not the tier looks current.

## Cross-Backup (rsync)

Triggered when `memory.md` mentions cross-backup or rsync backups.

Check the age of the most recent backup pull by looking at the
timestamp of the latest file or log entry. The specific path
depends on the server's backup configuration — check `memory.md`
for details.

- **WARN** if latest pull is older than 25 hours
- **CRITICAL** if older than 48 hours

## Docker

Triggered when `memory.md` mentions Docker.

```bash
docker ps --format \
  "table {{.Names}}\t{{.Status}}\t{{.Ports}}" \
  2>/dev/null
```

- **WARN** for any container not in "Up" state
- Report container names and status

## nginx

Triggered when `memory.md` mentions nginx.

```bash
nginx -t 2>&1
systemctl is-active nginx
```

- **WARN** if config test fails
- **CRITICAL** if nginx is not running

## Ollama

Triggered when `memory.md` mentions Ollama.

```bash
curl -s -o /dev/null -w "%{http_code}" \
  http://localhost:11434/api/tags
```

- **WARN** if API does not respond with 200

## node_exporter

Triggered when `memory.md` mentions node_exporter or Prometheus.

```bash
curl -s -o /dev/null -w "%{http_code}" \
  http://localhost:9100/metrics
```

- **WARN** if metrics endpoint does not respond with 200

## NVIDIA GPU

Triggered when `memory.md` mentions NVIDIA or GPU.

```bash
nvidia-smi \
  --query-gpu=temperature.gpu,utilization.gpu,\
utilization.memory,memory.used,memory.total \
  --format=csv,noheader,nounits 2>/dev/null
```

- **WARN** if GPU temperature > 85°C
- **CRITICAL** if GPU temperature > 95°C
- Report temperature, GPU utilization, memory usage

## MariaDB / MySQL

Triggered when `memory.md` mentions MariaDB or MySQL.

```bash
mysqladmin status 2>/dev/null \
  || mariadb-admin status 2>/dev/null
```

- **CRITICAL** if the database is not responding
- Report uptime and thread count

## WireGuard

Triggered when `memory.md` mentions WireGuard.

```bash
wg show 2>/dev/null
```

Check each peer's latest handshake timestamp.

- **WARN** if any peer's last handshake was > 5 minutes ago (may
  indicate connectivity issues)
- Report interface names and peer handshake ages
