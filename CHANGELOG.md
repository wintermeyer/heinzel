# Changelog

## 2.13.1 — 2026-07-12

- **Verify a finding before you report or
  escalate.** New `rules/verify-before-reporting.md`:
  before handing over a conclusion that something is
  missing, lost, moved, broken, or caused by an
  event, confirm it against the live system first.
  Resolve the real location from config instead of
  memory (`systemctl cat`, drop-ins,
  `EnvironmentFile`, `grep`, `find`); prove absence
  instead of assuming it ("not where I expected" is
  not "gone" — check mounts, `/etc/fstab`, the
  journal's `*.mount` unit, parent-directory mtime,
  and the filesystem's own "Last mounted on"); don't
  assert a cause the records don't show; and exhaust
  read-only checks within your privilege before
  escalating. Prompted by a least-privilege heinzel
  reporting a data directory as "gone since the last
  reboot" when the application had always stored it
  elsewhere, where a single read-only config lookup
  would have shown the data safe and avoided the
  escalation. Wired into CLAUDE.md as a Critical
  Safety Rules bullet and a section beside Anomaly
  Detection.

## 2.13.0 — 2026-07-01

- **Verify cross-backups at the receiver.**
  `rules/backups.md` gains a section on confirming a
  pull-based cross-backup (host A's dumps copied to
  host B) actually landed: check the dump files on the
  receiver, match the newest against the source, and
  run an integrity check, because a running job or a
  present cron line proves nothing. Documents a
  silent-failure gotcha: when the source exposes dumps
  through a symlink whose target sits outside the
  `rrsync -ro` jail, a plain `rsync -a` copies the link
  verbatim and transfers zero data with no error or
  warning email; the pull must pass
  `--copy-unsafe-links` so the sender follows the link.
  Also notes that dry-runs need `rsync -n -v`, since a
  bare `rsync -n` lists nothing and reads as "0 files".

## 2.12.0 — 2026-07-01

- **Never pass secrets on the command line.**
  `rules/secrets.md` gains a section keeping
  credentials out of `argv`, which is world-readable
  via `ps` and `/proc/<pid>/cmdline` and gets copied
  into shell history and the systemd journal by any
  tool that logs its own invocation; a looped command
  multiplies every copy. Heinzel now prefers a native
  credentials file, an environment variable, or an
  interactive prompt, and uses an inline flag only as
  a last resort (flagging the leak when it must). Adds
  per-tool guidance (`psql`/`.pgpass`,
  `cypher-shell`/`NEO4J_PASSWORD`, `mysql`/`.my.cnf`,
  `redis-cli`, `curl`/`.netrc`, restic/borg) and a
  procedure for when a credential has already leaked:
  do not repeat it, rotate it only with the user's
  approval after mapping and minimizing the blast
  radius (reliably scrubbing every log copy is not
  feasible), and switch to a non-leaking channel. Prompted by a Neo4j password
  found in a host's journal in cleartext after
  repeated inline `cypher-shell -p` runs. Updated the
  CLAUDE.md Secrets Hygiene summary and README.

## 2.11.0 — 2026-06-11

- **Human-readable journal entries.** Journal entries
  (`logger -t heinzel`) are now one-sentence,
  plain-language headlines written for admins who were
  not part of the session: a `[<operator> as
  <unix-user>]` identity prefix, the change in plain
  words, and the reason in a single fixed `— because`
  shape (~250 chars max). Technical detail (backup
  paths, commit hashes, rollback recipes, verification)
  moves to the local mirror
  `memory/servers/<hostname>/changelog.log`, which now
  carries indented `Detail:` / `Rollback:` / `Verify:` /
  `Flags:` blocks under each headline — the previous
  rule had this backwards (walls of text in the journal,
  compressed mirror). Constraints other admins must know
  get their own headline entry. Reworked
  `rules/changelog.md`; updated `rules/activity-check.md`
  example and README.

## 2.10.1 — 2026-06-10

- **Fix: taboo guard failed open after `cd` (#2).** The
  PreToolUse hook was registered with a relative script
  path, but hook commands run in the session's current
  working directory. After any `cd` the path no longer
  resolved, the hook errored non-blocking, and every
  subsequent Bash command ran unguarded. Both hooks
  (guard-taboos, check-updates) are now registered via
  `$CLAUDE_PROJECT_DIR`, and the test matrix gained a
  check that rejects relative hook paths in
  `settings.json`. Reported by @DanMitrea.

## 2.10.0 — 2026-06-10

- **Hard guardrails (Claude Code).** A shipped PreToolUse
  hook (`.claude/hooks/guard-taboos.sh`) now mechanically
  blocks the absolute taboos — halt/poweroff, `mkfs`,
  partition-table writers, deleting SSH keys, writes to
  `sshd_config` — in **every** permission mode, including
  `--dangerously-skip-permissions`, and even when the
  command hides inside an `ssh host "…"` wrapper. Read-only
  forms (`fdisk -l`, `gpart show`, `sgdisk -p`, `cat
  sshd_config`, …) stay allowed. Legitimate exceptions (OS
  replacement) require the operator to launch the session
  with `HEINZEL_GUARD_DISABLE=1`; the model cannot set it
  inline. A minimal `permissions.deny` list backs the hook
  as a second layer. 56-case test matrix in
  `guard-taboos-test.sh`. Note: a session can now see a
  command blocked mid-run — that is the guard working, not
  an error. OpenCode does not read Claude Code hooks; there
  the prose rules remain the safety layer.
- **Backup-presence check in housekeeping.** Every
  housekeeping run now answers the most basic question:
  does this host have ANY data backup? Probes common tools
  (restic, borg, rsnapshot, kopia, …), backup-shaped timers
  and cron jobs, ZFS/btrfs/LVM snapshots (a same-pool
  snapshot is flagged as not off-host), DB dump jobs, and
  Time Machine on macOS. Nothing found is CRITICAL — and
  because provider snapshots (Hetzner, AWS, Proxmox) are
  invisible from inside the server, heinzel asks the user
  once and records the answer as a `Backup:` line in the
  server's memory, re-confirming after ~180 days.
- **Scheduled housekeeping.** New
  `rules/scheduled-housekeeping.md`: nightly/weekly health
  reports via cron or systemd timer +
  `claude --permission-mode auto -p "…"`, delivered by
  heinzel-email. One interactive dry run answers all
  one-time questions into memory; flock prevents
  overlapping runs; never bypassPermissions unattended.
- **Secrets hygiene.** New `rules/secrets.md`: secrets are
  objects to manage, never content to display. Inspect
  private keys, password files, and `.env` via metadata and
  fingerprints (`ls -l`, `ssh-keygen -lf`,
  `openssl x509 -noout`); redact credential values from
  changelogs, memory, todo lists, and emails; likely-secret
  files are refused as email attachments by default (even
  the preview would leak); never copy key material under
  the repo; user-pasted secrets are used once and never
  persisted. Cross-referenced from CLAUDE.md, the changelog
  and server-memory rules, anomaly detection, and the email
  skill.

## 2.9.0 — 2026-06-10

Repo-wide rules audit: every rule file, skill, and helper
script was reviewed for contradictions, security gaps, and
beginner traps, and the findings fixed.

### Security fixes

- `rules/freebsd.md`: the "minimal safe pf.conf" example
  relied on the `egress` interface group; on hosts where
  that group is missing or empty, the SSH pass rule
  matched nothing and `block in all` cut off SSH the
  moment the rules loaded. The example now uses an
  explicit interface macro. Also new: mandatory
  `pfctl -nf` parse test before any load, and an
  `at`-scheduled `pfctl -d` safety net for rule changes
  over SSH.
- `rules/os-replacement.md`: the mfsBSD workflow left a
  production IP running sshd with root and the published
  default password during the whole install window. Now
  mandatory: bake an SSH key / changed password into the
  image or restrict access at the provider firewall
  before dd'ing. Downloaded images must be checksum-
  verified before any disk write, with an explicit point
  of no return. Private key material (TLS keys, SSH host
  keys) must never be saved under the repo, where team
  mode could git-share it.
- `bin/heinzel-backup --restore`: archive validation only
  checked entry names, so a crafted tarball could plant a
  symlink pointing anywhere on the filesystem. Restore
  now rejects symlink/hardlink entries, extracts to a
  temp dir first (no half-restored `memory/` on a
  truncated archive), and resolves relative paths against
  the directory you invoked it from.
- `rules/access-control.md`: blacklisted hostnames were
  only string-matched, so a DNS alias of a blacklisted
  host slipped through. Listed hostnames are now resolved
  and compared by IP as well; DNS-failure behaviour is
  defined (fall back to string match and tell the user).
- `rules/cloud-image.md`: built images no longer allow
  root SSH login by password (`PermitRootLogin
  prohibit-password`; the root password is console-only).
- `rules/anomaly-detection.md`: suspected prompt
  injections are now quoted as labeled untrusted data
  instead of echoed verbatim, and a new section forbids
  interpolating unsanitized server output into shell
  command lines.

### Guardrails

- `rules/partition-staging.md` and `rules/dual-boot.md`
  gained mandatory safety gates: verified backup,
  user-approved layout, data-integrity verification, and
  a marked POINT OF NO RETURN with explicit confirmation
  before any partition table or pool is destroyed.
- Firewall SSH-lockout warnings are now consistent across
  all OS families: `rules/rhel.md` and `rules/suse.md`
  warn to verify the `ssh` service is in the firewalld
  zone before starting the firewall (previously only
  Debian and FreeBSD had lockout warnings).
- Unattended updates are security-only everywhere:
  `rules/suse.md` now recommends
  `zypper patch --category security` instead of nightly
  full upgrades; `rules/freebsd.md` defaults to a
  notify-only cron job instead of `pkg upgrade -y`.
- `rules/deployment.md`: fixed the broken "nologin +
  SSH `command=`" recipe (forced commands run through the
  login shell, so nologin refuses); now pairs a minimal
  shell with `no-pty,no-port-forwarding,...` key options.
- `rules/service-reload.md`: resolved an internal
  contradiction — reloads auto-proceed only when a config
  test exists and passes; no known test means ask.
- `rules/macos.md`: warns that `softwareupdate
  --install --all` can pull OS updates needing a restart;
  list first, never `--restart` without asking.

### Fixes

- `rules/debian.md`: pinned-package verification used a
  command that never matches (and the banned `apt`);
  now `apt-cache policy`. Pinning warning added (frozen
  packages get no security updates). Unattended-upgrades
  check now names `20auto-upgrades` and the
  `apt-daily-upgrade.timer`. New dist-upgrade pitfall.
- `rules/suse.md`: fixed `zypper --dry-run update`
  argument order.
- `rules/mise.md`: apt repo line no longer hardcodes
  `arch=amd64` (broke arm64 hosts); shell setup is
  idempotent, backs up `.bash_profile`, and covers zsh
  (`~/.zshenv`) and FreeBSD sh/csh; hardcoded runtime
  versions replaced with web-search-first placeholders.
- `rules/dns-aliases.md`: resolution now filters for A
  records (a CNAME chain no longer breaks alias detection
  and the blacklist IP match); round-robin DNS no longer
  false-alarms the IP verification.
- `rules/activity-check.md`: no more silent blindness as
  non-root — tries `sudo -n journalctl` and tells the
  user when journal visibility is limited. Dropped the
  fictional "FreeBSD with systemd".
- `rules/privilege-escalation.md`: local mode skips the
  root-SSH fallback; sudo probe records why sudo is
  unusable instead of guessing.
- `rules/os-detection.md`: maps derivatives via
  `ID`/`ID_LIKE` (Ubuntu→debian, Rocky/Alma→rhel, …) and
  defines behaviour for unmatched distros.
- `rules/freebsd.md`: removed corrupted duplicate text at
  the end of the file; fixed a hyphen-broken flag.
- `rules/version-check.md`: removed the non-existent
  `ollama update` command from an example.
- `bin/heinzel-update` and the session-start hook now
  pull with `--ff-only` (a diverged local `main` fails
  loudly instead of creating a silent merge commit) and
  print friendly guidance on pull failures.
- Fleet-audit probes distinguish "needs root" from
  "absent" — an unreadable ufw is no longer reported as
  "no firewall" drift. The skill's "read-only" claim was
  corrected (it writes one audit-trail journal line per
  host).
- Housekeeping "pending security updates" now counts
  security updates instead of all upgrades.
- `heinzel-housekeeping` and `heinzel-security` state
  their FreeBSD scope limits explicitly instead of
  silently skipping; the security skill now rates a
  missing Linux firewall CRITICAL (was WARN), matching
  housekeeping.
- `heinzel-email` runs the mandatory service-class
  conflict check before installing an MTA.
- README: the `--dangerously-skip-permissions` section
  was replaced with Claude Code's auto mode
  (`--permission-mode auto`) — prompt-free batch work
  with a background safety check instead of no checks at
  all; allowlist-based `dontAsk` documented for CI. Also
  fixed stale skill lists and the backup-restore claims.

## 2.8.0 — 2026-05-19

- New skill `heinzel-fleet-audit`: read-only side-by-side
  comparison of key policies (unattended-upgrades, sshd
  effective config, firewall posture, MTA, time sync,
  auto-reboot behaviour) across every server in
  `memory/servers/`. Surfaces silent drift between hosts
  in a single table with a "Drift detected" section that
  links each disagreement to a suggested fix. Never
  modifies a host. Use after a config fix on one server
  to find which others carry the same bug, or as a
  periodic consistency check.
- `heinzel-housekeeping` now audits whether
  unattended-upgrades is actually *installing* security
  updates, not just whether the unit is "active". The
  Debian/Ubuntu baseline now checks that
  `/etc/apt/apt.conf.d/20auto-upgrades` exists with both
  periodic values set to 1, that the Origins-Pattern
  includes the `${distro_codename}-security` codename
  required by Debian Trixie and later, that `Mail` or
  `MailReport` is set so failures are not silent, and
  that the log shows recent Debian package activity in
  the last 30 days (not just no-op runs). Flags
  `Automatic-Reboot-Time` as anti-pattern because
  deferring the kernel reboot leaves the new userland
  on the old kernel for hours.
- `heinzel-housekeeping` now checks for the gap between
  installed package and running binary on critical
  services. Uses `needrestart -b -p` where available, with
  a manual `/proc/<pid>/exe` mtime fallback. Catches the
  case where a security patch is installed but the
  master process kept the old binary in memory, and the
  case where `needrestart` deferred a restart (most often
  `docker.service`, `dbus.service`, `systemd-logind`).
- `rules/backups.md` now explicitly forbids leaving
  in-place backups inside drop-in directories
  (`/etc/apt/apt.conf.d/`, `/etc/sudoers.d/`,
  `/etc/ssh/sshd_config.d/`, `/etc/cron.d/`,
  `/etc/systemd/system/*.d/`, `/etc/nginx/conf.d/`,
  `/etc/logrotate.d/`, `/etc/profile.d/`). Those
  directories are parsed file by file, so a `.bak` or
  timestamped sibling either logs daily warnings or
  changes runtime behaviour. Backups go to
  `/var/backups/heinzel/` only.

## 2.7.0 — 2026-05-02

- `heinzel-email` now pins the persona of every outgoing
  message: Heinzel is the apparent author, the operator is
  the principal Heinzel acts for. Body text, including any
  casual sign-off above the fixed greeting, speaks in
  Heinzel's voice on the operator's behalf. A closing line
  in the body must read like `Heinzel (for <Operator>)`,
  never `<Operator> (via heinzel)` or any phrasing that
  frames the operator as the author with Heinzel as a
  delivery channel.
- The `Reply-To` resolution rule is now explicit that the
  operator email is the human *using* Heinzel, never an
  account on the managed server. The skill must not probe
  `getent passwd`, `/etc/aliases`, `~/.forward`, or any
  mail metadata on the target host to derive it. Replies
  always land in the operator's real off-server inbox.

## 2.6.0 — 2026-04-27

- `heinzel-email` now sets `From: noreply@<sending-host-fqdn>`
  on every outgoing message and adds a `Reply-To:` header
  pointing at the human operator. Recipients see at a glance
  that the From mailbox is unread, but a one-click "Reply"
  still lands in a real inbox. The `noreply@…` mailbox does
  not need to exist on the host: real bounces follow the
  envelope sender (the submitter UID picked in 5R.4, or the
  current shell user on the local path), which is always a
  real account that can receive MAILER-DAEMON notices.
- Reply-To resolution mirrors the Operator-name chain:
  per-host `Reply-To:` in `memory/servers/<host>/memory.md`,
  global `Reply-To:` in `memory/user.md`, Claude Code
  auto-memory ("Default email" entry referenced from
  `MEMORY.md`), then `git config --global user.email`. First
  resolution from auto-memory or git config is persisted to
  `memory/user.md` under `# Preferences`, so the next run
  skips the probe and the user can edit the canonical value.
- Hosts can pin a non-default From mailbox by adding a `From:`
  line to their `memory.md`, e.g. `alerts@<host>` for hosts
  where a department-style identity is preferred.
- The verify step now treats the postfix `from=<…>` envelope
  vs. the visible `From:` header as deliberately decoupled,
  and no longer flags the mismatch as an anomaly.

## 2.5.0 — 2026-04-23

- `heinzel-email` now stamps every outgoing message with a
  fixed anti-auto-reply header triple so out-of-office and
  vacation responders leave Heinzel mail alone:

      Auto-Submitted: auto-generated
      Precedence: bulk
      X-Auto-Response-Suppress: OOF, AutoReply

  `Auto-Submitted` is RFC 3834 and is honoured by
  standards-compliant responders. `Precedence: bulk` covers
  legacy Unix vacation(1) / Sieve setups.
  `X-Auto-Response-Suppress` silences Microsoft Exchange /
  Outlook OOFs. Together the three cover the realistic
  responder population.
- The canonical send path is now `sendmail -t -oi` with a
  fully composed RFC 822 message (headers + blank line +
  body + greeting + signature), so custom headers survive
  every MTA uniformly. `mutt` and `mail -a` shell-outs are
  retired; `msmtp -t` remains the fallback when only msmtp
  is on the host. macOS uses its Postfix `/usr/sbin/sendmail`
  shim via the same invocation.
- `heinzel-email` now gives every outgoing message a human
  close. Between the body and the signature block Heinzel
  inserts a fixed two-line greeting:

      Viele Grüße
      Heinzel

  Heinzel is the author of the greeting; the operator
  attribution stays one block lower in the signature. A
  `Greeting:` line in `memory/user.md` (global) or
  `memory/servers/<host>/memory.md` (per-host) replaces the
  default wording verbatim, and a per-send instruction
  always wins over memory.
- `heinzel-email` now appends a fixed signature block to
  every outgoing message. The block uses the RFC 3676
  delimiter (`"-- "`) so MUAs like Gmail, Thunderbird and
  Apple Mail collapse it visually, and contains exactly
  three lines: "Sent by Heinzel on behalf of &lt;Operator
  name&gt;", and the project URL
  `https://github.com/wintermeyer/heinzel`.
- Operator name resolution follows a clear order: per-host
  `Operator name:` in `memory/servers/<host>/memory.md`,
  global `Operator name:` in `memory/user.md`, then Claude
  Code auto-memory (`user_profile.md` front-matter `name:`),
  `git config --global user.name`, GECOS full name, and
  finally `$USER`. First resolution via the derived sources
  is persisted to `memory/user.md` so future sessions are
  stable and the user can edit the canonical value.
- Per-server memory template extended with optional
  `Operator name:` and `Greeting:` overrides for hosts that
  should sign or close differently than the global default.
- `memory/user.md.example` grew commented
  `# Operator name: Your Full Name` and
  `# Greeting: <closing text>` hints so new installs
  discover both knobs during onboarding.
- Why: recipients of Heinzel emails had no indication that
  the message was sent automatically, no link to the
  project, and no record of which person asked Heinzel to
  send it — and the tail of the mail read abruptly.
  A two-line greeting plus a short signature covers all
  four without bloating the message.

## 2.4.2 — 2026-04-22

- Extend the MTA class in
  `rules/service-class-check.md` with three
  lightweight members that were missing from the
  v1 list: `msmtp-mta`, `nullmailer`, and `dma`
  (DragonFly Mail Agent). All three claim
  `/usr/sbin/sendmail` via Debian's alternatives
  system and play the same host-level role as
  postfix / exim4 / sendmail / opensmtpd. Without
  this, heinzel would silently install msmtp-mta
  next to an existing postfix.
- Probe updates per OS:
  - Debian/Ubuntu dpkg probe: add `msmtp-mta`,
    `nullmailer`, `dma`.
  - RHEL/Fedora/SUSE rpm probe: add `msmtp`
    (upstream RPM name, includes the sendmail
    shim) and `nullmailer`. `dma` is not commonly
    RPM-packaged, skipped.
  - FreeBSD pkg probe: add `msmtp*`, `nullmailer*`,
    `dma*`.
  - macOS brew probe: add `msmtp` to the members
    array.
- Option (c) ("run both side by side") remains
  available for the MTA class — two MTAs on
  different routes (e.g. postfix on port 25 plus
  msmtp-mta as an egress-only relay) is a
  legitimate configuration, unlike the time-sync
  and firewall classes.
- Why: found during 2.3.0 (heinzel-email) end-to-
  end validation on a fresh Debian 13 VM. The
  skill's 5R install path ran `apt-get install
  msmtp-mta bsd-mailx`, which 2.4.1's probe
  failed to catch because msmtp-mta wasn't a
  known class member. This release closes the
  loop.

## 2.4.1 — 2026-04-22

- Extend `rules/service-class-check.md` with four
  additional service classes:
  - **Time sync** — chrony, ntp (ntpd), openntpd,
    systemd-timesyncd
  - **DNS resolver** — unbound, bind9, dnsmasq,
    pdns-recursor, knot-resolver, systemd-resolved
  - **Firewall manager** — ufw, firewalld (frontends
    only; raw nftables/iptables are backends and not
    class members)
  - **Container runtime** — docker.io, docker-ce,
    moby-engine, podman, containerd.io
- Add a "systemd-provided members" subsection that
  distinguishes `systemd-timesyncd` and
  `systemd-resolved` from package-installed members.
  Those two ship inside systemd and are only a
  conflict when their unit is `is-active`, not just
  because the files exist.
- Flag option (c) ("run both side by side") as
  incoherent for two of the classes: time sync (only
  one daemon can own the clock) and firewall manager
  (two frontends stomp each other's rules and can
  cut off SSH). For those classes, present only
  options (a), (b), and (d).
- Add a FreeBSD note that `ntpd` and `local_unbound`
  ship in base rather than as packages, so the
  pkg-info probe has to be paired with a
  `service -e` check for them.
- Why: after 2.4.0 shipped with three classes
  (web/DB/MTA), these four cover the next tier where
  silent conflicts are common — systemd-timesyncd
  overridden by an installed chrony, docker.io
  pulled in on a podman host, ufw installed
  alongside firewalld, etc.

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
  `Mail:` / `Alert email:` lines convention already in use.
  No new memory subsystem.
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

Why: on a managed host, Claude ran `df -h` in
response to a disk-space question and skipped
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
