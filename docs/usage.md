# Using Heinzel

- [Requirements](#requirements)
- [What happens without asking](#what-happens-without-asking)
- [Fewer prompts and scripting](#fewer-prompts-and-scripting)
- [Your data: `memory/`](#your-data-memory)
- [Rule customization](#rule-customization)
- [Updates](#updates)
- [AI tools](#ai-tools)
- [Logs](#logs)

## Requirements

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

You can pre-fill `memory/user.md` from
`memory/user.md.example`. It also holds your language
(`Language: German`).

## What happens without asking

- **OS detection.** On first contact Heinzel detects the OS
  and hardware and loads the rule file for that platform.
- **Memory.** Each server gets a folder under
  `memory/servers/` with its state, a changelog and an open
  to-do list, plus one file per SSH login for what differs
  between accounts (home, sudo, runtimes). An interrupted
  job shows up as pending on the next connection.
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

Heinzel shares one SSH connection per host and keeps it open
for 10 minutes after the last call. The sockets live in
`~/.cache/heinzel` (mode 0700), so any process of your local
user can use an open connection without the key.

## Fewer prompts and scripting

By default Claude Code asks before every tool call. For
batch work use **auto mode**: a background check lets routine
commands through and still stops on risky ones. Press
Shift+Tab to cycle modes, or pass the flag:

```bash
claude --permission-mode auto \
  -p "Run housekeeping on server1.example.com"
```

Auto mode trusts this checkout, not your servers, and refuses
changes over SSH until you name them under `autoMode` in
`~/.claude/settings.json`. It ignores that key in the
project's settings files. The block is in
`rules/service-reload.md`, and `/auto-mode-setup` drafts it.

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
Later wins:

1. `rules/<name>.md` (upstream)
2. `pro/` and `extensions/<name>/` (rule packs you
   installed, see [extensions.md](extensions.md))
3. `memory/custom-rules/<name>.md` (yours, all servers)
4. `memory/servers/<hostname>/rules.md` (one server)

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

## AI tools

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
