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
PostgreSQL backups.

```bash
# Find the most recent backup file
ls -lt /var/backups/postgresql/ 2>/dev/null \
  | head -5
```

- **WARN** if latest backup is older than 25 hours
- **CRITICAL** if no backup found or older than 48 hours

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
