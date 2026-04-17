# Housekeeping Report Format

Use this exact structure for every housekeeping report.

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

## Rules

- **Issues section** only appears if problems exist. Sort by
  severity: CRITICAL first, then WARN, then INFO.
- **Services section** only appears if the server has services in
  its `memory.md` file.
- **One line per item.** Keep it scannable.
- Severity levels:
  - `CRITICAL` — needs immediate attention
  - `WARN` — should be addressed soon
  - `INFO` — informational, not urgent
