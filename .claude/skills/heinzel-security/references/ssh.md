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
much more reliable than parsing config files manually.

```bash
sshd -T 2>/dev/null | grep -i passwordauthentication
```

- `passwordauthentication yes` → **WARN**
- `passwordauthentication no` → OK

### Fallback method (unprivileged)

If `sshd -T` is unavailable or requires root, use the sshd
probe in `rules/ssh-config.md`: `sshd -G` gives the same
effective values without host keys, and every file read. Only
when that fails too, read the config files directly, following
their `Include` lines.

```bash
# Main config
cat /etc/ssh/sshd_config 2>/dev/null

# Drop-in configs (OpenSSH 8.2+)
cat /etc/ssh/sshd_config.d/*.conf 2>/dev/null
```

Filter `sshd -T`/`-G` output with `grep -i`
(`rules/ssh-config.md` → Output case).

Parse the files for `PasswordAuthentication`. The last matching
directive wins (drop-ins are read in lexical order before the
main file on most distros, but `sshd -T` is authoritative).

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

## SSH Certificates — Linux and macOS

Detection, probes and the reasoning live in
`rules/ssh-certificates.md`; run its "Host
certificate" and "User CA" probes (the latter needs
root; without it, the quick probe). Report host and
user certificates as **separate** lines. Skip both
lines with `none` when neither is configured.

Host certificate:

- Validity and key match: the severities in
  `rules/ssh-certificates.md` → Host certificate
- No renewal job, or one that does not reload sshd
  → **WARN**
- A name from server memory (FQDN, DNS alias)
  missing from the principals → **INFO**

User CA:

- `RevokedKeys` set but the file is missing or
  unreadable → **CRITICAL** (sshd refuses every
  public key login)
- CA signing key present on the host → **WARN**
  (report the path, never read the file)
- Same CA fingerprint signs host and user
  certificates → **WARN**
- `casignaturealgorithms` contains `ssh-rsa`
  (SHA-1) → **WARN**
- Principals that reach `root` → **INFO**, list
  them. With `Match` blocks, evaluate `root` via
  `sshd -T -C` (see the rule), not only the global
  values
- `AuthorizedPrincipalsCommand` in use → **INFO**,
  name command and user
- No `RevokedKeys` → **INFO**
- `cert-authority` lines in `authorized_keys` →
  **INFO**, list account and CA fingerprint

## SSH Client on the Server — Linux and macOS

For root and every account that connects out; probe in
`rules/ssh-config.md` → ssh (client). Applies with or without
an SSH CA:

- `stricthostkeychecking no`, or a known-hosts file of
  `/dev/null`, in the system client config → **WARN**
- `stricthostkeychecking accept-new` → **INFO**

With a host CA in the fleet (`rules/ssh-certificates.md` → SSH
client):

- The global known-hosts file has no `@cert-authority` line,
  or the lines sit only in some users' files → **INFO**
- `@cert-authority` for `*` → **INFO**
