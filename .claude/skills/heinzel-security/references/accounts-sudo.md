# Account Source and Sudo Rules — Linux, FreeBSD, macOS

Probes and what their output means: `rules/accounts.md`,
sections 1–3, in one call. This file only says what to
report, plus the two probes that are audit-only.

## Account source

Always one line in Checks, e.g. `OK — local files` or
`OK — SSSD, AD example.com, online`.

- A directory is configured (`realm list` shows a realm, or
  `authselect current` names the `sssd` or `winbind`
  profile) but its daemon is not active → **WARN**:
  directory accounts cannot log in.
- `sssctl domain-status <domain> -o` says offline →
  **WARN**: accounts and sudo rules come from SSSD's cache.
- Every directory user may log in (`allow-realm-logins`,
  or `access_provider` unset or `permit`;
  `rules/accounts.md` → 1) → **WARN**; name the domain.
- `sss` or `ldap` in `nsswitch.conf` with no daemon and no
  realm → OK, note it in the line.

## Sudo rules (root)

- `ALL ALL=(ALL) ALL` without `Defaults targetpw` or
  `rootpw` → **CRITICAL**: every account becomes root with
  its own password. With `targetpw` → **INFO**.
- `NOPASSWD: ALL` for people who log in with a key or
  certificate (one account or an admin group) → **INFO**,
  with the names (`rules/accounts.md` → 3): a deliberate
  trade, their key is a root key. Distributions ship
  `%sudo`/`%wheel` with a password; NOPASSWD comes from
  cloud-init's default user, heinzel's account, or
  accounts without a password.
- `NOPASSWD: ALL` for an account a service or app runs
  as (`deploy`, `www-data`, …) → **WARN**: a hole in the
  app is root.
- `NOPASSWD: ALL` for a group from the directory →
  **WARN**: whoever manages the group decides who is
  root. It may list no members here; say "members from
  the directory", never "0".
- `Defaults !authenticate` → **WARN**: every rule,
  including those meant to ask, runs without a
  password.
- A `NOPASSWD` command that can start a shell or write any
  file (editor, pager, shell, interpreter, `find`, `tar`,
  `cp`, `tee`) → **WARN**: the rule is as good as `ALL`.
- A file skipped by `@includedir` → **WARN**: its rules are
  not in effect.
- `sudoers:` names `sss` or `ldap` and the directory is
  unreachable (daemon inactive, domain offline) → **WARN**:
  admins whose rules live there lose sudo, or keep rules
  the directory has already revoked.
- Rules from a directory → **INFO**: the local files show
  only part; list effective rules per admin.
- Members of each other group with `ALL` (with a password)
  → **INFO**, with names. A member the user does not
  recognize: ask.

macOS ships `%admin ALL = (ALL) ALL` (with password) → OK.
AD groups with local admin rights (`dsconfigad -show`) →
**INFO**, name them.

## Local accounts

Every host. The list and the key check come from
`rules/accounts.md` → 5. One line in Checks with every
local account and what it can do, e.g.
`Local accounts  INFO — 3: anna (sudo, keys), bert, deploy
(keys)`. "sudo": member of a group a rule names, or
named in one (`rules/accounts.md` → 3); a login shell is one that
"System Accounts with Login Shells" in
`references/user-accounts.md` does not call inert.

With a team roster (`rules/accounts.md` → Team
accounts): a local account not on it → **WARN** (nobody
recorded it), unless an agent manages it
(`rules/accounts.md` → 4; name the agent); a roster
account missing or with another UID → **INFO**.

On a directory host, also:

- A local name that the directory knows too → **WARN**
  (`rules/accounts.md` → 5).
- A local account with sudo, or with a login shell and
  `authorized_keys`, not named as break-glass in the
  `Accounts:` memory line → **WARN** per account: a way in
  that the directory does not control or revoke.

Homes whose owner no longer resolves (a person removed
from the directory, or `userdel` without `-r`) →
**INFO**, count and names. Only with the directory
reachable (`rules/accounts.md` → 3), else every owner
looks gone. Never delete one without the user.

Search the home roots (`rules/accounts.md` → 2; one
level deeper where SSSD's template has `%d`). `-H`: a
root may be a symlink.

```bash
find -H <root>... -mindepth 1 -maxdepth 1 -nouser
```

Say when it last logged in only from a record (`last`,
`lastlog2` where installed). No record is "last login
unknown", not "stale" (`rules/verify-before-reporting.md`).
