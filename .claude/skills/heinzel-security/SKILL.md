---
name: heinzel-security
argument-hint: "[hostname]"
description: Run a heinzel security audit on a server — SSH
  hardening (password auth, weak algos, root login), firewall,
  user account hygiene, listening services, kernel hardening
  (ASLR, IP forwarding), file permissions, SUID/SGID audit,
  fail2ban. Use when the user asks for a "security audit",
  "security review", "hardening check", or to "audit security on
  <host>". Do NOT auto-invoke on generic phrases like "check
  server <host>". Covers Linux (Debian, Ubuntu, RHEL, CentOS,
  Fedora, SUSE) and macOS (SIP, FileVault, Gatekeeper).
---

# heinzel-security

Security configuration audit for a server or the local machine.
**Never run automatically** — only on explicit user request. The
whole of the heinzel first-connection onboarding pipeline still
applies before any of this runs.

## Workflow

1. **Load overrides.** Before running any check, apply the full
   heinzel rule-override chain (later wins):
   - `memory/custom-rules/heinzel-security.md` if present (global
     custom overrides for this skill — `## Add:`, `## Replace:`,
     `## Remove:` prefixes per `CLAUDE.md`).
   - `memory/servers/<hostname>/memory.md` for context (services,
     legitimate external bindings, VPN role).
   - `memory/servers/<hostname>/rules.md` if present (per-server
     rule overrides — same prefixes as above, highest precedence).
   Note: `memory/custom-rules/all.md` is already loaded by the
   CLAUDE.md session-start preflight — do not re-read it.
2. **Run checks in 2–3 parallel batches** for speed — not one
   massive batch. If a single parallel tool call errors, Claude
   Code cancels sibling calls, so grouping limits blast radius.
   Put commands with complex quoting (awk, sed) in their own batch
   so a quoting mistake does not cancel simple commands.
3. **SSH quoting warning:** avoid awk's `!~` operator — zsh
   interprets `!` as history expansion and mangles it even inside
   quotes. Use positive `~` match with `next` instead (see System
   Accounts check in `references/user-accounts.md`).
4. **Select checks** per the references below. Use the preferred
   method when privileges allow; fall back to the unprivileged
   method otherwise.
5. **Emit the report** using the format in
   `references/report-format.md`.
6. **Do NOT update `memory.md`.** These are config observations,
   not state changes. Memory tracks what is installed and running,
   not security posture details.
7. **Log the summary** to the system journal and mirror to the
   local changelog per `rules/changelog.md`:

       logger -t heinzel "Security audit: 1 WARN, 1 INFO"

## Cross-references

**Automatic security updates** are checked during housekeeping
(see `heinzel-housekeeping` skill). This audit does not duplicate
that check.

## References

Read on demand, only when the relevant section applies:

- `references/report-format.md` — required output format and
  severity rules (CRITICAL / WARN / INFO).
- `references/ssh.md` — SSH password auth, root login, weak
  algorithms, MaxAuthTries, X11Forwarding (Linux and macOS).
- `references/firewall.md` — Linux (ufw / firewalld) and macOS
  (Application Firewall).
- `references/user-accounts.md` — empty passwords, multiple UID
  0, system accounts with login shells.
- `references/listening-services.md` — audit `ss` / `lsof`
  output, flag databases on 0.0.0.0.
- `references/kernel-os.md` — sysctl checks: ASLR, IP forwarding,
  ICMP redirects, SUID core dumps.
- `references/file-permissions.md` — world-writable system files,
  SUID/SGID audit, /tmp mount options, cron perms, unowned files.
- `references/intrusion-prevention.md` — fail2ban status.
- `references/macos-security.md` — SIP, FileVault, Gatekeeper.
- `references/unprivileged.md` — which checks work without root,
  which need it, and how to report skipped ones.
