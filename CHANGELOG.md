# Changelog

## 2.4.0 — 2026-04-22

- Add `rules/service-class-check.md`: a new mandatory
  pre-install guardrail that halts when a planned
  package install would add a second member of a
  service class already present on the host. v1 covers
  three classes: web servers (apache2, httpd, nginx,
  caddy, lighttpd), relational databases (postgresql,
  mariadb-server, mysql-server), and mail MTAs
  (postfix, exim4, sendmail, opensmtpd).
- Detection runs in two phases per OS (Debian/Ubuntu,
  RHEL/Fedora, SUSE, FreeBSD, macOS best-effort): an
  already-installed probe of the package DB, plus a
  package-manager dry-run (`apt-get --simulate`,
  `dnf --assumeno`, `zypper --dry-run`, `pkg -n`,
  `brew deps`) to catch *transitive* pulls before
  anything lands on disk.
- On conflict, heinzel stops and presents four
  options: keep the existing service and look for a
  compatible install variant; remove the existing
  service first (as a separate destructive action);
  run both side by side and hand off to
  `rules/port-check.md` for a non-default port or
  Unix socket; or abort. No silent "go ahead"
  overrides — the user must name the option.
- `CLAUDE.md` gets a short pointer section between
  "Port Conflict Check" and "CI/CD Deployment".
  The rule inherits the standard override chain via
  `memory/custom-rules/service-class-check.md` and
  `memory/servers/<hostname>/rules.md`, so users can
  add DNS resolvers, caches, or other classes
  without patching the base rule.
- Why: a user asked heinzel to install a package that
  transitively pulled in Apache on a host where
  Nginx was already serving. Heinzel proceeded
  anyway, leaving the host with two web servers
  fighting for ports 80/443. `rules/port-check.md`
  catches *runtime* collisions; this rule catches the
  *install-time* case that precedes them.

## 2.3.0 — 2026-04-22

- Add `.claude/skills/heinzel-email/`: a new on-demand
  skill to send ad-hoc text and file attachments by email
  about a managed server. The first email per host asks
  where to send from (local workstation vs the server
  itself) via a four-option picker; "always for this host"
  persists the choice into per-server `memory.md`. On the
  remote path, prefers an existing MTA (postfix, sendmail,
  msmtp, mail/mailx) and asks before installing one. Two
  further consent gates ("use existing MTA" and "install a
  new MTA") use the same once / always / never picker.
- Sends as a non-root user via `runuser`/`su -` whenever
  the SSH session is root, dropping to the username from
  `memory/user.md` after verifying the account exists and
  can invoke the chosen transport. The install step is the
  only root-privileged operation in the workflow.
- Attachments check the sender UID can read the file
  (offers skip / copy-via-root-to-readable-temp / send-as-
  root-with-WARN), gate on size (10 MB threshold, gzip
  offered for text logs), and show a `head -5` preview
  before sending. Cap of 5 attachments per message in v1.
- Falls back to a hand-built MIME multipart message piped
  to `msmtp -t` when only msmtp is available. macOS
  `/usr/bin/mail` doesn't support attachments and is
  refused cleanly with a `brew install mutt` suggestion
  rather than auto-installing on the workstation.
- Per-server config (recipient, source, transport, sender
  identity, policies) lives in
  `memory/servers/<host>/memory.md`, extending the existing
  `Mail:` / `Alert email:` lines bremen3 already
  demonstrates. No new memory subsystem.
- Why: heinzel reports lived only in the conversation;
  there was no way to ship a log snippet, a housekeeping
  summary, or a list of failed services to an inbox.
  Adding email keeps heinzel's "ask before installing,
  least privilege, prefer existing tooling" posture
  end-to-end.

## 2.2.0 — 2026-04-20

- Add `rules/service-reload.md`: service reload/restart
  policy. `systemctl reload` now auto-proceeds by
  default once the service's config test passes
  (`nginx -t`, `named-checkconf`, `apachectl configtest`,
  etc.). `systemctl restart` still asks, and the ask
  now uses a four-option picker (once / always / no /
  never) so answers can be remembered instead of asked
  again next time.
- Add `memory/service-policy.md` (optional, gitignored,
  with a committed `.example` template). Three lists:
  `reload-always-ask` (force reload to ask),
  `restart-auto` (let restart run silently),
  `restart-never` (refuse restart outright, no prompt).
  The four-option picker writes to the matching list
  so the policy grows by use, not by manual editing.
- Session Start Preflight now also quietly loads
  `memory/service-policy.md` so the policy is in
  context before the first reload/restart request.
- Update `rules/debian.md`, `rules/rhel.md`,
  `rules/suse.md`, `rules/freebsd.md`, `rules/macos.md`:
  cross-reference the new reload policy from their
  Service Manager sections.
- Why: `systemctl reload nginx` after an approved
  nginx config edit was always a tax — the user had
  already approved the real change, but had to approve
  the no-op reload on top of it. Treating reload as
  auto-proceed (with config-test guard) removes the
  noise; the policy file keeps the user in control of
  the services that are actually risky to reload, and
  of every restart.

## 2.1.1 — 2026-04-17

- Add `.github/workflows/tag-release.yml`: auto-creates and
  pushes the matching `vX.Y.Z` tag whenever a push to `main`
  changes `VERSION`. Idempotent — no-ops if the tag already
  exists.
- Why: tag creation was a manual step that was easy to forget
  (v2.1.0 shipped today without its tag until noticed). Users
  who pin via `bin/heinzel-update --pin` depend on tags
  existing, so missing tags are a real regression. Automating
  the step removes the failure mode entirely.
- This bump to 2.1.1 is also the first live test of the new
  workflow.

## 2.1.0 — 2026-04-17

- Migrate `rules/housekeeping.md` and `rules/security.md`
  to native Skills at `.claude/skills/heinzel-housekeeping/`
  and `.claude/skills/heinzel-security/`. Each skill has a
  lean `SKILL.md` (workflow + invocation rules) plus a
  `references/` subdirectory that splits baseline checks,
  OS-specific probes, service-specific probes, and report
  format into separately-loadable files.
- Why: `CLAUDE.md` and the prose "read `rules/X.md`"
  pattern load every rule into every session, even when
  the user only wants a quick `df -h`. Housekeeping
  (581 lines) and security (604 lines) are the two biggest
  rule files and are both on-demand workflows — textbook
  progressive-disclosure candidates. Moving them into
  skills means their descriptions (a few hundred
  characters) load at session start; the full bodies load
  only when the user asks for a housekeeping or security
  run. Roughly 1,100 lines of rules prose stops being
  always-loaded.
- Cross-tool compatibility: both Claude Code and OpenCode
  read `.claude/skills/*/SKILL.md` natively and use the
  same two-stage progressive disclosure (description at
  startup, full body on invoke). Heinzel's `CLAUDE.md`
  stays authoritative for both tools (OpenCode reads it
  as the fallback to `AGENTS.md`). If `OPENCODE_DISABLE_\
  CLAUDE_CODE=1` is set by the user, both `CLAUDE.md` and
  `.claude/skills/` go dark — that's a user opt-out, not
  a heinzel regression.
- Override chain preserved and normalized: each skill
  reads its own global override file whose name matches
  the skill — `memory/custom-rules/heinzel-\
  housekeeping.md` for the housekeeping skill and
  `memory/custom-rules/heinzel-security.md` for the
  security skill — followed by `memory/housekeeping.md`
  (free-form cross-server checks), the server's
  `memory.md`, and finally `memory/servers/<host>/\
  rules.md` (per-server `## Add:` / `## Replace:` /
  `## Remove:` overrides).
- Guardrails untouched: `first-connection.md`,
  `access-control.md`, `ssh-user.md`,
  `privilege-escalation.md`, `os-detection.md`,
  `activity-check.md`, `anomaly-detection.md` stay as
  always-loaded rule files. Skills have no always-load
  semantics, so mandatory preflight steps must not move.
- Deferred for a later release: `rules/version-check.md`
  (hybrid usage — proactive nudges during housekeeping
  plus on-demand checks — needs decoupling first) and
  path-scoped OS rules.

## 2.0.11 — 2026-04-14

- Fix SessionStart hook on Windows. The previous
  command `sh "$CLAUDE_PROJECT_DIR/.claude/hooks/check-updates.sh"`
  failed on Windows with `/usr/bin/sh: cannot
  execute binary file` because cmd.exe does not
  expand `$CLAUDE_PROJECT_DIR` and the quoted path
  was handed to `sh` as a broken argument.
- Hook now uses a relative path and `bash` instead
  of `sh` — Git for Windows ships `bash.exe`
  reliably, and Claude Code runs hooks with the
  project directory as the working directory.
- `check-updates.sh` only `cd`s into
  `$CLAUDE_PROJECT_DIR` when that variable is set
  and points to an existing directory, so the hook
  no longer exits silently if the variable is
  missing or mangled.

## 2.0.10 — 2026-04-14

- Fresh-install onboarding no longer asks the SSH
  user question twice. Previously, when a new user
  pointed heinzel at a specific server on the very
  first session, they got two near-identical
  pickers back-to-back: one for the default, one
  for the server. The two prompts looked
  duplicated and were confusing.
- `rules/ssh-user.md` now distinguishes three
  cases: (A) fresh install with a server already
  specified — one combined question whose answer
  is saved as both the default and the per-server
  entry; (B) fresh install with no target — ask
  only for the default; (C) default exists, first
  connection to a new server — per-server prompt
  as before.
- The combined question makes the dual save
  explicit in the prompt text so the user
  understands one answer covers both.

## 2.0.9 — 2026-04-14

- First-time SSH-user interview now uses the
  `AskUserQuestion` picker in Claude Code (real
  selectable options, the "checkbox UI"), falling
  back to the ASCII `[1/2/3]` prompt in OpenCode
  and other tools that lack the picker. Same for
  the per-server first-connection prompt.
- CLAUDE.md's Session Start Preflight section now
  explicitly forbids improvising setup questions
  or bundling multiple questions into one prompt
  — Claude must hand off to `rules/ssh-user.md`'s
  interview format verbatim.

Why: on a fresh install the first interaction
was a freeform numbered list ("1. SSH username
to use… 2. Where should I save it?") instead of
the prescribed three-option picker. New users
lost the nicest part of the onboarding flow.

## 2.0.8 — 2026-04-14

- New "Session Start Preflight" section in
  CLAUDE.md tells Claude to load the initial memory
  files (`user.md`, `blacklist.md`, `readonly.md`,
  `custom-rules/all.md`) via the Read tool instead
  of a shell `for`-loop with `cat`, and to
  announce the preflight in one friendly line
  first. Fresh-install users previously saw a
  cryptic Bash permission prompt before anything
  else happened; now they see a short human
  sentence and no prompt at all in the common
  case.

## 2.0.7 — 2026-04-14

- CLAUDE.md now tells the workstation AI not to
  read `CHANGELOG.md` unless the user asks. Release
  notes are mostly for heinzel developers, not for
  sysadmin sessions; `git log` is the source of
  truth for repo history.

## 2.0.6 — 2026-04-14

Three bug fixes found during an audit of the shell
scripts:

- `bin/heinzel-backup --help` failed with "awk:
  can't open file" when invoked with a path that
  didn't resolve from the repo root (e.g.
  `sh ./heinzel-backup --help` from inside `bin/`).
  The script `cd`s to the repo root before
  `usage()` runs, so the relative `$0` was broken.
  Now computes an absolute path to self and passes
  that to `awk`.
- `.claude/hooks/check-updates.sh` could hang on
  `git pull` if the remote required credentials
  (HTTPS with expired token). The SessionStart
  hook's 15s timeout would kill it mid-operation.
  Now sets `GIT_TERMINAL_PROMPT=0` and a no-op
  `GIT_ASKPASS` so git fails fast instead.
- `bin/heinzel-update --pin <tag>` rejected valid
  remote tags on fresh or shallow clones because
  `git rev-parse` only looks at local refs. Now
  runs `git fetch --tags --quiet` first so
  remote-only tags resolve.

## 2.0.5 — 2026-04-14

- Native Windows (Git Bash) now works as a
  workstation. The SessionStart hook is invoked via
  `sh …` explicitly instead of relying on the file
  exec bit, `bin/heinzel-migrate` is called the
  same way, and a new `.gitattributes` forces LF
  line endings on all shell scripts so
  `core.autocrlf=true` on Windows can't corrupt the
  shebang.
- README Prerequisites spells out the Windows
  options: WSL (recommended) or Git for Windows
  (Git Bash). PowerShell and `cmd.exe` are
  explicitly unsupported as the launch shell.

Why: the previous README claimed Windows support
"natively or via WSL," but the auto-update hook
and helper scripts weren't actually portable to a
non-WSL Windows environment. These changes close
the gap for Git Bash users without adding
PowerShell duplicates.

## 2.0.4 — 2026-04-14

- README clarifies that Heinzel manages Linux,
  FreeBSD, and macOS *targets* but runs on any
  workstation where the AI tool runs — including
  Windows (via WSL or natively).

Why: users have asked whether they need a
Linux/macOS workstation to use Heinzel. They don't
— the repo is plain files and shell scripts, and
the only platform constraints are on the managed
targets, not the workstation.

## 2.0.3 — 2026-04-14

- `rules/ssh-user.md` now specifies a three-option
  interview for the SSH-user prompt: the current OS
  user (detected via `whoami`/`$USER`), `root`, or
  a custom name. Applies to both the initial
  default setup (when `memory/user.md` is missing)
  and to first-connection-to-a-new-server prompts.

Why: on a fresh install, heinzel already knows who
launched it — asking "what's your typical
username?" as an open question was clumsy. Offering
the detected OS user as the preselected default,
with `root` and "other…" one keystroke away, gets
most installs through setup in a single `1` press.

## 2.0.2 — 2026-04-14

- New `rules/first-connection.md` consolidates the
  mandatory onboarding pipeline (blacklist,
  read-only, DNS alias, SSH user, OS detection,
  server memory, activity check) into one ordered
  checklist. The sequence was previously spread
  across six rule files with no single entry point.
- `CLAUDE.md` gains a **No Shortcuts for "Quick"
  Questions** section and a direct pointer to the
  new checklist from the Remote mode section.

Why: on bremen3.wintermeyer.de, Claude ran `df -h`
in response to a disk-space question and skipped
the entire onboarding pipeline, citing "you only
asked a quick question." No rule permitted that
shortcut — Claude invented it. Tightening the
language and providing a single ordered checklist
removes the reasoning gap.

## 2.0.1 — 2026-04-14

- `bin/heinzel-backup` now uses `mktemp
  "${TMPDIR:-/tmp}/heinzel-backup.XXXXXX"` instead
  of `mktemp -t`, which differs between BSD (macOS)
  and GNU (Linux) — the old form worked by
  accident on macOS but produced an awkward file
  name on Linux
- README Project Structure tree now lists
  `rules/activity-check.md` and
  `rules/best-practices.md`, which were inventoried
  missing during the 2.0 audit

## 2.0.0 — 2026-04-14

**BREAKING:** All user state is now consolidated
under `memory/`. Backups are a single
`tar czf backup.tgz memory/` — no more tracking
three scattered locations.

- `rules/custom/` → `memory/custom-rules/`
- `opencode.json` → `memory/opencode.json`
- `opencode.json.example` → `memory/opencode.json.example`
- `.gitignore` rewritten around the new single
  user-state root with team-mode opt-in comments
- New `bin/heinzel-backup` script: dry-run, backup,
  and restore a `memory/` archive. Restore
  validates entries live under `memory/` and
  refuses to overwrite existing state without
  `--force`
- Auto-migration: `.claude/hooks/check-updates.sh`
  now detects the 1.x layout on session start and
  moves files into place, idempotently
- README gained a "Backup & Restore" section and a
  "Upgrading from 1.x to 2.0.0" walkthrough

Why: previously, user state was spread across
`memory/*`, `rules/custom/`, and the repo-root
`opencode.json`, which made backups a scripted
operation rather than a one-liner and required
multiple `.gitignore` blocks that had drifted
apart. Pulling everything under `memory/` makes the
mental model, the gitignore, and the backup story
all collapse to one directory.

Users on pinned 1.x tags won't be affected until
they unpin; everyone on `main` gets auto-migrated
on the next Claude Code session start. OpenCode
users or anyone bypassing the hook should run
`bin/heinzel-update` (or follow the manual steps
in the README's upgrade section).

## 1.0.6 — 2026-04-14

- Reframed the "Risks & Responsibilities" section:
  Heinzel is now positioned as a help for everybody
  — newcomers and veterans alike — rather than a
  tool only for experienced sysadmins, while being
  honest that no guarantee is possible

## 1.0.5 — 2026-04-14

- Merged the duplicate "Getting Started" section
  into "How to Install": Prerequisites and Team
  setup are now subsections of install, removing
  two parallel install guides
- Renamed the Features entry "Auto-detection" to
  "Auto OS-detection" and dropped its example
  prompt snippets

## 1.0.4 — 2026-04-14

- README install guide now mentions that Heinzel
  asks a few questions on the first connection
  (e.g. which SSH user) and remembers the answers

## 1.0.3 — 2026-04-14

- README restructured: renamed "How It Works" to
  "How to Install", promoted feature showcases into
  a dedicated "Features" section, moved
  "Updates & Versioning" directly after install, and
  replaced generic "the AI" phrasing with "Heinzel"
  for a consistent voice
- Clarified in the README that auto-update is
  skipped when pinned to a tag, on a non-`main`
  branch, or when `HEINZEL_NO_UPDATE=1`

## 1.0.2 — 2026-04-14

- Changelog rule now records the *why* of an action
  (inline `— because <reason>` or separate `Reason:`
  entry) when the motivation is known

## 1.0.0 — 2026-04-13

- Initial versioned release
- Auto-update hook with version awareness
- Version pinning support via git tags
- Standalone update script for OpenCode users
