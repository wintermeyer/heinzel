# Unprivileged Mode

When running in unprivileged mode (no sudo, no root SSH), use the
config file fallback for SSH checks. For firewall checks, attempt
the command — some firewall status commands work without root.

Many checks in this audit work without root:

- **Works unprivileged:** SSH config file parsing, multiple UID 0
  accounts, system accounts with login shells, listening services
  (without process names on Linux), all sysctl checks,
  world-writable system files, SUID/SGID audit, mount options,
  unowned files, fail2ban status (systemctl), macOS checks (SIP,
  FileVault, Gatekeeper).
- **Needs root:** `sshd -T`, empty password accounts
  (`/etc/shadow`), listening services with process names on Linux
  (`ss -tulnp`), cron directory permissions (some dirs may be
  unreadable).

Accounts and sudo (`references/accounts-sudo.md`): the account
source, the local accounts and the SSH user's own sudo rules
(`sudo -n -l`) work unprivileged; the sudoers files, other
users' rules (`sudo -l -U`), `sssctl` and other accounts'
`.ssh` need root.

If a check cannot be performed due to missing privileges, do not
skip it silently. Add it to the report:

```
### Skipped (needs root)

- SSH effective config (sshd -T requires root)
- Firewall status (ufw requires root)
- Empty password accounts (/etc/shadow unreadable)
- Listening services process names (ss -p needs root)
```

If config files are world-readable, use the fallback and note
that the result is from config file parsing, not the effective
compiled config.
