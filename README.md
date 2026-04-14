# Heinzel — System Administration with Safety Guardrails

Heinzel is a set of rules that turns an AI coding
assistant into a cautious, methodical sysadmin. It
works with
[Claude Code](https://docs.anthropic.com/en/docs/claude-code),
[OpenCode](https://opencode.ai), or any other
terminal-based AI tool that can read project files
and run shell commands. It supports Linux, FreeBSD,
and macOS — remote servers over SSH and the local
machine alike.

Describe what you need in plain English, and Heinzel
figures out the right commands for your OS, proposes
each one with an explanation, and waits for your
approval before running anything. It backs up configs,
tests commands before real execution, remembers every
server it has worked on, and gives you a detailed
report when it's finished.

Using it feels like pair-programming with a colleague
who always checks the docs first and never skips a
step because he's in a hurry. The bigger the network,
the more it pays off — Heinzel remembers every server's
OS, services, and quirks so you don't have to. Not
sure yet? Ask Heinzel to plan first before making
changes — no changes until you say go.

## Screencast: Debug and fix some webserver problems

![Screencast: Debug and fix some webserver problems](assets/webshop-bugfix-example.gif)

### Other Screencasts on YouTube

- [Debug and fix a misconfigured nginx and firewall on a remote server](https://www.youtube.com/watch?v=_uenftahbJI) (1 min)
- [Install the latest stable Ruby and Ruby on Rails](https://www.youtube.com/watch?v=QVvm29eABKY) (1 min)
- [Install a firewall, upgrade the Linux distribution and setup automatic daily security updates](https://www.youtube.com/watch?v=ve_TFyJy_uU) (2 min)

## How to Install

### Prerequisites

- **An AI coding assistant** that runs in the
  terminal — e.g.
  [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
  or [OpenCode](https://opencode.ai).
- **SSH access** to the target server — either as a
  normal user or as root. The SSH connection must
  not prompt for a password or passphrase (use
  key-based authentication without a passphrase).
  This is not needed for local administration
  (localhost / your own machine).

  Quick setup: generate a key with `ssh-keygen`,
  copy it to the server with `ssh-copy-id user@host`,
  and test with `ssh user@host`. See the
  [Arch wiki SSH keys guide](https://wiki.archlinux.org/title/SSH_keys)
  for details.

- Linux (any distribution), FreeBSD, or macOS on the
  target machines. All supported systems can also be
  managed locally without SSH.

### Steps

1. **Clone the repo and start heinzel**
   ```
   git clone https://github.com/wintermeyer/heinzel.git
   cd heinzel
   claude
   ```
   Or use `opencode` to launch OpenCode.
2. **Describe what you need in plain English**
   ```
   ❯ Install postgresql on server1.example.com
   ```
3. **Answer a few questions on the first connection**
   The first time Heinzel connects to a new server,
   it may ask for details it can't detect on its own
   — most commonly which SSH user to log in as. Your
   answers are stored in `memory/user.md` and the
   per-server memory file, so Heinzel won't ask again
   on future sessions. You can also pre-fill
   `memory/user.md` by copying `memory/user.md.example`
   and editing it — this is also where you set a
   preferred language (e.g. `Language: German`).
4. **Review and approve each command before it runs**
   Heinzel proposes every SSH command, explains what
   it does and why, and waits for your approval.
   Nothing runs without your say-so.

### Team setup

Heinzel supports team use where multiple people share
server state via git while keeping SSH usernames
personal.

1. Each team member copies `memory/user.md.example`
   to `memory/user.md` and sets their own SSH
   usernames. This file is always gitignored.
2. Edit `.gitignore` to track server memory — the
   comments in the file explain which lines to
   comment out.
3. If any team member uses heinzel locally (on their
   own machine), add their machine's hostname
   directory to `.gitignore` (e.g.
   `memory/servers/stefans-mbp/`).
4. Commit server memory changes after sessions so the
   team stays in sync.

## Updates & Versioning

Heinzel uses [semantic versioning](https://semver.org).
The current version is in the `VERSION` file; changes
are listed in `CHANGELOG.md`.

**Auto-update (Claude Code):** On every session start,
a hook runs `git pull` and reports version changes.
No action needed. Auto-update is skipped when pinned
to a tag (see below), when on a non-`main` branch, or
when `HEINZEL_NO_UPDATE=1` is set.

**Manual update (OpenCode / any tool):**

```bash
bin/heinzel-update           # pull latest
bin/heinzel-update --check   # check without pulling
```

**Pin to a stable version** (skip auto-updates):

```bash
bin/heinzel-update --pin v1.0.0   # pin
bin/heinzel-update --unpin        # back to main
```

**Opt out of auto-update** without pinning:

```bash
export HEINZEL_NO_UPDATE=1
```

### Upgrading from 1.x to 2.0.0

2.0.0 consolidates all user state under `memory/`.
Under 1.x, custom rules lived in `rules/custom/`
and the OpenCode config lived at the repo root.
The upgrade moves them automatically — no manual
work in the common case.

**Automatic (recommended).** Let the Claude Code
session-start hook run on your next session, or run
the update manually:

```bash
bin/heinzel-update
```

The hook detects the old layout and migrates:

```
rules/custom/*        →  memory/custom-rules/
opencode.json         →  memory/opencode.json
opencode.json.example →  memory/opencode.json.example
```

You'll see a one-time notice listing what moved.
Re-running the hook is a no-op.

**Manual** (if you're pinned to a 1.x tag or don't
use the Claude Code hook). First unpin, then pull:

```bash
bin/heinzel-update --unpin
bin/heinzel-update
```

Or move the files yourself:

```bash
mkdir -p memory/custom-rules
[ -d rules/custom ] && \
  mv rules/custom/* memory/custom-rules/ 2>/dev/null || true
[ -f opencode.json ] && \
  mv opencode.json memory/opencode.json
[ -f opencode.json.example ] && \
  mv opencode.json.example memory/opencode.json.example
```

**After upgrading**, review:

- Any personal scripts or cron jobs that reference
  the old paths.
- Your `.gitignore` if you edited it for team mode
  — the new defaults are re-organized around
  `memory/` (see the comments in the file).
- Take a fresh backup right after upgrading:
  `bin/heinzel-backup`.

**Rollback** if something goes wrong: restore your
pre-upgrade backup, or pin back to the last 1.x
release with `bin/heinzel-update --pin v1.0.6`.

## Backup & Restore

Heinzel keeps all your personal state under a
single directory — `memory/` — so backups are one
`tar` command. The tree is text and typically well
under a megabyte. No database, no hidden dotfiles,
no scattered config.

### What lives in `memory/`

- `user.md` — SSH usernames and language
  preference
- `blacklist.md`, `readonly.md` — access policies
- `servers/<hostname>/` — per-server memory,
  changelog, todo, and per-server rule overrides
- `custom-rules/` — your global rule overrides
- `opencode.json` — your OpenCode config
- `network.md`, `housekeeping.md` — cross-server
  facts and custom checks

### Back up

```bash
bin/heinzel-backup
```

Writes
`heinzel-backup-<hostname>-<timestamp>.tar.gz` to
the current directory. Use `--list` for a dry run,
`-o <path>` to write somewhere specific.

### Restore

```bash
bin/heinzel-backup --restore <file.tar.gz>
```

Refuses to overwrite existing `memory/` content
unless `--force` is passed. The archive is
validated — all entries must live under `memory/` —
before any files are written.

### Team mode note

In team mode, `memory/servers/`, `memory/network.md`,
`memory/housekeeping.md`, and
`memory/custom-rules/` are shared via git already.
But `memory/user.md`, `memory/blacklist.md`,
`memory/readonly.md`, and `memory/opencode.json`
are always personal and still need this backup.

## Features

### Auto OS-detection

The first time you point Heinzel at any machine, it
detects the OS, gathers hardware info, and remembers
everything for future sessions.

### DNS alias detection

When multiple DNS names point to the same server,
Heinzel detects this automatically by comparing IP
addresses. The first hostname becomes the canonical
name; additional names become symlinks that share the
same memory. Each alias can have its own SSH user.

### Memory across sessions

After working on a machine, Heinzel remembers it.
Next week you start a new session and type:

```
 ❯ Check on web1.example.com.
```

It reads
`memory/servers/web1.example.com/memory.md`, already
knows it's Debian 12 with nginx and PostgreSQL,
checks the local changelog, and picks up right where
it left off.

### Session to-do list

When a multi-step task gets interrupted — connection
drop, conversation ends, laptop closes — Heinzel
keeps a to-do list in
`memory/servers/<hostname>/todo.md` with checkboxes
for each step. On reconnection it shows what's still
pending and asks whether to continue or start fresh.

### Housekeeping checks

Run routine health inspections on any server:

```
 ❯ Run housekeeping on bremen1.wintermeyer.de
```

Heinzel checks disk, memory, load, pending updates,
firewall, SSL certificates, failed services, and
server-specific services. Problems are highlighted
at the top of a concise report.

### Security audit

Check security configuration on any server:

```
 ❯ Run a security audit on app.example.com
```

Heinzel checks SSH password authentication settings,
firewall status, and reports issues by severity.

### Plan mode (Claude Code)

For complex or unfamiliar tasks, switch to plan mode
before touching anything:

```
 ❯ /plan Migrate the database from MySQL to
   PostgreSQL on db.example.com
```

Heinzel explores the server, checks what's running,
reads configs, and drafts a step-by-step plan — but
makes no changes. You discuss the approach, adjust
it, and only when you approve does execution begin.

> **Note:** The `/plan` command is a Claude Code
> feature. OpenCode does not have an equivalent —
> simply ask Heinzel to plan before acting.

### Local administration

Heinzel also works on the local machine — no SSH
needed, commands run directly. The same safety rules,
memory, and guardrails apply whether the target is a
remote server or your own laptop.

This works on both Linux and macOS:

```
 ❯ Update all Homebrew packages on this Mac
```

```
 ❯ Check if the firewall is configured on
   this machine
```

## Supported AI Tools

Heinzel is tool-agnostic. Any terminal-based AI
coding assistant that reads project files and runs
shell commands will pick up the rules in `CLAUDE.md`
and the `rules/` directory.

### Claude Code

[Claude Code](https://docs.anthropic.com/en/docs/claude-code)
is Anthropic's CLI for Claude. It natively reads
`CLAUDE.md` and is the primary tool Heinzel was
developed with.

```
claude
```

### OpenCode with Ollama

[OpenCode](https://opencode.ai) is an open-source
terminal AI tool that supports many providers,
including local free models via
[Ollama](https://ollama.com). This lets you run
Heinzel entirely on your own hardware — no cloud
API required.

**1. Install Ollama and pull a model**

```bash
ollama pull qwen3.5:9b
```

**2. Expand the context window**

Ollama defaults to 4096 tokens — too small for
agentic tool use. Create a variant with a larger
context:

```bash
ollama run qwen3.5:9b
>>> /set parameter num_ctx 16384
>>> /save qwen3.5:9b-16k
>>> /bye
```

**3. Configure OpenCode**

Copy the example config and adjust if needed:

```bash
cp memory/opencode.json.example memory/opencode.json
```

Edit `memory/opencode.json` to match your setup —
e.g. change the `baseURL` if Ollama runs on a
different host (`http://192.168.0.3:11434/v1`), or
change the model name. The file is gitignored so
local edits won't conflict on `git pull`.

**4. Launch OpenCode**

```
opencode
```

Select the Ollama model from the model picker (search for qwen). 
Start the model picker by typing `/models` in the OpenCode terminal.

> **Note:** Larger models (14B+) produce more
> reliable tool calls. If you have the GPU memory,
> prefer a bigger model. The `tools: true` flag is
> required for agentic features. See the
> [OpenCode provider docs](https://opencode.ai/docs/providers/)
> for more configuration options.

## Command Line Interface

You can script Heinzel from the command line without
entering the interactive UI.

### Claude Code

Use the `-p` flag to pass a prompt directly:

```bash
$ claude --dangerously-skip-permissions \
  -p "What OS is installed on \
  server1.example.com? Login as root."
**server1.example.com** is running **Debian 11
(Bullseye)** on an aarch64 (ARM64) system with
4 CPU cores, 3.8 GB RAM, and a 15 GB root disk
(15% used).

Note: Debian 11 reached end of life in August
2024 and only receives long-term support (LTS)
until August 2026. You may want to plan an
upgrade to Debian 12 (Bookworm) before then.
$ claude --dangerously-skip-permissions \
  -p "Upgrade server1.example.com to Debian 12. \
  I have a backup. Don't ask me any questions. \
  Just do it. Give me a report afterwards."
---

## Upgrade Report: server1.example.com

**Debian 11 (Bullseye) -> Debian 12 (Bookworm)**
— completed successfully.

### What was done

1. **Verified Debian 11.11 was fully up to date**
   before starting
2. **Updated `/etc/apt/sources.list`** from
   `bullseye` to `bookworm` (backed up first)
3. **Ran `apt-get upgrade`** — installed packages
   that could upgrade without removals
4. **Ran `apt-get full-upgrade`** — completed the
   full dist-upgrade
5. **Cleaned up** — `autoremove` removed 28
   obsolete packages (410 MB freed)
6. **Rebooted** into the new kernel
   6.1.0-43-arm64
7. **Removed old kernel** 5.10.0-38-arm64
   (257 MB freed)
8. **Reinstalled `unattended-upgrades`** — it was
   dropped during the dist-upgrade

### Current state

|                         |                               |
| ----------------------- | ----------------------------- |
| **OS**                  | Debian 12.13 (Bookworm)       |
| **Kernel**              | 6.1.0-43-arm64                |
| **Disk**                | 15 GB, 19% used               |
| **nginx**               | running                       |
| **ufw**                 | active, default deny incoming |
| **unattended-upgrades** | installed and enabled         |
```

### OpenCode

Use the `run` command to pass a prompt directly:

```bash
opencode run "What OS is installed on \
  server1.example.com?"
```

Useful flags for scripting:

- `--format json` — machine-readable JSON output
- `-m provider/model` — override the model
- `-f file.txt` — attach files to the prompt
- `-c` — continue the previous session

For repeated calls without startup overhead, use the
headless server:

```bash
opencode serve
opencode run --attach http://localhost:4096 \
  "Check disk usage on web1.example.com"
```

## About `--dangerously-skip-permissions` (Claude Code)

By default Claude Code asks for your approval before
every tool call — every SSH command, every file read,
every write. The `--dangerously-skip-permissions` flag
disables these prompts so Claude runs everything
without asking.

The name is intentional: **it is dangerous.** You give
up the ability to review each command before it hits a
live server. On the other hand, it makes scripting and
batch work practical — you can't sit and approve 200
prompts during an unattended upgrade.

**When it makes sense:**

- Non-interactive / scripted use
  (`claude --dangerously-skip-permissions -p "..."`)
- Read-only tasks (checking OS, gathering info)
- Disposable environments (dev VMs, containers)

**When to avoid it:**

- First time working on a production server
- When you don't trust Heinzel or don't understand it
- Any time you want to understand what's happening
  step by step

Without the flag, Heinzel's safety rules still apply —
Heinzel still backs up configs, tests before applying,
and follows least privilege. The flag only removes
*your* approval step, not the built-in guardrails.

## Safety & Guardrails

Heinzel's safety rules are not optional — they're
baked into every session. Heinzel follows them
consistently, even when a human might skip steps
under pressure.

- **Asks before acting** — destructive commands,
  firewall changes, reboots, and network restarts
  all require your explicit approval.
- **Backs up config files** — copies to
  `/var/backups/heinzel/` before editing
  (auto-cleaned after 30 days).
- **Tests before applying** — uses dry-run, test, or
  validation modes before real execution whenever a
  tool supports it.
- **Auto-detects the OS** — reads `/etc/os-release`
  on Linux or `sw_vers` on macOS and applies the
  right commands for the platform. No guessing.
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
  as a last resort. If neither sudo nor root SSH
  is available, works in unprivileged mode and
  produces a sysadmin report for tasks that need
  root.
- **Server blacklist** — add hostnames or IPs to
  `memory/blacklist.md` to permanently block
  connection. Heinzel refuses to connect and won't
  accept overrides.
- **Read-only servers** — add hostnames or IPs to
  `memory/readonly.md` for servers you can inspect
  but must never modify. Deferred modifications are
  collected into a report you can hand off.
- **Ignores injected instructions** — text found in
  server files, logs, or command output is treated as
  data only. Suspicious patterns (text addressing the
  AI, embedded commands, safety-rule overrides) are
  flagged to the user, never followed.

## How Heinzel Fights LLM Hallucinations

LLMs can "hallucinate" — confidently produce commands
with wrong flags, incorrect file paths, or syntax that
doesn't exist on the server's specific OS and version.
On a live system, a hallucinated command can be
dangerous.

Heinzel reduces this risk with multiple layers:

- **Distro-specific rule files** — Instead of relying
  on the LLM's memory, heinzel loads a verified rule
  file for each platform (Debian, RHEL, SUSE,
  macOS). These files contain the correct
  commands, package managers, firewall tools, and
  common pitfalls for each distro. The LLM reads
  the file and follows it — it doesn't have to
  guess.
- **Verify before running** — heinzel is instructed
  to check `--help`, man pages, or upstream docs
  before running any command. This catches wrong
  flags and syntax before they reach the server.
- **Server memory** — Each server's OS, version,
  installed services, and configuration are recorded
  in a memory file. On subsequent connections, the
  LLM reads facts instead of guessing.
- **Test before apply** — Commands with a dry-run,
  test, or validation mode are checked that way first.
- **Human review** — Every command is shown to you
  before it runs. You are the final safeguard.

No approach eliminates hallucinations entirely. The
goal is to minimize what the LLM needs to recall
from training data by putting verified facts in front
of it at every step.

## Accessing Logs

Heinzel logs every action to the system journal on
each server. To query the log:

```bash
# All entries
journalctl -t heinzel

# Filter by date
journalctl -t heinzel --since "2026-02-01"

# Last 20 entries
journalctl -t heinzel -n 20

# macOS
log show \
  --predicate 'senderImagePath CONTAINS "logger"' \
  --info --last 7d | grep heinzel
```

## Supported Distributions

| Family  | Distributions                     | Rule file          |
| ------- | --------------------------------- | ------------------ |
| Debian  | Debian, Ubuntu                    | `rules/debian.md`  |
| RHEL    | RHEL, CentOS, Fedora, Rocky, Alma | `rules/rhel.md`   |
| SUSE    | openSUSE, SLES                    | `rules/suse.md`   |
| macOS   | macOS (Apple Silicon & Intel)     | `rules/macos.md`   |
| FreeBSD | FreeBSD (all versions)            | `rules/freebsd.md` |

Other distributions work too — Heinzel will apply
general best practices and let you know which OS it
detected.

## Risks & Responsibilities

> [!CAUTION]
> Heinzel operates on live servers and local machines
> — as root, with sudo, or in unprivileged mode.
> Always review every command before approving it.

Heinzel is for anyone willing to stay in the
driver's seat and review every command — from
newcomers learning Linux to veterans running fleets.
In fact, Heinzel can be an especially good teacher:
each proposed command comes with an explanation of
*what* it does and *why*, so you learn the real
sysadmin reasoning instead of copy-pasting Stack
Overflow answers.

We built Heinzel to be a help for everybody. By
design, it follows the safety checklist every single
time: it always backs up before editing, always
dry-runs when it can, always checks the OS before
assuming commands. A disciplined AI makes far fewer
mistakes than a tired human at 2 AM during an
outage. But we can't guarantee it won't ever make
one — LLMs can hallucinate, misread intent, or
produce a command with unintended side effects.

The question isn't whether Heinzel is risk-free —
it isn't. The question is whether a disciplined AI
that follows every safety rule every time, with a
human reviewing every command, produces fewer
disasters than a human working alone under
real-world conditions.

Stay in the driver's seat. Review every command. Do
not blindly approve.

## Rule Customization

Heinzel supports layered rule overrides so you can
customize behavior without editing the upstream rule
files (which would cause merge conflicts on
`git pull`).

Three layers, read in order (later wins):

1. **Base** — `rules/<name>.md` (upstream,
   git-tracked)
2. **Global custom** —
   `memory/custom-rules/<name>.md`
   (gitignored by default, opt-in team sharing)
3. **Per-server** —
   `memory/servers/<hostname>/rules.md`
   (gitignored with server memory)

Custom files use heading prefixes to control how
they interact with the base rules:

```markdown
## Add: Docker cleanup
New rules applied alongside the base.

## Replace: Firewall
Replaces the matching base section entirely.

## Remove: Common Pitfalls > snap
Skip this base section.
```

Sections without a prefix are treated as additions.
A special `memory/custom-rules/all.md` applies to
every server. Per-server overrides win over global custom
when both touch the same section.

## Project Structure

```
VERSION                — Current version number (semver)
CHANGELOG.md           — Release history
CLAUDE.md              — Main instructions (read by Claude Code
                         and OpenCode)
bin/
  heinzel-update       — Update, pin, or check heinzel version
  heinzel-backup       — Back up / restore your memory/ tree
  heinzel-migrate      — One-shot 1.x→2.0 user-state migration
                         (called automatically on update)
.claude/               — Claude Code only
  settings.json        — Project-level Claude Code settings
  hooks/
    check-updates.sh   — Auto-check for repo updates and
                         auto-migrate on session start
rules/                 — Upstream rule files (git-tracked)
  debian.md            — Debian & Ubuntu rules
  rhel.md              — RHEL, CentOS, Fedora, Rocky,
                         Alma rules
  suse.md              — openSUSE & SLES rules
  macos.md             — macOS rules
  freebsd.md           — FreeBSD rules
  efi-boot.md          — EFI boot management & dual-boot
  cloud-image.md       — Cloud image deployment
  dual-boot.md         — Dual-boot setup workflow
  os-replacement.md    — OS wipe-and-replace workflow
  partition-staging.md — Swap reclaim & hot-migrate for
                         repartitioning
  housekeeping.md      — Routine server inspection checklist
  security.md          — Security audit checks
  mise.md              — Language runtime manager (mise)
  privilege-escalation.md — Sudo, root SSH, unprivileged mode
  os-detection.md      — OS detection procedure
  ssh-user.md          — SSH username & language management
  server-memory.md     — Server memory file format
  changelog.md         — Session logging procedure
  activity-check.md    — Recent-activity summary on connect
  access-control.md    — Blacklist & read-only server rules
  anomaly-detection.md — Prompt injection & anomaly detection
  dns-aliases.md       — DNS alias detection & management
  backups.md           — Config file backup procedure
  best-practices.md    — Common anti-patterns to review
                         before risky actions
  deployment.md        — CI/CD deployment user rules
  directory-copy.md    — Cross-server directory copy checks
  port-check.md        — Port conflict detection before
                         starting services
  version-check.md     — Proactive stable version checking
                         and upgrade nudges
memory/                — All your user state (gitignored
                         by default; single-directory backup)
  MEMORY.md            — Index for server memory
  user.md.example      — SSH username template (copy to
                         user.md)
  user.md              — Your preferences and SSH usernames
  blacklist.md         — Blocked servers
  readonly.md          — Read-only servers
  housekeeping.md      — User-added custom checks
  network.md           — Cross-server network facts
  opencode.json.example — OpenCode config template (copy to
                         opencode.json)
  opencode.json        — Your local OpenCode config
  custom-rules/        — Your rule overrides that layer on
                         top of rules/*.md
  servers/<hostname>/
    memory.md          — Server state snapshot
    changelog.log      — Local change history
    todo.md            — Session task list
    rules.md           — Per-server rule overrides
```

## Why the Name Heinzel?

The name comes from the
[Heinzelmannchen](https://en.wikipedia.org/wiki/Heinzelm%C3%A4nnchen)
— the helpful gnomes of Cologne from German folklore.
Every night, while the people of Cologne slept, the
Heinzelmannchen crept out and did all the work: baking
bread, building houses, finishing whatever was left
undone. An invisible helper that quietly takes care of
things — a fitting name for a system administration
tool that handles the tedious work while you review
and approve.

## Professional Support

Need help setting this up for your infrastructure, or
want a team to manage your infrastructure with
AI-assisted tooling?

**[Wintermeyer Consulting](https://wintermeyer-consulting.de)**
offers consulting and hands-on support for heinzel
deployments — from initial setup to ongoing system
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
