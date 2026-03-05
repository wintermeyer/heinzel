# Security Audit — Configuration Checks

Security-focused checks for servers and macOS machines.
Run these checks when the user asks for a security
audit. Never run automatically — only on explicit
request.

## Running Checks

**Parallel execution:** run checks in parallel for
speed, but be aware that if one parallel tool call
errors, Claude Code cancels all sibling calls. To
limit blast radius, group checks into 2–3 batches
rather than one massive batch. Put commands with
complex quoting (awk, sed) in their own batch so a
quoting mistake does not cancel simple commands.

**SSH quoting:** avoid awk's `!~` operator — zsh
interprets `!` as history expansion and mangles it
even inside quotes. Use positive `~` match with
`next` instead (see System Accounts check below).

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
SSH weak algos      OK — no weak algorithms found
SSH root login      INFO — PermitRootLogin yes
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

## SSH Hardening — Linux and macOS

These checks extend the SSH Password Authentication
sections above. Use the same preferred/fallback
pattern: `sshd -T` when available, config file parsing
as fallback.

### PermitRootLogin

```bash
sshd -T 2>/dev/null | grep -i permitrootlogin
```

Fallback:

```bash
grep -i "^PermitRootLogin" \
  /etc/ssh/sshd_config \
  /etc/ssh/sshd_config.d/*.conf 2>/dev/null
```

- `yes` or `prohibit-password` → **INFO** (root SSH
  is normal in heinzel — this is informational only)
- `no` → OK

### Weak SSH Algorithms

```bash
sshd -T 2>/dev/null \
  | grep -E "^(ciphers|macs|kexalgorithms) "
```

Fallback: parse `Ciphers`, `MACs`, and
`KexAlgorithms` from config files.

Flag any of these as **WARN**:

- **Ciphers:** `3des-cbc`, `arcfour`, `arcfour128`,
  `arcfour256`, `blowfish-cbc`, `cast128-cbc`
- **MACs:** `hmac-md5`, `hmac-md5-96`,
  `hmac-sha1-96`, `umac-64@openssh.com`
- **KEX:** `diffie-hellman-group1-sha1`,
  `diffie-hellman-group-exchange-sha1`
- **Host key types:** `ssh-dss`

Report each weak algorithm found with its category.

### MaxAuthTries

```bash
sshd -T 2>/dev/null | grep -i maxauthtries
```

Fallback: parse from config files. Default is 6.

- Value > 4 → **INFO**
- Value ≤ 4 → OK

### X11Forwarding — Linux only

```bash
sshd -T 2>/dev/null | grep -i x11forwarding
```

Fallback: parse from config files.

- `yes` → **INFO**
- `no` → OK

Skip this check on macOS.

## User Account Hygiene — Linux

### Empty Password Accounts

Check for accounts with empty password fields in
`/etc/shadow`. Requires root.

```bash
awk -F: '($2 == "") {print $1}' /etc/shadow
```

- Any account found → **CRITICAL** per account
- No accounts → OK

**Unprivileged fallback:** this check cannot be
performed without root. Add to "Skipped" section.

### Multiple UID 0 Accounts

```bash
awk -F: '($3 == 0) {print $1}' /etc/passwd
```

No root needed — `/etc/passwd` is world-readable.

- Only `root` has UID 0 → OK
- Any other account with UID 0 → **CRITICAL**

### System Accounts with Login Shells

Check for system accounts (UID < 1000) that have
interactive login shells.

```bash
awk -F: '($3 < 1000) && \
  ($7 ~ /(nologin|false|sync|shutdown|halt)$/) \
  {next} ($3 < 1000) {print $1 ":" $7}' \
  /etc/passwd
```

**Note:** The `!~` (not-match) operator in awk does
not survive SSH + zsh quoting layers — zsh interprets
`!` as history expansion and mangles it. The command
above uses positive `~` match with `next` (skip) to
achieve the same result.

No root needed.

Expected exceptions: `root` (has `/bin/bash` or
`/bin/sh`). Flag all others.

- Any unexpected system account with a login shell →
  **WARN** per account
- Only expected exceptions → OK

## Listening Services — Linux and macOS

Audit all listening TCP/UDP ports and flag services
that should not be exposed to all interfaces.

### Linux

```bash
ss -tulnp 2>/dev/null
```

Root is needed for the `-p` flag (process names). If
running unprivileged, omit `-p`:

```bash
ss -tuln
```

### macOS

```bash
lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null
```

On macOS, `lsof` works for the current user's
processes without root. With `sudo`, it shows all.

### Evaluation

Present results as a table of listening addresses,
ports, and process names (when available).

Flag as **WARN** if any of these well-known database
or cache ports listen on `0.0.0.0` or `::` (all
interfaces) instead of `127.0.0.1` or `::1`:

- 3306 (MySQL/MariaDB)
- 5432 (PostgreSQL)
- 6379 (Redis)
- 27017 (MongoDB)
- 11211 (Memcached)

These services should almost always be bound to
localhost only. If the server's memory.md shows a
legitimate reason for external binding (e.g.
replication), note it as OK with context.

All other listening services: report them for review,
no automatic severity.

## Kernel / OS Security — Linux

These checks read sysctl values. No root needed.

### ASLR (Address Space Layout Randomization)

```bash
sysctl -n kernel.randomize_va_space
```

- `0` → **CRITICAL** (ASLR disabled)
- `1` → **WARN** (partial — should be 2)
- `2` → OK (full randomization)

### IP Forwarding

```bash
sysctl -n net.ipv4.ip_forward
```

On macOS:

```bash
sysctl -n net.inet.ip.forwarding
```

- `1` → **WARN** unless the server's memory.md
  mentions WireGuard, VPN, or router functionality.
  In that case → OK with note.
- `0` → OK

### ICMP Redirect Acceptance — Linux only

```bash
sysctl -n net.ipv4.conf.all.accept_redirects
```

- `1` → **WARN**
- `0` → OK

### SUID Core Dumps — Linux only

```bash
sysctl -n fs.suid_dumpable
```

- `1` → **WARN** (allows core dumps from SUID
  programs, potential information leak)
- `0` or `2` → OK (`2` is "suidsafe" — restricted)

## File Permissions — Linux

### World-Writable System Files

```bash
find /etc /usr /bin /sbin -xdev -type f \
  -perm -0002 2>/dev/null
```

No root needed (finds files based on permissions of
world-readable directories).

- Any file found → **WARN** per file
- None found → OK

### SUID/SGID Binary Audit

```bash
find / -xdev -type f \
  \( -perm -4000 -o -perm -2000 \) 2>/dev/null
```

No root needed. Report the total count.

**Known-good SUID/SGID binaries** (do not flag):
`sudo`, `su`, `passwd`, `chsh`, `chfn`, `newgrp`,
`gpasswd`, `mount`, `umount`, `ping`, `ping6`,
`fusermount`, `fusermount3`, `pkexec`,
`unix_chkpwd`, `crontab`, `ssh-agent`, `at`,
`expiry`, `wall`, `write`, `dotlockfile`,
`mount.nfs`, `mount.cifs`, `staprun`.

Any binary not in this list → **INFO** with full
path. The user can assess whether it belongs.

### /tmp and /dev/shm Mount Options — Linux only

```bash
mount | grep -E '(/tmp |/dev/shm )'
```

Or use `findmnt`:

```bash
findmnt -n -o OPTIONS /tmp 2>/dev/null
findmnt -n -o OPTIONS /dev/shm 2>/dev/null
```

- `/dev/shm` lacks `noexec` → **WARN**
- `/tmp` lacks `noexec` → **INFO**
- `/tmp` is not a separate mount → **INFO** (note
  that it shares the root filesystem)

### Cron Directory Permissions

```bash
stat -c '%a %U %G %n' \
  /etc/crontab \
  /etc/cron.d \
  /etc/cron.daily \
  /etc/cron.hourly \
  /etc/cron.weekly \
  /etc/cron.monthly 2>/dev/null
```

- Any of these world-writable (xx7 or xx6 with
  group=other) → **CRITICAL**
- World-readable but not writable → **INFO**
- Owner root, no world access → OK

### Unowned Files

```bash
find /etc /usr /var -xdev \
  \( -nouser -o -nogroup \) 2>/dev/null
```

Limit to these key directories to avoid excessive
scan time on large filesystems.

- Any unowned file found → **INFO** per file
- None found → OK

## Intrusion Prevention — Linux

### fail2ban Status

```bash
systemctl is-active fail2ban 2>/dev/null
```

- Not running / not installed → **INFO** (recommended
  but not critical, especially when SSH uses key-only
  authentication)
- Active → OK

If active, optionally show jail status:

```bash
fail2ban-client status 2>/dev/null
```

## macOS Security

### SIP (System Integrity Protection)

```bash
csrutil status
```

- Disabled → **CRITICAL**
- Enabled → OK

### FileVault (Full Disk Encryption)

```bash
fdesetup status
```

- Off → **WARN**
- On → OK

### Gatekeeper

```bash
spctl --status 2>&1
```

- `assessments disabled` → **WARN**
- `assessments enabled` → OK

## Cross-References

**Automatic security updates** are checked during
housekeeping — see `rules/housekeeping.md`. This
audit does not duplicate that check.

## Unprivileged Mode

When running in unprivileged mode (no sudo, no root
SSH), use the config file fallback for SSH checks.
For firewall checks, attempt the command — some
firewall status commands work without root.

Many checks in this audit work without root:

- **Works unprivileged:** SSH config file parsing,
  multiple UID 0 accounts, system accounts with
  login shells, listening services (without process
  names on Linux), all sysctl checks,
  world-writable system files, SUID/SGID audit,
  mount options, unowned files, fail2ban status
  (systemctl), macOS checks (SIP, FileVault,
  Gatekeeper).
- **Needs root:** `sshd -T`, empty password accounts
  (`/etc/shadow`), listening services with process
  names on Linux (`ss -tulnp`), cron directory
  permissions (some dirs may be unreadable).

If a check cannot be performed due to missing
privileges, do not skip it silently. Add it to the
report:

```
### Skipped (needs root)

- SSH effective config (sshd -T requires root)
- Firewall status (ufw requires root)
- Empty password accounts (/etc/shadow unreadable)
- Listening services process names (ss -p needs root)
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
