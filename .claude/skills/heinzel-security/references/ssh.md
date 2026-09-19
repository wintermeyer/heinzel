# SSH — Password Authentication & Hardening

**Note:** Reading `sshd_config` is safe. The CLAUDE.md taboo is
about *modifying* `/etc/ssh/sshd_config`, not reading it.

## SSH Password Authentication — Linux

Check whether sshd allows password-based logins. Key-based
authentication should be required; password auth should be
disabled.

### Preferred method (needs root)

Use `sshd -T` to query the effective compiled configuration.
This resolves Include directives, Match blocks, and defaults —
much more reliable than parsing config files manually. Since
OpenSSH 10.4 it prints keywords in mixed case
(`PasswordAuthentication`), so always filter with `grep -i`.

```bash
sshd -T 2>/dev/null | grep -i passwordauthentication
```

- `passwordauthentication yes` → **WARN**
- `passwordauthentication no` → OK

### Fallback method (unprivileged)

If `sshd -T` is unavailable or requires root, read the config
files directly. They are usually world-readable.

```bash
# Main config
cat /etc/ssh/sshd_config 2>/dev/null

# Drop-in configs (OpenSSH 8.2+)
cat /etc/ssh/sshd_config.d/*.conf 2>/dev/null
```

Follow every `Include` line, not just `sshd_config.d/` (macOS
also includes `/etc/ssh/crypto.conf`); the FreeBSD
`openssh-portable` port keeps its files in `/usr/local/etc/ssh`.
Parse the files for `PasswordAuthentication`. The first
obtained value wins (`sshd_config(5)`), so a drop-in included
at the top overrides the main file; `sshd -T` is authoritative.

**Important:** On OpenSSH 8.8+, some distros default
`PasswordAuthentication` to `no` via drop-in files in
`/etc/ssh/sshd_config.d/`. Always check the effective value —
do not assume the compiled default.

- If the effective value is `yes` → **WARN**
- If the effective value is `no` → OK
- If the files are unreadable → note in the report that the
  check could not be performed

## SSH Password Authentication — macOS

### Check if Remote Login is enabled

```bash
systemsetup -getremotelogin 2>/dev/null
```

Or check via launchctl:

```bash
sudo launchctl list com.openssh.sshd 2>/dev/null
```

- If Remote Login is **off** → **INFO** "Remote Login (SSH) is
  disabled — SSH checks skipped." Stop here, no further SSH
  checks needed.
- If Remote Login is **on** → proceed with the same `sshd -T`
  / config file approach as Linux.

macOS sshd config is at `/etc/ssh/sshd_config` (same path as
Linux).

## SSH Hardening — Linux and macOS

These checks extend the SSH Password Authentication sections
above. Use the same preferred/fallback pattern: `sshd -T` when
available, config file parsing as fallback.

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

- `yes` or `prohibit-password` → **INFO** (root SSH is normal in
  heinzel — this is informational only)
- `no` → OK

### Weak SSH Algorithms

```bash
sshd -T 2>/dev/null \
  | grep -iE "^(ciphers|macs|kexalgorithms) "
```

Fallback: parse `Ciphers`, `MACs`, and `KexAlgorithms` from
config files.

Flag any of these as **WARN**:

- **Ciphers:** `3des-cbc`, `arcfour`, `arcfour128`, `arcfour256`,
  `blowfish-cbc`, `cast128-cbc`
- **MACs:** `hmac-md5`, `hmac-md5-96`, `hmac-sha1-96`,
  `umac-64@openssh.com`
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
