# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code)
when working with code in this repository.

## Project

heinzel — Remote administration of Linux servers
via SSH. Supports any Linux distribution (Debian, Ubuntu,
RHEL, CentOS, Fedora, Alpine, SUSE, Arch, and others).

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

**Always use the least amount of privileges needed.** Don't
run everything as root out of convenience. If a task can be
done as a normal user, do it as a normal user. If only one
command in a sequence needs root, use `sudo` for that
specific command.

## Default SSH User

The user's preferred non-root SSH username is stored in
`memory/user.md`. Read this file at the start of every
session.

**If `memory/user.md` does not exist or has no default SSH
user set:** ask the user what username they typically use
for non-root SSH access on their servers, then save it to
`memory/user.md`.

When the user does not explicitly specify a username and
the task does not require root, use this default username
with `sudo` for privileged commands.

## OS Detection (mandatory first step)

Before doing any work on a server, you **must** know its OS.

**On first connection to a new server:**

1. Run `cat /etc/os-release` to detect the distro and
   version.
2. Determine the distro family:
   - `debian` — Debian, Ubuntu, and derivatives
   - `rhel` — RHEL, CentOS, Fedora, Rocky Linux, AlmaLinux
   - `alpine` — Alpine Linux
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
- **Firewall & network:** Be extremely careful — a mistake
  here cuts off SSH access. When network or firewall changes
  are needed, discuss with the user first. Often a reboot is
  safer than restarting networking live.
- **Use the appropriate non-interactive package manager** for
  the detected OS (`apt-get` on Debian/Ubuntu, `dnf` on
  RHEL 8+/Fedora, `yum` on RHEL 7/CentOS 7, `zypper` on
  SUSE, `apk` on Alpine, `pacman` on Arch).
- **Prefer stable/official repos only.** Do not add
  third-party repos or backports without asking.
- **Stick to stable release tracks.** Never suggest
  switching to testing, unstable, or rolling-release
  channels (e.g. Debian `testing`/`sid`, Alpine `edge`,
  Fedora Rawhide, openSUSE Tumbleweed) without asking.
  Always target the stable or LTS release.
- **Dry-run first** when the package manager supports it
  (e.g. `apt-get --dry-run upgrade`, `dnf --assumeno update`)
  before making changes.

## Expected Software

Every server should have a firewall and automatic security
updates configured. The specific tools vary by distro — see
the matching `rules/<family>.md` file. If they are missing,
flag it to the user.

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
BACKUP_DIR="/var/tmp/heinzel-backup"
mkdir -p "$BACKUP_DIR"
cp /etc/some/config.conf \
  "$BACKUP_DIR/config.conf.$(date +%Y%m%d-%H%M%S)"
# Clean backups older than 30 days
find "$BACKUP_DIR" -type f -mtime +30 -delete
```

## Changelog

Log to `/var/log/heinzel.log` on the server.
**Every session gets at least one entry** — even if no
changes were made. If the session was read-only, log a
one-line summary of what was checked or investigated.

Format:

```
[2026-02-25 14:30] Upgraded 12 packages (apt-get upgrade)
[2026-02-25 14:35] Edited /etc/nginx/sites-available/example.conf — added proxy_pass for /api
[2026-02-25 15:00] Read-only: checked OS, gathered hardware info
```

## Local Changelog

Mirror every entry from the remote changelog into a local
file at `memory/servers/<hostname>/changelog.log`. This
includes read-only session entries. Use the same timestamp
format but **compress the entries** — keep them shorter
than the remote log. The local log is a quick-reference
history, not a verbatim copy.

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
  a changelog (the changelog lives on the server at
  `/var/log/heinzel.log` and locally in
  `changelog.log`).

The goal is a quick-reference snapshot of the server, not a
growing log. If you can't tell the server's current state at
a glance, the memory file is too long.

**On subsequent connections:** read the memory file first,
then verify the OS version is still current.

## Read the Docs

Before using any tool, service, or command you are not fully
certain about, **search for and read its official
documentation first** — man pages, upstream docs, distro
wiki, etc. Do not rely on memory alone. Verify syntax,
flags, and behavior for the specific version installed on
the server. Getting a flag wrong on a live server can be
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
