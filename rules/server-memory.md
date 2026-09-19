# Server Memory

Each server: `memory/servers/<hostname>/` with
`memory.md`, `changelog.log`, optionally `todo.md`,
and optionally `rules.md` (per-server rule
overrides — see CLAUDE.md → Rule Overrides).

**On first connection:** create directory and
`memory.md` with at least:

```markdown
# hostname.example.com
- IP: 203.0.113.10
- OS: Debian 12 (Bookworm)
- Distro family: debian
- CPU: 4x Intel Xeon E-2236 @ 3.40GHz
- RAM: 16 GB
- Disk: 80 GB (/ ext4, 45% used)
- Last connected: 2026-02-25
```

Adapt fields to OS (add Arch, Homebrew for macOS;
add `Mode: local` for localhost).

SSH certificates: `SSH host cert:` and
`SSH user CA:` lines, format in
`rules/ssh-certificates.md` → Memory.

**Update memory immediately after any system
change.** Keep it compact (~30 lines max). Remove
outdated entries, merge related items.

**Update `Last connected:` on every connection.**

Memory files never hold credential values — see
`rules/secrets.md`.
