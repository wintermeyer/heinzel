# Security Audit — Configuration Checks

Security-focused checks for servers and macOS machines.
Run these checks when the user asks for a security
audit. Never run automatically — only on explicit
request.

## Report Format

Present results in this format:

```
## Security Audit: hostname

Date: YYYY-MM-DD HH:MM
OS: Debian 12 (Bookworm)

### Issues

WARN      SSH allows password authentication
INFO      macOS Application Firewall disabled

### Checks

SSH password auth   WARN — PasswordAuthentication yes
Firewall            OK — ufw active, default deny
```

**Rules:**

- **Issues section** only appears if problems exist.
  Sort by severity: CRITICAL first, then WARN, then
  INFO.
- **One line per item.** Keep it scannable.
- Severity levels:
  - `CRITICAL` — needs immediate attention
  - `WARN` — should be addressed soon
  - `INFO` — informational, not urgent

## SSH Password Authentication — Linux

Check whether sshd allows password-based logins.
Key-based authentication should be required; password
auth should be disabled.

**Note:** Reading sshd_config is safe. The CLAUDE.md
taboo is about *modifying* `/etc/ssh/sshd_config`,
not reading it.

### Preferred method (needs root)

Use `sshd -T` to query the effective compiled
configuration. This resolves Include directives,
Match blocks, and defaults — much more reliable than
parsing config files manually.

```bash
sshd -T 2>/dev/null | grep -i passwordauthentication
```

- `passwordauthentication yes` → **WARN**
- `passwordauthentication no` → OK

### Fallback method (unprivileged)

If `sshd -T` is unavailable or requires root, read
the config files directly. They are usually
world-readable.

```bash
# Main config
cat /etc/ssh/sshd_config 2>/dev/null

# Drop-in configs (OpenSSH 8.2+)
cat /etc/ssh/sshd_config.d/*.conf 2>/dev/null
```

Parse the files for `PasswordAuthentication`. The
last matching directive wins (drop-ins are read in
lexical order before the main file on most distros,
but `sshd -T` is authoritative).

**Important:** On OpenSSH 8.8+, some distros default
`PasswordAuthentication` to `no` via drop-in files
in `/etc/ssh/sshd_config.d/`. Always check the
effective value — do not assume the compiled default.

- If the effective value is `yes` → **WARN**
- If the effective value is `no` → OK
- If the files are unreadable → note in the report
  that the check could not be performed

## SSH Password Authentication — macOS

### Check if Remote Login is enabled

```bash
systemsetup -getremotelogin 2>/dev/null
```

Or check via launchctl:

```bash
sudo launchctl list com.openssh.sshd 2>/dev/null
```

- If Remote Login is **off** → **INFO** "Remote Login
  (SSH) is disabled — SSH checks skipped." Stop here,
  no further SSH checks needed.
- If Remote Login is **on** → proceed with the same
  `sshd -T` / config file approach as Linux.

macOS sshd config is at `/etc/ssh/sshd_config` (same
path as Linux).

## Firewall — Linux

Verify a firewall is installed, active, and the
default incoming policy is deny/drop.

### Debian/Ubuntu (ufw)

```bash
ufw status verbose
```

- Not installed or inactive → **WARN** "No active
  firewall"
- Active but default incoming is not `deny` →
  **WARN** "Firewall default incoming policy is not
  deny"
- Active and default deny → OK

### RHEL/Fedora/SUSE (firewalld)

```bash
firewall-cmd --state
firewall-cmd --get-default-zone
```

Then check the default zone's target:

```bash
firewall-cmd --zone=<zone> --get-target
```

- Not running → **WARN** "No active firewall"
- Zone target is `ACCEPT` → **WARN** "Default zone
  target is ACCEPT (allows all incoming)"
- Zone target is `default` (reject/drop) → OK

## Firewall — macOS

Check Application Firewall status:

```bash
/usr/libexec/ApplicationFirewall/socketfilterfw \
  --getglobalstate
```

- Disabled → **INFO** (not WARN — common on macOS
  behind NAT, consistent with housekeeping severity)
- Enabled → OK

## Unprivileged Mode

When running in unprivileged mode (no sudo, no root
SSH), use the config file fallback for SSH checks.
For firewall checks, attempt the command — some
firewall status commands work without root.

If a check cannot be performed due to missing
privileges, do not skip it silently. Add it to the
report:

```
### Skipped (needs root)

- SSH effective config (sshd -T requires root)
- Firewall status (ufw requires root)
```

If config files are world-readable, use the fallback
and note that the result is from config file parsing,
not the effective compiled config.

## After the Report

1. **Do NOT update memory.md.** These are config
   observations, not state changes. Memory tracks
   what is installed and running, not security
   posture details.
2. **Log to changelog** — a one-line summary:
   ```
   logger -t heinzel "Security audit: 1 WARN, \
   1 INFO"
   ```
3. **Mirror to local changelog.log** in compressed
   form.
