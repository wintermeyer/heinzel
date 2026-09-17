# User Account Hygiene — Linux

## Empty Password Accounts

Check for accounts with empty password fields in `/etc/shadow`.
Requires root.

```bash
awk -F: '($2 == "") {print $1}' /etc/shadow
```

- Any account found → **CRITICAL** per account
- No accounts → OK

**Unprivileged fallback:** this check cannot be performed without
root. Add to "Skipped" section.

## Multiple UID 0 Accounts

```bash
awk -F: '($3 == 0) {print $1}' /etc/passwd
```

No root needed — `/etc/passwd` is world-readable.

- Only `root` has UID 0 → OK
- Any other account with UID 0 → **CRITICAL**

## System Accounts with Login Shells

Check for system accounts (UID < 1000) that have interactive
login shells.

```bash
awk -F: '$3 < 1000 {
  s = $7; sub(/.*\//, "", s)
  inert = (s == "nologin" || s == "false" || s == $1)
  if (s ~ /sh$/ || inert == 0) print $1 ":" $7
}' /etc/passwd
```

Inert shells are `nologin`, `false`, and a binary named after
its account (`sync`, on RHEL also `shutdown` and `halt`), which
`s == $1` catches without spelling a name. A shell ending in
`sh` is reported regardless, so an account named after its
shell (`bash` with `/bin/bash`) cannot hide.

**Three traps this shape avoids; do not "simplify" it back:**

- Printing only shells that end in `sh` fails open: `ksh93`,
  `python3` and an empty field (which means `/bin/sh`) go
  unreported. A security check reports what it does not
  recognize.
- A regex of inert shell names writes `shutdown` and `halt`
  into the command, and `guard-taboos.sh` denies it (see
  `CLAUDE.md`, Critical Safety Rules).
- awk's `!~` (and any `!`) does not survive SSH + zsh quoting:
  zsh reads `!` as history expansion, even inside quotes.

No root needed.

Expected exceptions: `root` (has `/bin/bash` or `/bin/sh`), and
on Debian/Ubuntu `postgres` (the `postgresql-common` package
ships it with `/bin/bash`). Flag all others.

- Any unexpected system account with a login shell → **WARN** per
  account
- Only expected exceptions → OK
