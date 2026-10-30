# Server Memory

Each server: `memory/servers/<hostname>/` with
`memory.md`, `changelog.log`, optionally `todo.md`,
optionally `rules.md` (per-server rule
overrides — see CLAUDE.md → Rule Overrides), and
optionally one `user-<login>.md` per SSH login
(see Per-login memory).

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
add `Mode: local` for localhost). Add
`- SSH port: <port>` only for a port other than 22
(`rules/ssh-port.md`).

**Update memory immediately after any system
change.** Keep it compact (~30 lines max). Remove
outdated entries, merge related items.

**Update `Last connected:` on every connection.**

## Per-login memory

One host, several logins: `root` and `alice` on the
same server see a different home, shell, sudo
rights, runtimes, crontab and groups. Facts that
hold for one login only go in
`memory/servers/<hostname>/user-<login>.md`, never
in `memory.md`:

```markdown
# alice@hostname.example.com
- Home: /home/alice (zsh)
- Groups: alice, docker
- Sudo: no sudoers entry (unusable)
- mise: node 24.11.0, erlang 28.1 (~/.local/share/mise)
- Crontab: nightly export at 03:10
- Apps: ~/demo (compose project, .env present)
- Last connected: 2026-10-30
```

- **What goes where:** host facts (OS, hardware,
  services, firewall, system packages) in
  `memory.md`; what changes with the login in the
  user file. When in doubt: would `root` see it
  the same way? Then it is a host fact.
- **Create on need:** on the first fact that is
  specific to a login, not on every first login.
  A host worked on only as `root` usually has no
  user file at all.
- **Read** `memory.md` plus the file of the login
  this session uses. Read another login's file only
  when the work concerns that account.
- **Same limits:** compact, current facts only, no
  credential values. Update `Last connected:` of
  the user file when it exists.
- **Flat, with the `user-` prefix**, never a
  `users/` subdirectory: tools that pick memory
  files by name (Heinzel Pro's import) would read
  `users/backups.md` as the custom rule `backups`.
- Local mode has one login; its facts stay in
  `memory.md`.

Memory files never hold credential values — see
`rules/secrets.md`.

Edit memory files with the agent's file-edit tool,
never through `sed -i` or an interpreter
(`python3 -`, `perl -e`). Memory often names key
paths and `/etc/ssh/sshd_config`. The taboo guard
blocks a command line that carries them: it cannot
tell a note about a path from a write to it.
