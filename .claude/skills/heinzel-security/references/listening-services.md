# Listening Services — Linux and macOS

Audit all listening TCP/UDP ports and flag services that should
not be exposed to all interfaces.

## Linux

```bash
ss -tulnp 2>/dev/null
```

Root is needed for the `-p` flag (process names). If running
unprivileged, omit `-p`:

```bash
ss -tuln
```

## macOS

```bash
lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null
```

On macOS, `lsof` works for the current user's processes without
root. With `sudo`, it shows all.

## Evaluation

Present results as a table of listening addresses, ports, and
process names (when available).

Flag as **WARN** if any of these well-known database or cache
ports listen on `0.0.0.0` or `::` (all interfaces) instead of
`127.0.0.1` or `::1`:

- 3306 (MySQL/MariaDB)
- 5432 (PostgreSQL)
- 6379 (Redis)
- 27017 (MongoDB)
- 11211 (Memcached)

These services should almost always be bound to localhost only.
If the server's `memory.md` shows a legitimate reason for
external binding (e.g. replication), note it as OK with context.

All other listening services: report them for review, no
automatic severity.
