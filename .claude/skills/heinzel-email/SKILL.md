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
   - Body: plain text. Verbatim user content, followed by
     the Heinzel closing (see **Greeting** and **Signature**
     below). If the user asks to send command output, run the
     command and embed stdout/stderr inline in a fenced block
     above the closing.

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

   **Greeting.** Before the signature, every outgoing
   message carries a fixed two-line human close, separated
   from the body above by one blank line and from the
   signature below by another blank line:

   ```
   Viele Grüße
   Heinzel
   ```

   Heinzel is the author of the closing — not the operator.
   The operator attribution lives in the signature block
   below. Keep the greeting fixed across languages; the
   subject and body may be English, the "Viele Grüße /
   Heinzel" close stays the tool's voice. Users who want a
   different wording can set a `Greeting:` line in
   `memory/user.md` (global) or
   `memory/servers/<host>/memory.md` (per-host); if present,
   it replaces both lines verbatim (multi-line allowed).
   Per-send instructions ("use 'Mit freundlichen Grüßen'
   this time") always win over memory.

   **Signature.** Every outgoing message ends with a fixed
   three-line signature block, separated from the greeting
   above by one blank line and opened by the RFC 3676
   delimiter `"-- "` (two hyphens, one space, then newline
   — most MUAs collapse the sig visually only when the
   delimiter is exact):

   ```
   -- 
   Sent by Heinzel on behalf of <Operator name>
   https://github.com/wintermeyer/heinzel
   ```

   Keep it to these three lines. No timestamp, no hostname,
   no extra attribution — the subject already names the
   host. Plain text only; no HTML.

   **Resolve `<Operator name>`** in this order, stop at the
   first hit. Never fabricate a name from a short handle
   like `root` or `admin`:

   1. `Operator name:` line in
      `memory/servers/<host>/memory.md` (per-host override,
      rare).
   2. `Operator name:` line in `memory/user.md` (global,
      canonical).
   3. Claude Code auto-memory — the `user_profile.md` file
      referenced from `MEMORY.md`. Take the human name from
      its front-matter `name:` field (strip any suffix like
      ` — user profile`). This is the same auto-memory
      channel step 3 uses for the default email.
   4. `git config --global user.name` on the workstation.
   5. GECOS full name:
      `getent passwd "$USER" | cut -d: -f5 | cut -d, -f1`
      on Linux, `id -F` on macOS/BSD.
   6. `$USER` as a last resort.
   7. If even `$USER` is empty, ask once via the picker and
      persist the answer.

   **Persist on first resolution via 3/4/5/6** — write
   `Operator name: <name>` into `memory/user.md` under the
   existing `# Preferences` section so the next run skips
   the probes and the user can edit the canonical value.
   Do not overwrite an `Operator name:` line that already
   exists; user edits win.

   **From header.** Heinzel mail is machine-generated. Set
   `From: noreply@<sending-host-fqdn>` so recipients see at
   a glance that the mailbox is not monitored:

   - Remote path: `<sending-host-fqdn>` is the per-server
     hostname (the directory name under
     `memory/servers/<host>/`).
   - Local path: `<sending-host-fqdn>` is the workstation's
     FQDN (`hostname -f`, fall back to `hostname`).

   The `noreply@…` mailbox does **not** need to exist on the
   host. Real bounces follow the *envelope* sender (the
   submitter UID picked in 5R.4, or the current shell user
   on the local path) — that is always a real account that
   can receive MAILER-DAEMON notices. The From header is
   purely visual, for the recipient's MUA.

   A host can pin a different From mailbox by adding a
   `From:` line to its `memory.md` (rare — only useful when
   a host needs a non-`noreply@` identity such as
   `alerts@<host>`).

   **Reply-To header.** Because the From mailbox is unread,
   every Heinzel message MUST carry a `Reply-To:` pointing
   at the human operator, so recipients hitting "Reply"
   land in a real inbox.

   **Resolve `<operator email>`** in this order, stop at
   the first hit. Never fabricate an email from a short
   handle like `root` or `admin`:

   1. `Reply-To:` line in
      `memory/servers/<host>/memory.md` (per-host
      override, rare — e.g. a different person fields
      replies for one specific host).
   2. `Reply-To:` line in `memory/user.md` (global,
      canonical).
   3. Claude Code auto-memory — the "Default email"
      entry under User in `MEMORY.md`. Load the linked
      file and use the address. Same channel step 3 of
      "Resolve recipient" uses.
   4. `git config --global user.email` on the
      workstation.
   5. If still nothing, omit the Reply-To header, tag
      the report **WARN** with the reason, and tell the
      user before sending — don't ship a Heinzel mail
      with no working reply path silently.

   **Persist on first resolution via 3/4** — write
   `Reply-To: <addr>` into `memory/user.md` under the
   `# Preferences` section so the next run skips the
   probes and the user can edit the canonical value.
   Do not overwrite an existing `Reply-To:` line.

   **Anti-auto-reply headers.** Every Heinzel email is an
   automated status message about a managed server. It
   should never fan out out-of-office or vacation replies
   back at the operator. To that end, every outgoing
   message carries this fixed header triple, regardless of
   path or attachments:

   ```
   Auto-Submitted: auto-generated
   Precedence: bulk
   X-Auto-Response-Suppress: OOF, AutoReply
   ```

   - `Auto-Submitted: auto-generated` is the RFC 3834
     signal. Standards-compliant auto-responders
     (vacation(1), Sieve `vacation`, recent postfix,
     well-behaved providers) MUST NOT reply to a message
     that carries it.
   - `Precedence: bulk` is the older sendmail convention,
     still honoured by many legacy responders.
   - `X-Auto-Response-Suppress: OOF, AutoReply` is the
     Microsoft Exchange / Outlook-specific knob that
     suppresses OOF replies and "I'm out of the office"
     auto-responses when the recipient uses Exchange.

   Together the three cover RFC-compliant systems, legacy
   Unix responders, and the Exchange-flavoured world.
   Do not make them per-host configurable; there is no
   realistic Heinzel message that should be treated as
   a normal human email by an auto-responder.

7. **Send.** Because Heinzel always injects custom headers
   (the anti-auto-reply triple above, plus MIME headers
   when attaching), the canonical send path builds the
   full RFC 822 message and pipes it to a sendmail-style
   agent that reads headers from stdin (`-t` mode). This
   is uniform across Postfix, msmtp-mta, exim, opensmtpd,
   and macOS Postfix — they all expose `/usr/sbin/sendmail`
   with compatible `-t` semantics.

   The composed message always has this shape (headers,
   blank line, body + greeting + signature):

   ```
   From: noreply@<sending-host-fqdn>
   Reply-To: <operator email>
   To: <recipient>
   Subject: <subject>
   Auto-Submitted: auto-generated
   Precedence: bulk
   X-Auto-Response-Suppress: OOF, AutoReply
   MIME-Version: 1.0
   Content-Type: text/plain; charset=utf-8

   <body>

   <greeting>

   -- 
   <signature>
   ```

   `From:` and `Reply-To:` are resolved per the rules
   above. If `Reply-To:` could not be resolved (case 5),
   omit the line entirely after warning the user.

   **No attachments.** Pipe the message to
   `sendmail -t -oi` (`-oi` prevents a lone `.` on a line
   from ending input). Prefer the MTA-provided
   `/usr/sbin/sendmail`; fall back to `msmtp -t` when only
   msmtp is present.

   **With attachments**, build a MIME multipart message by
   hand — `text/plain` body plus parts that are
   `text/plain` for `text/*` MIME types (detected via
   `file --mime-type`) and base64-encoded
   `application/octet-stream` otherwise. Heinzel
   constructs the headers (including the anti-auto-reply
   triple) and the boundary itself, then pipes into
   `sendmail -t -oi` (or `msmtp -t` when only msmtp is
   present). This replaces the earlier tool-specific
   shell-outs to `mutt` and `mail -a`: a single code path
   means headers are guaranteed to survive every send.

   **macOS local path.** `/usr/bin/sendmail` on macOS is a
   Postfix compatibility shim and accepts the same `-t`
   invocation, so the same composed message pipes through
   without change. `/usr/bin/mail` is not used for the
   send itself anymore; we only consulted it during the
   5L.1 probe to confirm a working local MTA exists.

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
   fell to case 3). This is the *envelope* sender (the
   Return-Path), which always reflects the submitter UID;
   the visible `From:` header is `noreply@…` and is
   independent — do not flag the mismatch as a problem.

9. **Update `memory.md`** if anything new was learned (source
   chosen, transport discovered or installed, recipient
   added, policy set, sender identity confirmed, per-host
   operator override requested). Use the shape under
   "Per-server memory" below. Only write `…always` or
   `…never` lines when the user explicitly picked them;
   absence means "ask next time". The global `Operator name`
   is persisted to `memory/user.md`, not to per-server
   memory — write a per-host `Operator name:` line only when
   the user asks for a different signer on that specific
   host.

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
- Operator name: <full name>         # per-host override for signature
                                     # (global default in memory/user.md)
- Greeting: <closing text>           # per-host override for the greeting
                                     # (global default in memory/user.md;
                                     # absent = "Viele Grüße / Heinzel")
- From: <mailbox>                    # per-host From override
                                     # (default: noreply@<host>)
- Reply-To: <addr>                   # per-host Reply-To override
                                     # (global default in memory/user.md)
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
