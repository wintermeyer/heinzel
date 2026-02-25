# claude-sysadmin

A `CLAUDE.md` configuration for using
[Claude Code](https://claude.ai/code) as a remote sysadmin for
Debian Linux servers.

Imagine telling your terminal *"SSH into web1.example.com and
upgrade the system"* — and it just does it. It checks the Debian
version, runs a dry-run first, backs up configs before touching
them, performs the upgrade, and gives you a summary when it's
done. That's what this project enables.

Instead of typing commands one by one, you describe what you want
in plain English. Claude Code connects to your server via SSH,
figures out the right commands, and executes them — while you
review and approve each step. It's like pair-programming with a
sysadmin who never forgets to make a backup.

## Warning

> [!CAUTION]
> This concept gives an AI agent access to your servers via
> SSH. This is inherently dangerous!

- Claude can operate as **root** or use **sudo** — a single
  mistake can take down a server, wipe data, or lock you out
  permanently.
- You are trusting an LLM to make decisions on **live production
  systems**. LLMs can hallucinate, misunderstand context, or
  produce commands with unintended side effects.
- A bad firewall rule or network change can **cut off SSH
  access**, leaving you with no remote way back in.
- There is **no undo** for many sysadmin operations. Deleted
  files, overwritten configs, and broken boot loaders don't come
  with a rollback button.

**This is for experienced Linux sysadmins only.** You should be
able to recognize a dangerous command before approving it. If you
aren't comfortable administering Debian servers from the command
line yourself, do not use this!!!

Always review every command Claude proposes before allowing
execution. The guardrails in `CLAUDE.md` reduce risk but do not
eliminate it.

## What This Is

A set of guardrails and conventions for letting Claude Code SSH
into your Debian servers as root to perform administration
tasks — upgrades, debugging, config changes, etc.

The `CLAUDE.md` file defines safety rules, backup procedures,
and a changelog format so that Claude operates carefully on live
systems.

## Examples

Here are some things you can ask Claude to do:

- *"SSH into web1.example.com and do a full system upgrade."*
- *"Check why nginx is returning 502 on app.example.com."*
- *"Set up a Let's Encrypt certificate for shop.example.com
  using certbot."*
- *"Show me disk usage on db.example.com — it's running low
  on space."*
- *"Install and configure PostgreSQL 15 on db2.example.com."*
- *"Check the logs on mail.example.com — outgoing mail seems
  stuck."*
- *"Harden the firewall on staging.example.com — only allow
  SSH, HTTP, and HTTPS."*
- *"Add a new vhost for blog.example.com to the nginx config
  on web1.example.com."*
- *"Figure out why cron jobs aren't running on
  worker.example.com."*
- *"Check if all servers (web1, web2, db1) need a reboot after
  the last kernel update."*

## Usage

1. Clone this repo (or copy `CLAUDE.md`) into your working
   directory.
2. Open Claude Code in that directory.
3. Tell Claude the hostname of your server, e.g. *"SSH into
   example.com and upgrade the system."*

## Prerequisites

- SSH key-based access to your target servers (no
  password/passphrase prompts). This can be as root, as a
  normal user, or as a normal user with sudo privileges.
- Debian Linux on the target servers.

## What It Does

- **Safety first** — asks before destructive commands, firewall
  changes, reboots, and network restarts.
- **Backups** — copies config files to
  `/var/tmp/claude-sysadmin-backup/` before editing
  (auto-cleaned after 30 days).
- **Changelog** — logs all changes to
  `/var/log/claude-sysadmin.log` on each server.
- **Dry-runs** — runs `apt-get --dry-run` before actual package
  operations.
- **Stable Debian repos only** — no third-party sources without
  explicit approval.

## Contributing

Bug reports, feature requests, and pull requests are very
welcome! If you have ideas for better guardrails, new use cases,
or improvements to the safety rules — please open an issue or
submit a PR.

## License

MIT
