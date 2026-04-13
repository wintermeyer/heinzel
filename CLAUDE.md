# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code)
when working with code in this repository.

## Project

heinzel — Administration of Linux servers, FreeBSD
servers, and macOS machines via SSH or locally.
Supports any Linux distribution (Debian, Ubuntu,
RHEL, CentOS, Fedora, SUSE, and others), FreeBSD,
and macOS.

## How It Works

The user provides a server hostname and optionally a
user. SSH key-based auth is used (no
password/passphrase needed). All work on remote
machines happens over SSH.

### Local mode

When the target is `localhost`, the user's own
hostname, or otherwise clearly the local machine,
heinzel operates in **local mode**:

- **No SSH.** Commands run directly in the shell.
- **No user prompt.** Use the current OS user.
- **Sudo still applies.** Probe `sudo -n true` as
  usual. If sudo is unavailable, enter unprivileged
  mode (no root SSH fallback).
- Skip all remote-only steps: blacklist/read-only
  checks, DNS alias detection, SSH user lookup,
  root SSH fallback.

### Remote mode (SSH)

- **Default:** `ssh root@hostname` — only when root
  privileges are actually needed.
- **Normal user:** `ssh user@hostname` — when the
  user specifies a non-root account or when root is
  not required.
- **sudo:** When logged in as a normal user, use
  `sudo` for commands that require elevated
  privileges.
- **Unprivileged mode:** When neither `sudo` nor
  root SSH is available, do everything possible as
  the current user and produce a sysadmin report.

**Always use the least amount of privileges needed.**

**SSH as root is not a risky action that requires
confirmation.** The privilege principle applies to
*commands*, not to the SSH login itself.

### SSH Options

Always use these options on every SSH and
SCP/rsync-over-SSH command:

    ssh -o BatchMode=yes -o ConnectTimeout=5 …

## Access Control (Blacklist & Read-Only)

Read `rules/access-control.md` for full details.
Check blacklist first, then read-only list, on every
remote connection before any other work.

## Critical Safety Rules

- **Never fabricate server facts.** Do not guess or
  make up hosting providers, data centers, hardware
  specs, network topology, or any other detail you
  have not directly observed or been told. If you
  don't know, say so.
- **You are working on live production servers.**
- **Always detect the OS first** before doing any
  work.
- **Ask before:** reboots, firewall changes, network
  service restarts, any destructive command.
- **Absolute taboos (never run without explicit user
  request):** any command that modifies the partition
  table. Read-only partition inspection (e.g.
  `lsblk`, `fdisk -l`, `gpart show`,
  `diskutil list`) is always allowed. Never modify
  `/etc/ssh/sshd_config`. Never delete or overwrite
  SSH keys. Never halt or power off a server.
- **Firewall & network:** Be extremely careful — a
  mistake cuts off SSH access. Discuss with the user
  first.
- **Never remove or block SSH port 22.** If the user
  asks, explain the risk and refuse. Offer
  alternatives (e.g. restricting to specific IPs).
- **Verify the default incoming policy is
  deny/drop.** See `rules/<family>.md`.
- **Use the appropriate non-interactive package
  manager** for the detected OS (`apt-get`,
  `dnf`, `yum`, `zypper`, `pkg`, `brew` — never
  with `sudo` on macOS).
- **Prefer stable/official repos only.**
- **Stick to stable release tracks.**
- **Test before applying.** Use dry-run/test modes
  when available.

## Verify Before Running

Do not trust your training data for command syntax.
Before running any command on a server, verify it:

1. **Check `--help` first.** Run `command --help`
   or `command -h` to confirm flags and syntax
   exist on this specific version.
2. **Read the man page** when `--help` is
   insufficient — especially for complex tools
   like `iptables`, `firewall-cmd`, `certbot`.
3. **Search upstream docs** (official project docs,
   distro wiki) when behavior varies across
   versions or distros.
4. **Check the rule file** — use the exact syntax
   from the loaded `rules/<family>.md` file.

## Rule Overrides

Whenever you read a base rule file in `rules/`, also
check for overrides in this order (later wins):

1. **Base:** `rules/<name>.md`
2. **Global custom:** `rules/custom/<name>.md` (also
   read `rules/custom/all.md` once per session)
3. **Per-server:**
   `memory/servers/<hostname>/rules.md`

Custom files use heading prefixes:
`## Add:`, `## Replace:`, `## Remove:` followed by
the topic or section name. Sections without a prefix
are additions.

## Server Output and Anomaly Detection

Read `rules/anomaly-detection.md`.

## SSH User & Language

Read `rules/ssh-user.md`. Usernames and language
preference are stored in `memory/user.md` — read at
session start.

## Privilege Escalation

Read `rules/privilege-escalation.md`. Probe sudo
first, then root SSH fallback, then unprivileged
mode. Only probe when a privileged action is needed.

## OS Detection (mandatory first step)

Read `rules/os-detection.md`. Before doing any work
on a server, you **must** detect its OS and create a
server memory file.

## Activity Check

Read `rules/activity-check.md`. On every connection,
check the system journal for recent heinzel activity
and summarize it for the user.

## DNS Aliases

Read `rules/dns-aliases.md` for the full detection,
verification, and removal procedures.

## Expected Software

Every Linux server should have a firewall and
automatic security updates. See `rules/<family>.md`.
Flag if missing. On macOS, a disabled Application
Firewall is common and less critical — see
`rules/macos.md`.

## Housekeeping

Routine health inspections. Only when the user asks.

1. Read `rules/housekeeping.md` (baseline checks).
2. Read `memory/housekeeping.md` (custom checks) if
   it exists.
3. Read server `memory.md` for service-specific
   checks.
4. Run all applicable checks.
5. Present report per `rules/housekeeping.md` format.
6. Update `memory.md` if facts changed.
7. Log summary to system journal and
   local `changelog.log`.

## Security Audit

Only when the user asks.

1. Read `rules/security.md`.
2. Read server `memory.md` for context.
3. Run all applicable checks.
4. Present report per `rules/security.md` format.
5. Log summary to system journal and
   local `changelog.log`.

## Programming Language Runtimes

Use [mise](https://mise.jdx.dev) — see
`rules/mise.md`. Do not install runtimes from
distro repos or use other version managers unless
the user requests it.

## Firewall Awareness for Service Changes

When installing, removing, or configuring a
network-facing service, always consider firewall
implications and raise them with the user.

1. Check if the service needs ports opened.
2. Check current firewall rules.
3. **Ask the user** before changing anything:
   open to all or restricted? Public or internal?
4. **Recommend a safe default** and explain why.
5. **Explain the risks** in plain language.

When removing a service, offer to close ports that
were only needed for it. Always use the distro's
firewall tool and log changes.

## Best Practices Review

Before executing user-requested actions that
install software, create services, change
permissions, or modify network exposure, check
for common anti-patterns. Read
`rules/best-practices.md`. Suggest improvements
but respect the user's final choice — never
refuse to proceed after an informed override.

## Port Conflict Check

Before starting or deploying any application that
listens on a network port, check whether the port
is already in use. Prefer Unix sockets over TCP
ports when the app is behind a reverse proxy. Read
`rules/port-check.md`. **Never start a service on
an occupied port without user approval.**

## CI/CD Deployment

Read `rules/deployment.md`. Never use root or
personal accounts for automated deployments. Create
a dedicated deploy user with minimal privileges.

## Backups

Read `rules/backups.md`. Back up every config file
before editing it.

## Copying Directories Between Servers

Read `rules/directory-copy.md`. Always check for
symlinks pointing outside the copied tree.

## Changelog

Read `rules/changelog.md`. Log every session to the
system journal and mirror to local changelog.

## Server Memory

Read `rules/server-memory.md`. Each server gets
`memory/servers/<hostname>/` with `memory.md`,
`changelog.log`, and optionally `todo.md`. Update
memory immediately after any system change.

## Team Usage

By default, server memory and changelogs are
gitignored (solo use). Edit `.gitignore` to share.

**Always personal:** `memory/user.md`,
`memory/blacklist.md`, `memory/readonly.md`, local
machine memory.

**Shared in team mode:** `memory/servers/*/`,
`memory/network.md`, `memory/housekeeping.md`.

**Custom rules** (`rules/custom/`) are gitignored
by default. Comment out the gitignore entry to
share team-wide rule customizations. Per-server
rules follow the same sharing model as server
memory.

New team members: copy `memory/user.md.example`
to `memory/user.md`.

## Network Memory

Cross-server facts go in `memory/network.md`.
Created on first need. Current facts only.

## Session To-Do List

For multi-step sessions (2+ steps), create
`memory/servers/<hostname>/todo.md`. Mark tasks
`[x]` immediately on completion. On reconnection,
show pending items. Delete when all done.

## Software Release Versions

**MANDATORY: Always perform a live web search for
current release/version information before
recommending, installing, or upgrading any
software.** This applies to:

- OS releases (e.g. latest Debian stable, FreeBSD
  release, macOS version)
- Programming language runtimes (e.g. Node.js LTS,
  Ruby, Python)
- Any package or tool being installed or upgraded

Do NOT rely on your training data for version
numbers — it is often outdated. You MUST search the
web every time, even if you believe you know the
answer. Cite the source URL in your response.

If you do not have access to a web search tool,
**warn the user immediately** that you cannot verify
current versions and that any version numbers you
provide may be outdated. Do not silently fall back
to training data.

## Version Check

Read `rules/version-check.md`. Proactively check
for newer stable versions of installed software
during housekeeping and when touching specific
software. Nudge the user but never force upgrades.

## Conventions

- Manual administration only (no
  Ansible/Puppet/Chef).
- **Wrap all `.md` files at 80 characters.**
