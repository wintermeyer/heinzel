# claude-sysadmin

A `CLAUDE.md` configuration for using
[Claude Code](https://claude.ai/code) as a remote sysadmin for
Linux servers.

Imagine telling your terminal *"SSH into web1.example.com and
upgrade the system"* — and it just does it. It detects the OS,
runs a dry-run first, backs up configs before touching them,
performs the upgrade, and gives you a summary when it's done.
That's what this project enables.

Instead of typing commands one by one, you describe what you want
in plain English. Claude Code connects to your server via SSH,
figures out the right commands for the server's OS, and executes
them — while you review and approve each step. It's like
pair-programming with a sysadmin who never forgets to make a
backup.

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
aren't comfortable administering Linux servers from the command
line yourself, do not use this!!!

Always review every command Claude proposes before allowing
execution. The guardrails in `CLAUDE.md` reduce risk but do not
eliminate it.

## On Risk: The Full-Self-Driving Argument

Yes, this tool can break your servers. An LLM with root access
to production systems is a genuinely dangerous idea — there's no
sugarcoating that. But consider an analogy.

Tesla's Full-Self-Driving can kill people. It has. And yet over
time, the data shows that it prevents more accidents than it
causes. The calculus isn't "is it perfect?" — it's "is it better
than the alternative?" Human drivers are tired, distracted,
overconfident. They run red lights. They text at the wheel. FSD
doesn't do any of that. It's not flawless, but it's consistent.

Server administration has a similar problem. Human sysadmins
make mistakes too — especially when they're tired, rushed, or
managing dozens of servers at 2 AM during an outage. They forget
to make backups before editing configs. They run `rm -rf` in the
wrong directory. They apply firewall rules that lock themselves
out. They skip the dry-run because they're in a hurry. Every
experienced sysadmin has a horror story.

Claude doesn't get tired. It doesn't get flustered during an
outage. It **always** makes a backup before editing a config. It
**always** runs the dry-run first. It **always** checks the OS
version before assuming which commands to use. It follows the
safety checklist every single time, not just when it remembers
to.

The risks are real:

- An LLM can hallucinate a command that doesn't do what it
  thinks.
- It can misunderstand your intent and take the wrong action.
- A single bad command as root can be unrecoverable.

But the mitigations are also real:

- **You approve every command** before it runs. Claude proposes,
  you decide.
- **Guardrails are baked in** — backup procedures, dry-runs,
  least-privilege, changelog logging. A human might skip these
  under pressure. Claude won't.
- **It explains what it's doing and why**, so even less
  experienced admins can learn and catch mistakes.
- **It reads the docs** before running commands it's not sure
  about, which is more than most of us do at 2 AM.

The question isn't whether claude-sysadmin is risk-free — it
isn't. The question is whether a disciplined AI that follows
every safety rule every time, with a human reviewing every
command, produces fewer disasters than a human working alone
under real-world conditions.

I (Stefan Wintermeyer) think the answer is yes — over time, 
and with the right guardrails. But like FSD, it requires you 
to stay in the driver's seat. Keep your hands on the wheel. 
Review every command. Do not blindly approve!

## What This Is

A set of guardrails and conventions for letting Claude Code SSH
into your Linux servers to perform administration tasks —
upgrades, debugging, config changes, etc.

The `CLAUDE.md` file defines safety rules, backup procedures,
and a changelog format so that Claude operates carefully on live
systems. Distro-specific rules in `rules/` tell Claude the right
commands for each OS family.

## Supported Distributions

| Family | Distributions | Rule file |
|--------|--------------|-----------|
| Debian | Debian, Ubuntu | `rules/debian.md` |
| RHEL | RHEL, CentOS, Fedora, Rocky, Alma | `rules/rhel.md` |
| Alpine | Alpine Linux | `rules/alpine.md` |
| SUSE | openSUSE, SLES | `rules/suse.md` |

Other distributions work too — Claude will apply general Linux
best practices and let you know which distro it detected.

## Examples

### Auto-detection on first connection

**You:** *"SSH into web1.example.com and upgrade the system."*

Claude detects the OS first:

```
$ ssh root@web1.example.com cat /etc/os-release
PRETTY_NAME="Debian GNU/Linux 12 (bookworm)"
ID=debian
VERSION_ID="12"
...
```

**Claude:** *"web1.example.com is running Debian 12 (Bookworm).
I'll use apt-get for package management. Running dry-run
first..."*

```
$ ssh root@web1.example.com apt-get update
[...]
$ ssh root@web1.example.com apt-get --dry-run upgrade
12 upgraded, 0 newly installed, 0 to remove.
```

**Claude:** *"12 packages to upgrade including a kernel update.
This will need a reboot afterwards. Proceed?"*

### Works across distros

**You:** *"SSH into app.example.com and install nginx."*

If it's RHEL:
```
$ ssh root@app.example.com dnf install -y nginx
```

If it's Alpine:
```
$ ssh root@app.example.com apk add nginx
```

Claude picks the right command automatically based on the
detected OS.

### Server memory across sessions

After working on a server, Claude remembers it for next time:

**You (next week):** *"Check on web1.example.com."*

Claude reads `memory/servers/web1.example.com.md`, already
knows it's Debian 12 with nginx and PostgreSQL, and picks up
right where it left off.

### More things you can ask

- *"Set up a Let's Encrypt certificate for shop.example.com
  using certbot."*
- *"Show me disk usage on db.example.com — it's running low
  on space."*
- *"Install and configure PostgreSQL 15 on
  db2.example.com."*
- *"Harden the firewall on staging.example.com — only allow
  SSH, HTTP, and HTTPS."*
- *"Figure out why cron jobs aren't running on
  worker.example.com."*
- *"Check if all servers (web1, web2, db1) need a reboot
  after the last kernel update."*

## Usage

1. Clone this repo into your working directory.
2. Open Claude Code in that directory.
3. Tell Claude the hostname of your server, e.g. *"SSH into
   example.com and upgrade the system."*

Claude will auto-detect the OS on first connection and
remember it for future sessions.

## Prerequisites

- SSH key-based access to your target servers (no
  password/passphrase prompts). This can be as root, as a
  normal user, or as a normal user with sudo privileges.
- Linux on the target servers (any distribution).

## What It Does

- **Auto-detects the OS** — reads `/etc/os-release` and applies
  the right commands for the distro.
- **Remembers servers** — stores OS, services, and notes in
  `memory/servers/` for future sessions.
- **Safety first** — asks before destructive commands, firewall
  changes, reboots, and network restarts.
- **Backups** — copies config files to
  `/var/tmp/claude-sysadmin-backup/` before editing
  (auto-cleaned after 30 days).
- **Changelog** — logs all changes to
  `/var/log/claude-sysadmin.log` on each server.
- **Dry-runs** — runs dry-run commands before actual package
  operations when the package manager supports it.
- **Stable repos only** — no third-party sources without
  explicit approval.

## Project Structure

```
CLAUDE.md              — Main instructions for Claude Code
rules/
  debian.md            — Debian & Ubuntu rules
  rhel.md              — RHEL, CentOS, Fedora, Rocky, Alma rules
  alpine.md            — Alpine Linux rules
  suse.md              — openSUSE & SLES rules
memory/
  MEMORY.md            — Index for server memory
  servers/             — Per-server memory files (gitignored)
```

## Professional Support

Need help setting this up for your infrastructure, or want a
team to manage your servers with AI-assisted tooling?

**[Wintermeyer Consulting](https://wintermeyer-consulting.de)**
offers consulting and hands-on support for claude-sysadmin
deployments — from initial setup to ongoing server management.

Contact the project founder Stefan Wintermeyer and his team:
**sw@wintermeyer-consulting.de**

## Contributing

Bug reports, feature requests, and pull requests are very
welcome! If you have ideas for better guardrails, new distro
support, or improvements to the safety rules — please open an
issue or submit a PR.

## License

MIT
