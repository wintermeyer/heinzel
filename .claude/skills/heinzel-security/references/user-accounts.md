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
awk -F: '($3 < 1000) && \
  ($7 ~ /(nologin|false|sync|shutdown|halt)$/) \
  {next} ($3 < 1000) {print $1 ":" $7}' \
  /etc/passwd
```

**Note:** The `!~` (not-match) operator in awk does not survive
SSH + zsh quoting layers — zsh interprets `!` as history
expansion and mangles it. The command above uses positive `~`
match with `next` (skip) to achieve the same result.

No root needed.

Expected exceptions: `root` (has `/bin/bash` or `/bin/sh`). Flag
all others.

- Any unexpected system account with a login shell → **WARN** per
  account
- Only expected exceptions → OK
