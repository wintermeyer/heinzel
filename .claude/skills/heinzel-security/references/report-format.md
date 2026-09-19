# Security Audit Report Format

Use this exact structure for every security audit report.

```
## Security Audit: hostname

Date: YYYY-MM-DD HH:MM
OS: Debian 12 (Bookworm)

### Issues

WARN      SSH allows password authentication
INFO      macOS Application Firewall disabled

### Checks

SSH password auth   WARN — PasswordAuthentication yes
SSH weak algos      OK — no weak algorithms found
SSH root login      INFO — PermitRootLogin yes
SSH host cert       OK — CA SHA256:Cxr4…, valid 23 more days,
                    renewed by step-ssh-renew.timer
SSH user CA         INFO — 1 CA, no RevokedKeys; root via
                    principal "ops"
Firewall            OK — ufw active, default deny
Empty passwords     OK — no accounts with empty password
UID 0 accounts      OK — only root
Listening services  OK — no databases on 0.0.0.0
ASLR                OK — randomize_va_space = 2
IP forwarding       OK — disabled
File permissions    OK — no world-writable system files
SUID/SGID binaries  INFO — 14 found (all expected)
fail2ban            INFO — not running
```

## Rules

- **Issues section** only appears if problems exist. Sort by
  severity: CRITICAL first, then WARN, then INFO.
- **One line per item.** Keep it scannable.
- Severity levels:
  - `CRITICAL` — needs immediate attention
  - `WARN` — should be addressed soon
  - `INFO` — informational, not urgent
