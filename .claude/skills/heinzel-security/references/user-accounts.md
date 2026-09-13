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
awk -F: '($3 < 1000) && ($7 ~ /sh$/) \
  {print $1 ":" $7}' /etc/passwd
```

Practically every interactive shell ends in `sh` — `bash`, `sh`,
`dash`, `zsh`, `ksh`, `csh`, `tcsh`, `fish` — while every inert
shell ends in something else (`nologin`, `false`, `sync`). So
matching `sh$` selects the accounts that can log in without
naming a single inert shell.

When a shell does not follow that rule (`ksh93`, a wrapper
script, a runtime as the shell), list every system account and
judge the shells directly:

```bash
awk -F: '($3 < 1000) {print $1 ":" $7}' /etc/passwd
```

**Two traps this command shape avoids — do not "simplify" it
back:**

- awk's `!~` (not-match) does not survive SSH + zsh quoting
  layers: zsh reads `!` as history expansion and mangles it,
  even inside quotes.
- Excluding inert shells by name means writing their names, and
  two of those names (`shutdown`, `halt`) are power-off commands.
  heinzel's own `guard-taboos.sh` hook scans the whole command
  string and cannot tell a regex alternative from an invocation,
  so it denies the command — correctly, by its own design. The
  positive `sh$` match names no inert shell at all and passes.

No root needed.

Expected exceptions: `root` (has `/bin/bash` or `/bin/sh`), and
on Debian/Ubuntu `postgres` (the `postgresql-common` package
ships it with `/bin/bash`). Flag all others.

- Any unexpected system account with a login shell → **WARN** per
  account
- Only expected exceptions → OK
