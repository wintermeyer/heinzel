# Verify a Finding Before You Report or Escalate

A **finding** is any conclusion about the system
you are about to hand to someone: "X is gone", "the
reboot deleted Y", "service Z is broken", "the data
moved to the wrong disk". Noticing the symptom is
step one. Confirming it against ground truth is step
two, and step two is **mandatory** before you report
the finding, act on it, or escalate it (to the user,
to another operator, or to a root session).

Skipping step two turns a stale assumption into a
false alarm. A directory that seems to have
"vanished at the reboot" may simply never have lived
where you remembered: the application writes
somewhere else, the path was a mount that was never
persistent, or your note is from an older layout.
Memory and notes go stale; the live system is the
source of truth.

This is the same discipline as **Verify Before
Running** (don't trust training data for command
*syntax*) and **Never fabricate server facts**
(`CLAUDE.md`), applied to *conclusions* rather than
to raw facts or commands.

## Before concluding, run these checks

### 1. Resolve the real location from config

Never assume where an app keeps its data, config, or
logs from your notes, a past layout, or training
data. Ask the running system where it actually
points:

- the service's environment and unit:
  `systemctl cat <unit>`, its drop-ins,
  `EnvironmentFile`, `Environment=`,
  `WorkingDirectory=`
- the app's own config file
- a search: `grep -rIn '<VAR_OR_PATH>' /etc /opt …`,
  `find / -xdev -name '<state-file>' 2>/dev/null`

Paths move: migrations, redeploys, refactors. A
stale path in your head is not evidence of loss.

### 2. Prove absence

"Not where I expected" is not "gone". Confirm the
thing is absent everywhere it could be, and check
whether it ever existed where you think it did:

- current mounts: `findmnt <path>`, `df`,
  `/proc/mounts`
- was it ever a mount? `/etc/fstab`, plus the
  systemd mount-unit name in the journal
  (`journalctl | grep '<escaped-path>.mount'`). A
  mount that fails to reappear usually leaves an
  **empty mountpoint** behind; a directory entry
  that is simply not there is a different failure
  with a different cause.
- the parent directory's mtime (when did it last
  change? a removal bumps it)
- with the needed privilege, the filesystem's own
  record: `dumpe2fs -h <dev>` / `tune2fs -l`
  ("Last mounted on"), which tells you what a disk
  really is before you guess.

### 3. Don't assert a cause you haven't shown

"X vanished *since* the reboot" or "*because of* the
upgrade" is a claim, not an observation. Report
causation only when records show X was present
before the event and absent after. Otherwise state
it honestly: "X is not present; last confirmed
present <when / never>; cause not established."
Correlation with a reboot or an upgrade is a lead to
check, not a conclusion to ship.

### 4. Exhaust read-only checks before escalating

If you lack a privilege and are about to escalate —
ask the user, email the operator, defer to a root
session — first run every read-only check you *can*
do. The config and env lookups, `find`, `grep`, the
journal, and `findmnt` all need no root. Escalate
with verified facts and one precise, minimal ask
("need root for `blkid` on `<dev>` to read its
filesystem type"), never with an unverified,
alarming guess. Many "I need root" escalations
dissolve once step 1 is done, because the data was
never missing — only the assumed path was wrong.

This matters most for a least-privilege heinzel that
runs as a normal user and escalates by asking rather
than acting: a verified, narrow request costs the
operator one grant; an unverified scare costs a
whole investigation.

## When the finding survives all four

Then it is real. Report it plainly, with the
evidence that makes it real, and act or escalate.
Verified problems get fixed; unverified ones get
checked first — never the other way around.
