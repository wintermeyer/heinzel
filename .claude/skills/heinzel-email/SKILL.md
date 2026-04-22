---
name: heinzel-email
argument-hint: "[hostname] [recipient]"
description: Send an email about a managed server — ad-hoc text
  and/or file attachments. Use when the user asks to "email me
  X", "send X by mail", "mail this to <address>", "attach
  /var/log/foo to an email", or "send a report by email". The
  first email per host asks where to send from (local
  workstation vs the server itself). On the remote path,
  prefers the existing MTA (postfix, sendmail, msmtp,
  mail/mailx) and asks before installing one. Sends as a
  non-root user via `runuser`/`su -`. Attachments check sender
  readability, size, and offer a content preview before
  sending. **Never run automatically** — only on explicit user
  request.
---

# heinzel-email

Send ad-hoc text and file attachments by email about a managed
server. The report content is *about* the server; whether the
mail leaves *from* the server or *from* your workstation is a
per-host preference that's asked once and remembered.

The full heinzel first-connection onboarding pipeline still
applies before any of this runs.

## Workflow

1. **Onboarding pipeline.** Run `rules/first-connection.md` in
   full. No "quick question" exception — even a one-line email
   still goes through blacklist/read-only check, DNS alias
   detection, SSH user lookup, OS detection, server memory
   load, and activity check.

2. **Load overrides.** Apply the heinzel rule-override chain
   (later wins):
   - `memory/custom-rules/heinzel-email.md` if present.
   - `memory/servers/<host>/memory.md` (recipient, source,
     transport, policies — see "Per-server memory" below).
   - `memory/servers/<host>/rules.md` if present.
   `memory/custom-rules/all.md` is already loaded by the
   session-start preflight — do not re-read it.

3. **Resolve recipient.** In order of precedence:
   1. **User said an explicit address** ("send to alice@…",
      "mail it to bob@example.com") → use that. Don't override
      it with stored values.
   2. **Per-server memory** — `memory/servers/<host>/memory.md`
      has an `Alert email:` line (the bremen3 pattern) → use
      that.
   3. **"Send me" shorthand** ("email me", "send me", "mail it
      to me") and the user's default email is recorded in
      Claude Code's auto-memory (the `MEMORY.md` index will
      show a "Default email" entry under User → load that file
      and use the address) → use it without prompting. Still
      write the address back to the per-server `memory.md` as
      `- Alert email: <addr>` on first use so the skill stays
      self-contained for future runs.
   4. Otherwise, ask once via the picker, then persist to
      `memory.md` as in (3).
   - Never guess or invent a recipient.

4. **Consent gate 0 — sender side (local vs remote).** Check
   `memory.md` for `Email source: local | remote`:
   - `local` → jump to step **5L**.
   - `remote` → continue with step **5R**.
   - Missing → ask the user with four options:
     > "First-time email for `<host>`. Send from where?"
     - **Remote — once**: send from the server this time, ask
       again next time.
     - **Remote — always for this host**: write
       `Email source: remote` into `memory.md`, then continue
       to 5R.
     - **Local — once**: send from this workstation this time,
       ask again next time.
     - **Local — always for this host**: write
       `Email source: local` into `memory.md`, then jump to
       5L.

   Why this gate exists: some hosts have great mail
   infrastructure (bremen3's postfix → Google MX); others have
   none and the user may prefer not to install anything on
   them. Either side is a perfectly valid choice the user
   should be able to lock in once.

### 5L. Local-side workflow

**5L.1** Probe the workstation for a local transport:
`command -v mail || command -v mailx || command -v sendmail
|| command -v msmtp`. On macOS, also confirm Postfix is
loaded: `launchctl print system/com.apple.postfix.master`
exits 0.

**5L.2** **No install fallback locally.** If nothing's there,
refuse cleanly: "no mail tooling on this workstation —
install msmtp locally and rerun, or pick remote next time by
deleting `Email source: local` from `memory.md`." Do not
auto-install on the workstation.

**5L.3** Skip Gate A (5R.2) and Gate B (5R.3) entirely —
those are remote-only.

**5L.4** Skip the sender-identity step (5R.4). Local sending
runs as the current shell user.

**5L.5** Continue at the shared step **6 (Compose)**. At step
**7 (Send)** the command runs locally. At step **8 (Verify)**
inspect local logs:
- macOS: `log show --style compact --last 1m --predicate
  'process == "smtpd" OR process == "smtp"'`
- Linux workstation: `journalctl --since "1 minute ago" -t
  postfix` or `tail -50 /var/log/mail.log`

### 5R. Remote-side workflow

**5R.1 Resolve transport** — probe in this order on the
remote host:
- `command -v mail || command -v mailx || command -v s-nail`
- `command -v sendmail`
- `command -v msmtp`
- `systemctl is-active postfix opensmtpd exim4` (any active)

**5R.2 Consent gate A — existing MTA.** If 5R.1 found a
working MTA, check `memory.md` for `Email send policy:
<always|never>`:
- `always` → proceed silently.
- `never` → refuse with the reason; do not send.
- missing → ask:
  > "Use the MTA already on `<host>` (`<detected tool>`)?"
  - **Once** — send this time, ask again next time.
  - **Always** (recommended) — write `Email send policy:
    always` into `memory.md`, send.
  - **Never** — write `Email send policy: never` into
    `memory.md`, abort.

If 5R.1 found a working MTA, skip 5R.3 entirely.

**5R.3 Consent gate B — install a new MTA.** Only reached
when 5R.1 found nothing. Check `memory.md` for `MTA install
policy: <always|never>`:
- `always` → install silently using the OS-family default
  below.
- `never` → refuse; do not install, do not send.
- missing → ask:
  > "No MTA found on `<host>`. Install one?"
  - **Once** — install this time, ask again next time.
  - **Always** — write `MTA install policy: always` into
    `memory.md`, install.
  - **Never** — write `MTA install policy: never` into
    `memory.md`, abort.

Install targets (OS-family defaults):
- Debian/Ubuntu: `apt-get install -y msmtp-mta bsd-mailx`
- RHEL/Fedora: `dnf install -y msmtp s-nail`
- SUSE: `zypper install -y msmtp s-nail`
- FreeBSD: `pkg install -y msmtp` (`mail(1)` is in base)
- macOS as a managed target: do **not** install. Use
  `/usr/bin/mail` if a working Postfix is already
  configured; otherwise refuse cleanly and explain
  (residential macOS rarely sends).

Before installing, surface the deliverability caveat: the
server's IP probably has no PTR/SPF/DKIM, so mail to
gmail-style providers will likely be filtered. Recommend a
smarthost relay (msmtp config) if the user has one. If a
smarthost is configured during install, follow
`rules/backups.md` (back up `/etc/msmtprc` before edits) and
store credentials with `0600 root:root`.

**5R.4 Pick the sender identity — least privilege.** Sending
mail almost never needs root. Choose the UID for the send,
in this order:

1. Current SSH user is non-root → use that user.
2. Current SSH user is root (common: bremen3-style no-sudo,
   or privileged earlier work in the session):
   - First check `memory.md` for an `Email sender:` line —
     if present, use it without re-probing.
   - Otherwise read `memory/user.md` for the preferred
     username.
   - `id <user>` to verify the account exists on the host.
   - `su - <user> -c 'command -v <transport>'` to verify the
     account can invoke the chosen transport. If group perms
     on `/etc/msmtprc` block it, fall to case 3.
   - Drop privileges for the send only:
     `runuser -u <user> -- sh -c '…'` (Linux util-linux) or
     `su - <user> -c '…'` (portable, FreeBSD).
3. If no non-root sender is viable, send as root and tag the
   report **WARN** with the reason. Never invent a user.

The install step (5R.3) still requires root/sudo — that is
the only root-privileged operation in the workflow.

## Shared steps (both 5L and 5R converge here)

6. **Compose.**
   - Default subject: `[heinzel/<short-hostname>] <topic>` —
     even on the local-side path, the subject names the
     server the report is *about*.
   - Body: plain text. Verbatim user content. If the user
     asks to send command output, run the command and embed
     stdout/stderr inline in a fenced block.

   **Attachments** (e.g. "email me /var/log/auth.log"):

   a. Per file, `stat` the path on the side that holds it
      (remote when the path lives on the server; local
      otherwise). Refuse if it doesn't exist; never invent
      paths.
   b. **Readability check.** Confirm the chosen sender UID
      (5R.4 result on the remote path, current shell user on
      the local path) can read it: `[ -r path ]` under that
      UID. If not, do not silently escalate. Show the perms
      (`ls -l`) and ask:
      - skip the file (default offered);
      - copy via root to a temp file `0600 <sender>:<sender>`
        the sender can read, then clean up after send;
      - send as root with a **WARN**.
   c. **Size check.** If the file is over 10 MB, show the
      size and Gmail's 25 MB cap, then ask: send as-is, gzip
      first (recommended for text logs), or skip.
   d. **Sensitive-content nudge.** Log files often contain
      secrets, IPs, hostnames, internal email addresses.
      Show the file's `head -5` and ask "ok to attach?"
      before proceeding. The user can override globally for
      the session by saying "skip the log preview" — do not
      persist that override to memory.
   e. Multiple attachments: repeat a–d per file. Hard cap of
      5 attachments per message in v1; refuse the 6th and
      suggest splitting the mail.

7. **Send.** Choose the command shape based on attachments
   and the available tool.

   **No attachments**, any tool: pipe body via heredoc to
   `mail -s "<subject>" <recipient>` (or `msmtp -t` with
   explicit `From:`/`To:`/`Subject:` headers when only
   msmtp is present).

   **With attachments**, in preference order:
   - `mutt -s "<subject>" -a <f1> [-a <f2> …] -- <recipient>`
     — cleanest, supported on Linux + macOS via brew.
   - `mail -s "<subject>" -a <f1> [-a <f2> …] <recipient>`
     where `mail` is bsd-mailx (Debian) or s-nail (Fedora).
     Verify with `mail --help 2>&1 | grep -- -a` before
     relying on it on this specific host.
   - **msmtp-only fallback**: build a MIME multipart message
     by hand — `text/plain` body plus parts that are
     `text/plain` for `text/*` MIME types (detected via
     `file --mime-type`) and base64-encoded
     `application/octet-stream` otherwise. Heinzel
     constructs the headers and boundary itself, then pipes
     into `msmtp -t`.
   - **macOS `/usr/bin/mail` does NOT support attachments.**
     If the chosen local transport is BSD `mail` and the
     user wants attachments, refuse cleanly and suggest
     `brew install mutt`. Do not auto-install on the
     workstation (same rule as 5L.2).

   Remote path: run under the user chosen in 5R.4, via
   `runuser -u <user> -- sh -c '…'` or
   `su - <user> -c '…'`. Local path: under the current
   shell user.

8. **Verify delivery.** Check the send command's exit code,
   then probe the appropriate mail log from the last minute:
   - Linux remote: `journalctl -u postfix --since "1 minute
     ago" | tail -20` (substitute the active MTA unit), or
     `tail -50 /var/log/mail.log` (Debian) /
     `/var/log/maillog` (RHEL/FreeBSD).
   - macOS local: `log show --style compact --last 1m
     --predicate 'process == "smtpd" OR process == "smtp"'`.
   - Linux workstation local: `journalctl --since "1 minute
     ago" -t postfix` or `/var/log/mail.log`.

   Look for `status=sent` (or msmtp's `delivery
   successful`). Flag `deferred` / `bounced` as **CRITICAL**
   and report verbatim instead of claiming success. Never
   call a send successful on the basis of the command's exit
   code alone.

   On the remote path, confirm the log line's `from=<…>`
   matches the chosen sender user (not root, unless 5R.4
   fell to case 3).

9. **Update `memory.md`** if anything new was learned (source
   chosen, transport discovered or installed, recipient
   added, policy set, sender identity confirmed). Use the
   shape under "Per-server memory" below. Only write
   `…always` or `…never` lines when the user explicitly
   picked them; absence means "ask next time".

10. **Log to changelog** per `rules/changelog.md`:

    ```
    logger -t heinzel "Email to <recipient> from \
        <local|remote/<user>>: <subject>"
    ```

## Per-server memory

No new file. The skill reads and updates lines in the
existing `memory/servers/<host>/memory.md`, extending the
format bremen3 already uses. Policy lines are only written
once the user picks **Always** or **Never**; absence means
"ask next time".

```
- Mail: <transport summary>          # remote path only
                                     # e.g. "postfix + bsd-mailx
                                     #       (outbound via Google MX)"
                                     # or  "msmtp via smtp.fastmail.com:587"
- Alert email: <recipient address>
- Email source: local | remote       # gate 0 — sender side
- Email sender: <username>           # remote path only — non-root user
- Email send policy: always | never  # gate A — use existing remote MTA
- MTA install policy: always | never # gate B — install a new remote MTA
```

The two policy lines are deliberately separate: a user may
be happy to use a mature postfix that's already there
("send: always") but want to be asked every time before
heinzel installs new packages on a different server
("install: ask" = line absent). Mirrors the shape of
`memory/service-policy.md`'s split between `restart-auto`
and `restart-never`.

## References (read on demand)

- `rules/first-connection.md` — the mandatory onboarding
  pipeline.
- `rules/server-memory.md` — server memory file format.
- `rules/changelog.md` — session logging procedure.
- `rules/best-practices.md` — anti-pattern review before
  installing software.
- `rules/backups.md` — config backup before any edit (e.g.
  `/etc/msmtprc`).
