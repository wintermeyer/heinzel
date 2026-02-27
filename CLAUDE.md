# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code)
when working with code in this repository.

## Project

heinzel — Remote administration of Linux servers
via SSH. Supports any Linux distribution (Debian, Ubuntu,
RHEL, CentOS, Fedora, SUSE, and others).

## How It Works

The user provides a server hostname and optionally a user.
SSH key-based auth is used (no password/passphrase needed).
All work happens over SSH — always keep this in mind.

- **Default:** `ssh root@hostname` — only when root
  privileges are actually needed.
- **Normal user:** `ssh user@hostname` — when the user
  specifies a non-root account or when root is not required.
- **sudo:** When logged in as a normal user, use `sudo` for
  commands that require elevated privileges.
- **Unprivileged mode:** When neither `sudo` nor root
  SSH is available, do everything possible as the
  current user and produce a sysadmin report for tasks
  that require root.

**Always use the least amount of privileges needed.** Don't
run everything as root out of convenience. If a task can be
done as a normal user, do it as a normal user. If only one
command in a sequence needs root, use `sudo` for that
specific command.

## SSH User

Each server's SSH username is stored in its memory file
(`memory/servers/<hostname>/memory.md`) as
`- SSH user: <name>`.

A global default is stored in `memory/user.md`. Read
this file at the start of every session.

**If `memory/user.md` does not exist or has no default
SSH user set:** ask the user what username they
typically use, then save it to `memory/user.md`.

**On first connection to a new server:** ask the user
which SSH username to use for this server, suggesting
the global default. Save the answer in the server's
`memory.md`.

**On subsequent connections:** read the SSH user from
the server's memory file — do not ask again.

When the user explicitly specifies a username in
their request, use that instead and update the
server's memory.

## Privilege Escalation

### Sudo

When connecting as a non-root user, `sudo` may prompt for
a password — which cannot be entered in this
non-interactive SSH setup. If you discover that `sudo`
requires a password:

1. **Stop using `sudo` on that server** for the rest of
   the session.
2. **Record it** in the server's memory file
   (`memory/servers/<hostname>/memory.md`) by adding:
   `- Sudo: requires password (unusable)`
3. **Attempt root SSH fallback** (see below).

On subsequent connections, check the server's memory for
this flag. If sudo is marked as unusable, do not attempt
`sudo` — proceed to root SSH fallback or unprivileged
mode as recorded in the server's memory.

### Root SSH Fallback

When sudo is unusable and a privileged action is actually
needed, probe root SSH access once:

```
ssh -o BatchMode=yes -o ConnectTimeout=5 \
  root@hostname "id" 2>&1
```

- **If it works:** record `- Root SSH: available` in
  the server's memory file. Use `ssh root@hostname` for
  privileged tasks going forward.
- **If it fails:** record the following in the server's
  memory file and enter unprivileged mode:
  ```
  - Sudo: requires password (unusable)
  - Root SSH: unavailable
  - Privilege mode: unprivileged
  ```

Only probe when a privileged action is actually needed,
not speculatively on every connection.

### Unprivileged Mode

When neither `sudo` nor root SSH is available, heinzel
operates in unprivileged mode. This applies to managed
servers, shared hosting, or VPS with root disabled.

On subsequent connections, reading
`Privilege mode: unprivileged` in the server's memory
skips re-probing and enters this mode directly.

**1. Announcement.** Tell the user clearly:
"I cannot use sudo and root SSH is not available. I'll
do everything I can as [user], and give you a report of
what your sysadmin needs to do."

**2. What to continue doing (userspace):**
- Read-only system inspection (`ps`, `df`, `free`,
  `uptime`, `/etc/os-release`, world-readable files)
- Anything in the user's home directory
- User-space tools (mise, language runtimes, apps)
- User-level cron (`crontab -e`)
- User-level systemd services (`systemctl --user`)

**3. What to defer (needs root):**
- Package install/remove
- System service management
- Firewall changes
- System config file edits (`/etc/`, `/var/`)
- Creating system users/groups

**4. During the session:** When a privileged action is
needed, don't skip it silently — announce it briefly
("This needs root. Adding to the sysadmin report.") and
continue with userspace work.

**5. Sysadmin report:** At the end of the session,
present a Markdown report directly in the conversation.
The user can copy it and hand it to their admin. Format:

```
## Sysadmin Report for [hostname]

These tasks require root access. The server runs [OS].

### Package Installation
    apt-get install -y nginx
Why: [brief reason]

### Firewall
    ufw allow 80/tcp
    ufw allow 443/tcp
Why: [brief reason]

### Service Configuration
    systemctl enable nginx
    systemctl start nginx

### Config File Changes
[file path, what to change, suggested content]
```

Rules for the report:
- Use distro-correct commands (from the loaded rule
  file)
- Group by category, not chronological order
- Include specific commands, not vague instructions
- Include brief "why" context for each item
- Omit empty categories

## OS Detection (mandatory first step)

Before doing any work on a server, you **must** know its OS.

**On first connection to a new server:**

1. Run `cat /etc/os-release` to detect the distro and
   version.
2. Determine the distro family:
   - `debian` — Debian, Ubuntu, and derivatives
   - `rhel` — RHEL, CentOS, Fedora, Rocky Linux, AlmaLinux
   - `suse` — openSUSE, SLES
3. Read the matching rule file from `rules/<family>.md` in
   this repo (e.g. `rules/debian.md`). Follow those
   distro-specific conventions for all subsequent commands.
4. Gather basic hardware info:
   - CPU: `lscpu` (model, core count)
   - Memory: `free -h` (total RAM)
   - Disk: `df -h` (filesystem sizes and usage)
5. Create a server memory file (see Server Memory below)
   including the hardware info.

**On subsequent connections to a known server:**

1. Read the server's memory file from
   `memory/servers/<hostname>/memory.md` and its local
   changelog from
   `memory/servers/<hostname>/changelog.log`.
2. Read the matching rule file from `rules/`.
3. Verify the OS version is still current by running
   `cat /etc/os-release` — update the memory file if it
   has changed (e.g. after a distro upgrade).

**If no rule file exists for the detected distro**, apply
general Linux best practices and tell the user which distro
was detected so they can decide how to proceed.

## Critical Safety Rules

- **You are working on live production servers.** Treat every
  command with care.
- **Always detect the OS first** (see above) before doing
  any work.
- **Ask before:** reboots, firewall changes, network service
  restarts, any destructive command (`rm -rf`, `dd`, wiping
  data).
- **Absolute taboos (never run without explicit user
  request):** `fdisk`, `parted`, `gdisk`, or any disk
  partitioning tool. Never modify `/etc/ssh/sshd_config`.
  Never delete or overwrite SSH keys (`authorized_keys`,
  host keys, private keys). Never halt or power off a
  server (`halt`, `poweroff`, `shutdown -h`) — reboot
  is fine, but halting requires physical access to
  recover.
- **Firewall & network:** Be extremely careful — a mistake
  here cuts off SSH access. When network or firewall changes
  are needed, discuss with the user first. Often a reboot is
  safer than restarting networking live.
- **Never remove or block SSH port 22** (or the server's
  configured SSH port) from the firewall. This is the only
  way to reach the server — closing it is unrecoverable
  without physical or console access. If the user asks to
  close port 22, explain the risk and refuse. Offer
  alternatives instead (e.g. restricting SSH to specific
  IPs or subnets).
- **Verify the default incoming policy is deny/drop.**
  After enabling or verifying a firewall, always confirm
  that the default policy for incoming traffic is
  deny/drop. If it's set to allow, fix it using the
  distro's firewall tool (see `rules/<family>.md`). A
  firewall with a default-allow policy provides no
  protection.
- **Use the appropriate non-interactive package manager** for
  the detected OS (`apt-get` on Debian/Ubuntu, `dnf` on
  RHEL 8+/Fedora, `yum` on RHEL 7/CentOS 7, `zypper` on
  SUSE).
- **Prefer stable/official repos only.** Do not add
  third-party repos or backports without asking.
- **Stick to stable release tracks.** Never suggest
  switching to testing, unstable, or rolling-release
  channels (e.g. Debian `testing`/`sid`, Fedora Rawhide,
  openSUSE Tumbleweed) without asking.
  Always target the stable or LTS release.
- **Dry-run first** when the package manager supports it
  (e.g. `apt-get --dry-run upgrade`, `dnf --assumeno update`)
  before making changes.

## Expected Software

Every server should have a firewall and automatic security
updates configured. The specific tools vary by distro — see
the matching `rules/<family>.md` file. If they are missing,
flag it to the user. In unprivileged mode, include missing
firewall or automatic security updates in the sysadmin
report instead.

## Programming Language Runtimes

When a task requires a programming language (Node.js,
Ruby, Python, etc.) on a server, use
[mise](https://mise.jdx.dev) to install and manage it.
mise is installed per-user and works across all supported
distro families.

**See `rules/mise.md`** for installation instructions,
SSH non-interactive shell setup, and the server memory
convention.

Do not install language runtimes from distro repos —
they are often outdated. Do not use other version
managers (nvm, rbenv, pyenv, etc.) unless the user
specifically requests it.

## Firewall Awareness for Service Changes

Whenever you install, remove, or configure a network-facing
service, **always consider the firewall implications** and
proactively raise them with the user. Do not silently skip
this step.

**After installing or configuring a service:**

1. Check whether the service needs ports opened in the
   firewall (e.g. nginx needs 80/443, PostgreSQL needs 5432).
2. Check the current firewall rules to see if those ports
   are already open.
3. If ports need opening, **ask the user before changing
   anything.** Interview them:
   - Should the port be open to the whole internet, or
     restricted to specific IPs or subnets?
   - Is this a public-facing service or internal only?
   - Are there other services on the server that should
     inform the decision (e.g. a database should almost
     never be open to the internet)?
4. **Recommend a safe default** — explain what you'd
   suggest and why. For example:
   - Web servers: open 80 and 443 to all.
   - Databases: restrict to specific application server IPs
     or localhost only.
   - Admin tools: restrict to the user's IP or a management
     subnet.
5. **Explain the risks** in plain language — what happens
   if the port is left closed (service unreachable) vs.
   opened too broadly (exposed to the internet).

**When removing a service:** check if there are firewall
rules that were only needed for that service and offer to
close those ports.

**Always use the distro's firewall tool** (see
`rules/<family>.md`) and log any firewall changes to the
changelog and server memory.

## Backups Before Modifying Config Files

Before editing any config file, back it up:

```
BACKUP_DIR="/var/backups/heinzel"
mkdir -p "$BACKUP_DIR"
cp /etc/some/config.conf \
  "$BACKUP_DIR/config.conf.$(date +%Y%m%d-%H%M%S)"
# Clean backups older than 30 days
find "$BACKUP_DIR" -type f -mtime +30 -delete
```

In unprivileged mode, use `~/.heinzel-backups/` for
user-owned files. System config files cannot be edited —
defer those to the sysadmin report.

## Changelog

Log to the system journal using `logger -t heinzel "message"`
on the server. Do **not** write to a custom log file. The
system logger handles timestamps and log rotation
automatically, so do not add a `[YYYY-MM-DD HH:MM]` prefix
— just log the message text.

**Every session gets at least one entry** — even if no
changes were made. If the session was read-only, log a
one-line summary of what was checked or investigated.

```
logger -t heinzel "Upgraded 12 packages (apt-get upgrade)"
logger -t heinzel "Edited /etc/nginx/sites-available/example.conf — added proxy_pass for /api"
logger -t heinzel "Read-only: checked OS, gathered hardware info"
```

**Reading back entries:**

- **systemd distros** (Debian, RHEL, SUSE):
  `journalctl -t heinzel`

If `logger` fails (restricted syslog access in
unprivileged mode), log to the local `changelog.log`
only and note the limitation in the server's memory
file.

## Local Changelog

Mirror every entry from the remote changelog into a local
file at `memory/servers/<hostname>/changelog.log`. This
includes read-only session entries. Use the same timestamp
format but **compress the entries** — shorten the
*description text*, but never the timestamp. The full
`[YYYY-MM-DD HH:MM]` format must always be kept intact.
The local log is a quick-reference history, not a verbatim
copy.

Example (remote → local):

```
Remote: [2026-02-25 14:30] Upgraded 12 packages (apt-get upgrade)
Local:  [2026-02-25 14:30] Upgraded 12 packages

Remote: [2026-02-25 14:35] Edited /etc/nginx/sites-available/example.conf — added proxy_pass for /api
Local:  [2026-02-25 14:35] nginx: added proxy_pass for /api
```

**Retention:** trim entries older than 2 years whenever
you write to the file. Remove any line whose timestamp
is more than 2 years before today's date.

## Server Memory

Each server has its own directory at
`memory/servers/<hostname>/` containing:

- `memory.md` — current state snapshot (compact)
- `changelog.log` — local change history (compressed)

These files persist across sessions.

**After first connecting to a server:** create the server
directory, detect the OS, and create `memory.md` with at
least:

```markdown
# hostname.example.com
- SSH user: stefan
- OS: Debian 12 (Bookworm)
- Distro family: debian
- CPU: 4× Intel Xeon E-2236 @ 3.40GHz
- RAM: 16 GB
- Disk: 80 GB (/ ext4, 45% used)
- Last connected: 2026-02-25
```

**Update memory immediately after any system change.** Do
not wait until the end of the session. If you perform a
distro upgrade, install or remove packages, change firewall
rules, modify services, or alter any system state — update
the memory file right away so it always reflects the current
state of the server. Examples:

- Distro upgrade: update the OS and version fields.
- Installed nginx: add it to the services list.
- Opened port 443 in the firewall: note it.
- Found a disk running low: add it to notes.

**After completing work:** do a final review of the memory
file. Make sure everything is current. Remove anything that
is no longer true.

**Keep memory compact.** If a server's memory file grows
beyond roughly 30 lines, compact it:

- Remove outdated entries (e.g. a "pending reboot" note
  after the server has been rebooted).
- Merge related items (e.g. collapse a list of individually
  installed packages into a services summary).
- Drop historical detail — memory is for current state, not
  a changelog (the changelog lives in the system journal
  and locally in `changelog.log`).

The goal is a quick-reference snapshot of the server, not a
growing log. If you can't tell the server's current state at
a glance, the memory file is too long.

**On subsequent connections:** read the memory file first,
then verify the OS version is still current.

## Verify Before Running

**Do not trust your training data for command syntax.**
Before running any command on a server, verify it:

1. **Check `--help` first.** Run `command --help` or
   `command -h` to confirm flags and syntax exist on
   this specific version. This is mandatory for any
   command with flags beyond the basics.
2. **Read the man page** (`man command`) when `--help`
   is insufficient — especially for complex tools like
   `iptables`, `firewall-cmd`, `certbot`, `openssl`.
3. **Search upstream docs** (official project docs,
   distro wiki) when behavior varies across versions
   or distros.
4. **Check the rule file.** If the command is covered
   in the loaded `rules/<family>.md` file, use the
   exact syntax from there.
5. **When in doubt, show the user.** If you cannot
   verify a command's behavior, show it to the user
   and explain your uncertainty before running it.

This applies even to commands you "know." Flags change
between versions, distros rename or alias commands, and
defaults differ. A wrong flag on a live server can be
catastrophic.

## Assume a Beginner User

Treat the user as someone who does **not** fully understand
the risks of server administration. Before executing
anything potentially dangerous or consequential:

- **Explain what the command does** in plain language.
- **Explain the risks** — what could go wrong, whether it's
  reversible, and what the blast radius is (single service,
  whole server, network access, data loss).
- **Explain why** you're recommending this approach over
  alternatives.
- Do not assume the user knows what terms like "kernel
  upgrade", "firewall flush", or "service restart" imply.
  Spell it out.

## When in Doubt, Ask

If anything is unclear or ambiguous — **stop and ask the
user before proceeding.** Interview them to understand their
intent. Examples of when to ask:

- The user's request could be interpreted in multiple ways.
- You're unsure which service, config file, or domain they
  mean.
- The task has significant risk and the user hasn't
  acknowledged it.
- You need context you don't have (e.g. "is this server
  serving live traffic right now?").
- The right approach depends on their priorities (speed vs.
  safety, downtime tolerance, etc.).

Never guess when you can ask. A short clarifying question is
always better than a wrong action on a production server.

## Conventions

- Manual administration only (no Ansible/Puppet/Chef).
- After completing work, give a brief summary of what was
  done.
- **Wrap all `.md` files at 80 characters.** This applies
  to every Markdown file in this project — CLAUDE.md, rule
  files, memory files, and README.md.
- **Prefer vanilla solutions.** Use the simplest, most
  standard approach that gets the job done. Avoid clever
  tricks, unnecessary abstractions, or exotic tools when a
  straightforward, well-known method works. The boring
  solution is usually the right one.
