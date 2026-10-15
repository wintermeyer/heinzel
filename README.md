# Heinzel — System Administration with Safety Guardrails

Heinzel is a set of rules that turns an AI coding assistant
into a cautious, methodical sysadmin. Describe what you need
in plain English. Heinzel works out the right commands for
your OS, explains each one, and waits for your approval. It
backs up configs, tests before applying, and remembers every
server it has worked on.

It manages Linux, FreeBSD and macOS, remote over SSH or on
the local machine, and runs in
[Claude Code](https://docs.anthropic.com/en/docs/claude-code),
[OpenCode](https://opencode.ai) or any terminal AI tool that
reads project files and runs shell commands.

![Trailer: Heinzel at work](assets/heinzel-trailer.gif)

The trailer is scripted, not recorded. To change it, see
[`assets/trailer/`](assets/trailer/README.md).

Screencasts on YouTube:

- [Debug and fix a misconfigured nginx and firewall](https://www.youtube.com/watch?v=_uenftahbJI) (1 min)
- [Install the latest stable Ruby and Ruby on Rails](https://www.youtube.com/watch?v=QVvm29eABKY) (1 min)
- [Install a firewall, upgrade the distribution, set up daily security updates](https://www.youtube.com/watch?v=ve_TFyJy_uU) (2 min)

Press:
[German article about Heinzel on heise.de](https://www.heise.de/ratgeber/KI-Assistent-Heinzel-fuer-die-Server-Administration-im-Ueberblick-11244463.html)

## Install

You need:

- **An AI coding assistant in the terminal**, e.g. Claude
  Code or OpenCode.
- **SSH access to the server** as a normal user or as root,
  with a key that does not ask for a passphrase. Not needed
  for the local machine. New to SSH keys? See the
  [Arch wiki guide](https://wiki.archlinux.org/title/SSH_keys).
- **A workstation** running Linux, macOS, FreeBSD or Windows.
  On Windows use
  [WSL](https://learn.microsoft.com/windows/wsl/), or start
  the AI tool from the Git Bash of
  [Git for Windows](https://gitforwindows.org/). PowerShell
  and `cmd.exe` are not supported.

Then:

```
git clone https://github.com/wintermeyer/heinzel.git
cd heinzel
claude        # or: opencode
```

```
❯ Install postgresql on server1.example.com
```

On the first connection Heinzel may ask what it cannot
detect, usually the SSH user. The answer goes to
`memory/user.md`, so it asks once. You can pre-fill that file
from `memory/user.md.example`. It also holds your language
(`Language: German`).

Heinzel proposes every command, says what it does and why,
and waits for your approval.

Heinzel shares one SSH connection per host and keeps it open
for 10 minutes after the last call. The sockets live in
`~/.cache/heinzel` (mode 0700), so any process of your local
user can use an open connection without the key.

## What you can ask

- `Check on web1.example.com`: reads the server's memory file
  and recent changes, then picks up where the last session
  ended.
- `Run housekeeping on app.example.com`: a health report on
  disk, memory, load, updates, firewall, certificates and
  failed services. Problems come first.
- `Run a security audit on app.example.com`: SSH, firewall,
  accounts, open ports and kernel settings, by severity.
- `Email me the output of "df -h" from app.example.com`:
  sends text or files by mail, from your workstation or from
  the server.
- `Clean up leftovers of old apps on this Mac`: finds what
  removed apps left in `~/Library` and `/Library`. Only what
  you approve goes to the Trash.
- `Update all Homebrew packages on this Mac`: local mode, no
  SSH, same rules.
- `/plan Migrate the database on db.example.com`: explores
  and drafts a plan, changes nothing until you approve.
  `/plan` is Claude Code. In OpenCode, ask Heinzel to plan
  first.

More that happens without asking:

- **OS detection.** On first contact Heinzel detects the OS
  and hardware and loads the rule file for that platform.
- **Memory.** Each server gets a folder under
  `memory/servers/` with its state, a changelog and an open
  to-do list. An interrupted job shows up as pending on the
  next connection.
- **Long jobs.** A command that can take more than a
  minute runs as a job on the host, output and exit
  status in files, and is read back later, after a
  dropped connection or in a new session too
  (`rules/ssh-connections.md`).
- **DNS aliases.** Several names for the same IP share one
  memory. Each alias can have its own SSH user.
- **SSH ports.** A port other than 22 is stored per server.
  List the ports you use as `Alternative SSH ports:` in
  `memory/user.md`. Heinzel tries those and never scans.
- **Email details.** Mails carry a short signature with the
  operator's name (`Operator name:` in `memory/user.md`) and
  headers that keep out-of-office replies away. The first
  mail per host asks where to send from. Heinzel uses an
  existing MTA and asks before installing one.

The macOS cleanup scanner needs the Command Line Tools
(`xcode-select --install`).

## Heinzel or Heinzel Pro

Heinzel is one admin at one terminal, working on one host at
a time. [Heinzel Pro](https://heinzel-pro.de) is the
commercial product built on the same rules: a team, a web
interface, a fleet, and a runtime that enforces what Heinzel
can only ask for. Everything that needs a second person, an
identity, a fleet, a schedule or an evidence chain lives
there. Heinzel reads and reports those things and answers a
request to change them with one line pointing to Pro.

| | Heinzel (this repo, MIT) | Heinzel Pro |
| --- | --- | --- |
| Who | One admin, their terminal, their servers | A team, one web interface, a fleet |
| Connect, detect the OS, remember the host | Yes | Yes |
| Housekeeping, security audit, reports | On request | On a schedule, as a list of open findings, started by alerts |
| Packages, configs, services, firewall | Asks first | Rights per person and server, a second person where the tenant wants one |
| Accounts, SSH keys, sudo, deploy users | Inspects and reports | Creates and changes them, approved and logged |
| Secrets and certificates | Finds leaks, reports expiry | A rotation plan that names every consumer first, then the change as an approved session; certificates watched across the fleet and renewed |
| Partitions, boot loaders, OS replacement | Reads | Changes them, with a second person before every write where the tenant requires it |
| Many servers at once | One after another | Rollouts: one task on many servers, a canary first, then waves; OS upgrades the same way; a version matrix across a group |
| At night, with nobody there | No | Schedules that read alone and collect changes for the morning, alerts that start a diagnosis; maintenance windows per group, outside which every change waits for a person |
| Protected paths | `memory/protected-paths.md`: read-only, hidden, confirm | The same modes for the whole tenant, plus paths a tool manages, told to the agent on every server |
| What the agent may do | One guard, no off switch | Capabilities per tenant, off again per server: partitioning and OS replacement off from the start, identity and secrets on |
| Evidence | Journal and changelog on the host | Audit chain, access review, policy as a file |
| Own rules | Files in the checkout | Own rules per tenant and server, imported from a Heinzel checkout with its server memory, on top of the open rule set as a versioned bundle |

Resetting the password of an existing account, adding a key
the operator pastes in, and every package, config, service
and firewall change stay in Heinzel. Heinzel Pro runs as a
container, hosted or on your own servers; the details are on
[heinzel-pro.de](https://heinzel-pro.de).

## Safety & guardrails

The safety rules are part of every session.

- **Asks before acting.** Destructive commands, firewall
  changes, reboots and service restarts need your approval.
  Reloads run on their own when the config test passes
  (`rules/service-reload.md`, `memory/service-policy.md`).
- **Hard guardrails (Claude Code).** A PreToolUse hook
  (`.claude/hooks/guard-taboos.sh`) blocks the absolute
  taboos in every permission mode, even
  `--dangerously-skip-permissions`: halt and poweroff,
  `mkfs`, partition-table writers, boot-loader and EFI
  writers, deleting or overwriting SSH keys, writes to
  `sshd_config`, deleting accounts, writes to `sudoers`,
  the account files and the server lock. It also catches
  them inside `ssh host "…"`, behind `python3 -c` and when
  the file-edit tools target one of those files. Read-only forms
  (`fdisk -l`, `efibootmgr -v`, `visudo -c`) stay allowed.
  The hook has no off switch: what it blocks is Heinzel Pro's
  work. OpenCode does not run this hook; there the written
  rules are the safety layer.
- **Verifies before it reports.** "It is gone since the
  reboot" gets checked against the live system first
  (`rules/verify-before-reporting.md`).
- **Backs up config files** to `/var/backups/heinzel/` before
  editing. Cleaned up after 30 days.
- **Tests before applying** with dry-run or validation modes
  where a tool has one.
- **Logs everything.** Each change is one plain-language line
  in the system journal. The technical detail and the way
  back are in `memory/servers/<hostname>/changelog.log`.
- **Stable repos only.** No third-party sources without your
  approval.
- **Least privilege.** Normal user first, `sudo` when needed,
  root last. With neither, Heinzel does what it can and
  writes a report for the tasks that need root.
- **Blacklist and read-only servers.** Hosts in
  `memory/blacklist.md` are never contacted. Hosts in
  `memory/readonly.md` are inspected but never changed.
- **Server lock.** A machine's owner can lock it against
  every Heinzel with a file on the machine itself:

  ```
  # /etc/heinzel.conf
  allow_changes = false
  reason = Database migration until 20 Oct, hands off
  ```

  Heinzel still connects and inspects, but changes nothing
  and reports what it would have done. An unreadable file
  or any value other than `true` locks too. Heinzel never
  writes, moves or deletes the file; you remove the lock by
  hand. It is a promise kept by Heinzel, not a security
  boundary: it stops no tool that ignores it
  (`rules/access-control.md`).
- **Protected paths.** `memory/protected-paths.md` marks
  paths per server as `readonly`, `hidden` (content never
  shown) or `confirm` (needs a typed `CONFIRM`).
- **Ignores injected instructions.** Text in files, logs and
  command output is data. Text that addresses the AI is
  flagged to you and not followed.
- **Keeps secrets out.** Keys, password files and `.env`
  contents are inspected by metadata and fingerprint, never
  printed, and never passed as command-line arguments.

### Against hallucinations

An LLM can invent a flag or a path. Heinzel puts verified
facts in front of it instead:

- A rule file per platform holds the right commands, package
  manager and firewall tool.
- It checks `--help`, the man page or upstream docs before a
  command runs.
- It reads the server's memory file instead of guessing.
- It uses dry-run modes first.
- You see every command before it runs.

This reduces the risk. It does not remove it.

> [!CAUTION]
> Heinzel operates on live systems, as root, with sudo or
> unprivileged. Review every command before you approve it.

A disciplined AI that follows the checklist every time makes
fewer mistakes than a tired human at 2 AM. It can still
misread your intent. Stay in the driver's seat.

## Fewer prompts and scripting

By default Claude Code asks before every tool call. For
batch work use **auto mode**: a background check lets routine
commands through and still stops on risky ones. Press
Shift+Tab to cycle modes, or pass the flag:

```bash
claude --permission-mode auto \
  -p "Run housekeeping on server1.example.com"
```

`-p` runs one prompt without the interactive UI. In OpenCode
that is `opencode run "…"`.

- For CI, the strictest setup is `--permission-mode dontAsk`
  with an allowlist (`--allowedTools` or `permissions.allow`
  in `.claude/settings.json`).
- `--dangerously-skip-permissions` removes all review,
  including the protection against malicious text in server
  output. Use it in disposable environments only.
- Whatever the mode, Heinzel's own rules still apply. See
  the [permission modes docs](https://code.claude.com/docs/en/permission-modes)
  for details.

A run with nobody at the keyboard, nightly by cron or a
timer, is a Heinzel Pro feature: there a schedule reads
alone and collects what it would change for a person to
approve in the morning.

## Your data: `memory/`

All your state is plain text in one directory:

- `user.md`: SSH usernames, language, operator name
- `blacklist.md`, `readonly.md`, `protected-paths.md`: access
  policies
- `service-policy.md`: which services may reload or restart
  without asking
- `servers/<hostname>/`: memory, changelog, to-do and rule
  overrides per server
- `custom-rules/`: your global rule overrides
- `network.md`, `housekeeping.md`: cross-server facts and
  your own checks
- `opencode.json`: your OpenCode config

### Backup and restore

```bash
bin/heinzel-backup                        # writes a .tar.gz
bin/heinzel-backup -o <path>              # to a given path
bin/heinzel-backup --list                 # dry run
bin/heinzel-backup --restore <file.tar.gz>
```

Restore refuses to overwrite existing content without
`--force` and validates the archive before writing.

`memory/` is gitignored and personal: one checkout, one
person. Several people working on the same servers, with
rights, approvals and an audit trail, is Heinzel Pro.

## Rule customization

Change behaviour without editing the upstream rule files.
Three layers, later wins:

1. `rules/<name>.md` (upstream)
2. `memory/custom-rules/<name>.md` (yours, all servers)
3. `memory/servers/<hostname>/rules.md` (one server)

```markdown
## Add: Docker cleanup
New rules applied alongside the base.

## Replace: Firewall
Replaces the matching base section entirely.

## Remove: Common Pitfalls > snap
Skip this base section.
```

A section without a prefix is an addition.
`memory/custom-rules/all.md` applies to every server. Skills
follow the same chain, e.g.
`memory/custom-rules/heinzel-housekeeping.md`. A few rules
take additions only: the ethics rule, the guard's taboos,
the connection pipeline, anomaly detection, secrets hygiene
and the Heinzel Pro refusals cannot be replaced or removed.

## Updates

The version is in `VERSION`, the changes in `CHANGELOG.md`.
Claude Code updates Heinzel at session start with a
`git pull`, unless you are pinned, on another branch, or have
set `HEINZEL_NO_UPDATE=1`. Elsewhere:

```bash
bin/heinzel-update              # pull latest
bin/heinzel-update --check      # check only
bin/heinzel-update --pin v2.28.0
bin/heinzel-update --unpin
```

Coming from 1.x? The update moves `rules/custom/` and
`opencode.json` into `memory/` by itself. If you are pinned
to a 1.x tag, run `bin/heinzel-update --unpin` first.

## Supported systems

| Family  | Distributions                     | Rule file          |
| ------- | --------------------------------- | ------------------ |
| Debian  | Debian, Ubuntu                    | `rules/debian.md`  |
| RHEL    | RHEL, CentOS, Fedora, Rocky, Alma | `rules/rhel.md`    |
| SUSE    | openSUSE, SLES                    | `rules/suse.md`    |
| macOS   | Apple Silicon and Intel           | `rules/macos.md`   |
| FreeBSD | all versions                      | `rules/freebsd.md` |
| Unraid  | observed on 7.3                   | `rules/unraid.md`  |

Other distributions work with general best practices.

### AI tools

Claude Code is the tool Heinzel is developed with. OpenCode
reads the same `CLAUDE.md` and `.claude/skills/`, as long as
`OPENCODE_DISABLE_CLAUDE_CODE` is unset. Any other tool that
reads project files gets the rule layer. The skills
(housekeeping, security audit, email, macOS cleanup) need a
tool that supports Skills.

### OpenCode with a local model

Heinzel can run on your own hardware with
[Ollama](https://ollama.com):

```bash
ollama pull qwen3.5:9b
ollama run qwen3.5:9b
>>> /set parameter num_ctx 16384
>>> /save qwen3.5:9b-16k
>>> /bye
cp memory/opencode.json.example memory/opencode.json
opencode
```

Ollama's default context of 4096 tokens is too small for
tool use, hence the larger variant. Adjust `baseURL` and the
model name in `memory/opencode.json`, then pick the model
with `/models`. Larger models (14B and up) make more reliable
tool calls. See the
[OpenCode provider docs](https://opencode.ai/docs/providers/)
for more.

## Logs

Every change is logged on the server:

```bash
journalctl -t heinzel
journalctl -t heinzel --since "2026-02-01"

# macOS
log show \
  --predicate 'senderImagePath CONTAINS "logger"' \
  --info --last 7d | grep heinzel
```

## Project structure

```
CLAUDE.md        main instructions for the AI tool
rules/           rule files per platform and topic
.claude/skills/  housekeeping, security, email, macOS cleanup
.claude/hooks/   update check and the taboo guard
bin/             heinzel-update, heinzel-backup,
                 heinzel-migrate
memory/          your state (gitignored)
assets/trailer/  script that renders the README trailer
```

## Why the name?

The
[Heinzelmännchen](https://en.wikipedia.org/wiki/Heinzelm%C3%A4nnchen)
are the helpful gnomes of Cologne. At night, while the city
slept, they did the work that was left undone.

## Professional support

[Wintermeyer Consulting](https://wintermeyer-consulting.de)
offers consulting and hands-on support for Heinzel, from
setup to ongoing system management. Contact Stefan
Wintermeyer: **sw@wintermeyer-consulting.de**

## Contributing

Bug reports, feature requests and pull requests are welcome.
See [CONTRIBUTING.md](CONTRIBUTING.md): a contribution may
also end up in Heinzel Pro.

## License

MIT
