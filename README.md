# Heinzel — AI-Powered Linux Server Administration

Tell Heinzel what you want, and it SSHes into your
server and does it for you — with built-in safety
guardrails.

Heinzel turns
[Claude Code](https://claude.ai/code) into a
cautious, methodical sysadmin that backs up before
editing, dry-runs before installing, and asks before
doing anything destructive.

> 3 years ago you searched StackOverflow and
> copy-pasted commands. A year ago you asked ChatGPT
> and copy-pasted commands. Today you just describe
> what you need.

2 min. demo screencast on YouTube:

[![Demo screencast](https://img.youtube.com/vi/ve_TFyJy_uU/hqdefault.jpg)](https://www.youtube.com/watch?v=ve_TFyJy_uU)

## How It Works

1. **Install
   [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
   and clone the repo**
   ```
   git clone https://github.com/wintermeyer/heinzel.git
   cd heinzel
   claude
   ```
2. **Describe what you need in plain English**
   ```
   ❯ Install and configure nginx on web1.example.com
   ```
3. **Review and approve each command before it runs**
   Claude proposes every SSH command, explains what
   it does and why, and waits for your approval.
   Nothing runs without your say-so.

## Examples

### Auto-detection on first connection

On the first connection to any server, Claude detects
the OS, gathers hardware info, and remembers
everything for future sessions:

```
 ❯ What OS is installed on app.example.com?
```

```
 ❯ Install a firewall on app.example.com and
   configure it to allow SSH and HTTPS traffic.
```

### Server memory across sessions

After working on a server, Claude remembers it. Next
week you launch Claude Code again and type:

```
 ❯ Check on web1.example.com.
```

Claude reads
`memory/servers/web1.example.com/memory.md`, already
knows it's Debian 12 with nginx and PostgreSQL,
checks the local changelog, and picks up right where
it left off.

### More things you can ask

```
 ❯ Set up a Let's Encrypt certificate for shop.example.com using certbot.
 ❯ Show me disk usage on db.example.com — it's running low on space.
 ❯ Install and configure PostgreSQL 15 on db2.example.com.
 ❯ Harden the firewall on staging.example.com — only allow SSH, HTTP, and HTTPS.
 ❯ Figure out why cron jobs aren't running on worker.example.com.
 ❯ Check if all servers (web1, web2, db1) need a reboot after the last kernel update.
```

## Safety & Guardrails

Heinzel's safety rules are not optional — they're
baked into every session. Claude follows them
consistently, even when a human might skip steps
under pressure.

- **Asks before acting** — destructive commands,
  firewall changes, reboots, and network restarts
  all require your explicit approval.
- **Backs up config files** — copies to
  `/var/backups/heinzel/` before editing
  (auto-cleaned after 30 days).
- **Dry-runs first** — runs dry-run commands before
  actual package operations when the package manager
  supports it.
- **Auto-detects the OS** — reads `/etc/os-release`
  and applies the right commands for the distro.
  No guessing.
- **Logs everything** — all changes are recorded in
  the system journal (`journalctl -t heinzel`) and
  mirrored locally in
  `memory/servers/<hostname>/changelog.log`.
- **Remembers servers** — stores OS, services, and
  notes in `memory/servers/` for future sessions.
- **Stable repos only** — no third-party sources
  without your explicit approval.
- **Least privilege** — uses a normal user when
  possible, `sudo` only when necessary, root only
  as a last resort.

## Accessing Logs

Heinzel logs every action to the system journal on each
server. To query the log:

```bash
# All entries
journalctl -t heinzel

# Filter by date
journalctl -t heinzel --since "2026-02-01"

# Last 20 entries
journalctl -t heinzel -n 20
```

On Alpine Linux (which uses syslog instead of systemd):

```bash
grep heinzel /var/log/messages
```

## Supported Distributions

| Family | Distributions | Rule file |
|--------|--------------|-----------|
| Debian | Debian, Ubuntu | `rules/debian.md` |
| RHEL | RHEL, CentOS, Fedora, Rocky, Alma | `rules/rhel.md` |
| Alpine | Alpine Linux | `rules/alpine.md` |
| SUSE | openSUSE, SLES | `rules/suse.md` |

Other distributions work too — Claude will apply
general Linux best practices and let you know which
distro it detected.

## Getting Started

### Prerequisites

- SSH key-based access to your target servers (no
  password/passphrase prompts). This can be as root,
  as a normal user, or as a normal user with sudo
  privileges.
- Linux on the target servers (any distribution).

### Setup

1. Clone this repo into your working directory.
2. Open Claude Code in that directory.
3. Tell Claude your problem, e.g. *"Find out if
   there is a webserver running on
   shop.example.com"*

Claude will auto-detect the OS on first connection
and remember it for future sessions.

## Risks & Responsibilities

> [!CAUTION]
> Heinzel operates on live servers via SSH — as root
> or with sudo. Always review every command before
> approving it.

This is a tool for **experienced Linux sysadmins**.

The risks are real — an LLM can hallucinate,
misunderstand your intent, or produce a command with
unintended side effects. A single bad command as root
can be unrecoverable! 😱

But consider: human sysadmins make mistakes too —
especially when tired, rushed, or managing dozens of
servers at 2 AM during an outage. They forget
backups, skip dry-runs, and apply firewall rules that
lock themselves out. Every experienced sysadmin has a
horror story.

Claude doesn't get tired or flustered. It **always**
backs up before editing, **always** dry-runs first,
and **always** checks the OS before assuming which
commands to use. It follows the safety checklist every
single time — not just when it remembers to.

The question isn't whether heinzel is risk-free — it
isn't. The question is whether a disciplined AI that
follows every safety rule every time, with a human
reviewing every command, produces fewer disasters than
a human working alone under real-world conditions.

Stay in the driver's seat. Review every command. Do
not blindly approve.

## Project Structure

```
CLAUDE.md              — Main instructions for Claude Code
rules/
  debian.md            — Debian & Ubuntu rules
  rhel.md              — RHEL, CentOS, Fedora, Rocky, Alma rules
  alpine.md            — Alpine Linux rules
  suse.md              — openSUSE & SLES rules
  mise.md              — Language runtime manager (mise)
memory/
  MEMORY.md            — Index for server memory
  servers/<hostname>/
    memory.md          — Server state snapshot (gitignored)
    changelog.log      — Local change history (gitignored)
```

## Why the Name Heinzel?

The name comes from the
[Heinzelmannchen](https://en.wikipedia.org/wiki/Heinzelm%C3%A4nnchen)
— the helpful gnomes of Cologne from German folklore.
Every night, while the people of Cologne slept, the
Heinzelmannchen crept out and did all the work: baking
bread, building houses, finishing whatever was left
undone. An invisible helper that quietly takes care of
things — a fitting name for a server administration
tool that handles the tedious work while you review
and approve.

## Professional Support

Need help setting this up for your infrastructure, or
want a team to manage your servers with AI-assisted
tooling?

**[Wintermeyer Consulting](https://wintermeyer-consulting.de)**
offers consulting and hands-on support for heinzel
deployments — from initial setup to ongoing server
management.

Contact the project founder Stefan Wintermeyer and
his team: **sw@wintermeyer-consulting.de**

## Contributing

Bug reports, feature requests, and pull requests are
very welcome! If you have ideas for better guardrails,
new distro support, or improvements to the safety
rules — please open an issue or submit a PR.

## License

MIT
