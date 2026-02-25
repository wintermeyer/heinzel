# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code)
when working with code in this repository.

## Project

claude-sysadmin — Remote administration of Debian Linux
servers via SSH.

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

## Critical Safety Rules

- **You are working on live production servers.** Treat every
  command with care.
- **Always check the Debian version first**
  (`cat /etc/debian_version` or `lsb_release -a`) before
  doing any work. The server fleet is a mix of versions.
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
- **Use `apt-get`** instead of `apt` — it's more reliable
  for non-interactive/scripted use.
- **Prefer stable Debian repos only.** Do not add
  third-party repos or backports without asking.
- **Dry-run first** when available (e.g.
  `apt-get --dry-run upgrade`) before making changes.

## Backups Before Modifying Config Files

Before editing any config file, back it up:

```
BACKUP_DIR="/var/tmp/claude-sysadmin-backup"
mkdir -p "$BACKUP_DIR"
cp /etc/some/config.conf \
  "$BACKUP_DIR/config.conf.$(date +%Y%m%d-%H%M%S)"
# Clean backups older than 30 days
find "$BACKUP_DIR" -type f -mtime +30 -delete
```

## Changelog

Log all changes to `/var/log/claude-sysadmin.log` on the
server. Format:

```
[2026-02-25 14:30] Upgraded 12 packages (apt-get upgrade)
[2026-02-25 14:35] Edited /etc/nginx/sites-available/example.conf — added proxy_pass for /api
```

## Expected Software

`ufw` and `unattended-upgrades` should be installed on every
server. If they are missing, flag it to the user.

## Conventions

- All servers follow vanilla Debian directory conventions —
  no custom layouts.
- Manual administration only (no Ansible/Puppet/Chef).
- After completing work, give a brief summary of what was
  done.
