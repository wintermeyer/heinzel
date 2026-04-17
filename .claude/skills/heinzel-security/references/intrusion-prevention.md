# Intrusion Prevention — Linux

## fail2ban Status

```bash
systemctl is-active fail2ban 2>/dev/null
```

- Not running / not installed → **INFO** (recommended but not
  critical, especially when SSH uses key-only authentication)
- Active → OK

If active, optionally show jail status:

```bash
fail2ban-client status 2>/dev/null
```
