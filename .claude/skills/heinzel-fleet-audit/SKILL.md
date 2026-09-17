---
name: heinzel-fleet-audit
argument-hint: "[hostname1 hostname2 ...]"
description: Compare key policies across all servers in
  memory/servers/ to surface silent drift. Makes no configuration
  changes; writes one audit-trail line to each host's journal.
  Probes unattended-upgrades, sshd effective config, firewall
  posture, MTA, time sync, and auto-reboot behaviour. Use when
  the user asks to "fleet audit", "vergleiche alle server",
  "policy drift check", "are my servers configured the same?",
  or after a fix on one host to find which others carry the
  same bug.
---

# heinzel-fleet-audit

Cross-server policy audit. Heinzel knows every host
individually but has nothing that holds hosts against each
other. This skill closes that gap by probing the same set of
settings on every server in `memory/servers/` and rendering a
side-by-side comparison so silent drift becomes visible.

**No configuration changes.** The audit never alters any
host's configuration. The only write is a single audit-trail
line to each host's system journal (step 6 below). Acting on
findings is a separate step (heinzel-housekeeping for
per-host fixes, or manual edits with explicit user approval).

**Never run automatically** — only on explicit user request.

## When to use

- "Run a fleet audit"
- "Vergleiche die Policies auf allen Servern"
- "Drift check across the fleet"
- After fixing a config bug on one host: "which other hosts
  have the same problem?"

Do NOT auto-invoke for generic phrases like "check my
servers" — that maps to single-host housekeeping.

## Workflow

1. **Discover hosts.** List directories under
   `memory/servers/` whose name resolves to a real host
   (skip placeholders like `server1.example.com` and
   `192.168.64.20` unless the user names them explicitly).
   The user may pass an explicit subset as arguments — in
   that case audit only those.

2. **Resolve SSH users.** Read `memory/user.md` for the
   per-host SSH user. Hosts without a mapping go on a
   "skipped: no SSH user known" list (do not prompt — just
   report).

3. **Probe in parallel.** For each in-scope host, run the
   probes from `references/probes.md` in a single batched
   SSH command, with the standard options from `CLAUDE.md` →
   SSH Options.
   Hosts that time out or refuse the connection go on a
   "skipped: unreachable" list.

4. **Render comparison.** Build one table per probe category
   using the format in `references/output-format.md`. Hosts
   are columns, settings are rows. Cells that differ across
   columns get visual emphasis.

5. **Surface drift.** After the tables, emit a short "Drift
   detected" section that lists each disagreement and the
   recommended fix (link to the relevant rule or skill). Do
   not change anything.

6. **Log to the system journal** on each audited host:

       logger -t heinzel "fleet-audit: read-only policy probe"

   (One line per host — this is an audit trail, not a
   change record.)

7. **No memory updates.** The audit is a snapshot; it does
   not own server state. If the audit uncovers a memory
   file that contradicts the live config, mention it in
   the "Drift detected" section so the user can decide
   what to fix.

## References

Read on demand:

- `references/probes.md` — the exact commands to run per
  category (UA, sshd, firewall, MTA, time, auto-reboot).
- `references/output-format.md` — table layout and the
  "Drift detected" section format.

## Scope and limits

- Linux (Debian family) is fully covered. RHEL/SUSE
  probes share the same shape but use `dnf`/`firewalld`/
  `zypper` equivalents. macOS hosts are skipped with a
  "macOS not yet supported" note — covering them is a
  separate effort.
- The audit does not check that running services are
  healthy (that is housekeeping's job). It only compares
  declared policy.
- BatchMode SSH means no password prompts. Hosts that need
  a passphrase get skipped — fix the agent setup
  separately.
