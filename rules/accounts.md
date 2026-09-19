# Accounts and Privileges

A key or certificate proves who logs in. Whether the
account exists, where it comes from and what it may
do is decided on the host: by the name service
(`nsswitch`), PAM and `sudo`. This rule finds out how
a host does that, records it, and says what it means
for heinzel's own privileges.

Covers Linux, FreeBSD and macOS. Everything below is
read-only; changes are in "Changing accounts or sudo
rules".

## When to check

- On the first privileged action after onboarding,
  together with the sudo probe
  (`rules/privilege-escalation.md`).
- Before connecting a server to an SSH CA: a
  principal needs an account (Certificate logins).
- Before creating an account, a group or a sudo rule.
- In a security audit and a fleet audit.

Run sections 1–3 in one SSH call; the root-only
parts need root or `sudo -n`. Read `Accounts:` from
server memory on later connections instead of
probing again.

## 1. Where accounts come from (no root)

**Linux and FreeBSD** use `nsswitch.conf` (openSUSE
Tumbleweed: `/usr/etc` too, `rules/suse.md`):

```bash
for f in /etc/nsswitch.conf /usr/etc/nsswitch.conf; do
  [ -e "$f" ] || continue
  echo "$f"
  grep -E '^(passwd|group|shadow|sudoers|netgroup):' "$f"
  break
done
```

| Source in `passwd:` | Accounts from |
|---|---|
| `files`, `compat`, `systemd` only | local files |
| `sss` | SSSD (AD, FreeIPA, LDAP) |
| `ldap` | `nslcd` (nss-pam-ldapd) or `nss_ldap` |
| `winbind` | Samba winbind (AD) |
| other (`kanidm`, `oslogin`, …) | an agent: `accounts-on-demand.md` |

An entry is not proof of a directory. On Debian,
installing `libnss-sss` adds `sss` to the file even
when no SSSD is configured. Confirm the daemon runs:

```bash
systemctl is-active sssd nslcd winbind 2>/dev/null
command -v realm >/dev/null && realm list
command -v authselect >/dev/null && authselect current
```

On FreeBSD: `service -e | grep -E 'sssd|nslcd'`
(`security/sssd2`, `net/nss-pam-ldapd`; base has no
LDAP source).

`realm list` names the domain, `server-software`
(`active-directory`, `ipa`), `client-software` and
`login-policy`. `allow-realm-logins` lets every
account of the domain log in; `allow-permitted-logins`
only the `permitted-logins` and `permitted-groups`.
`realm` needs the realmd service; no output means no
realm was joined with it, not that there is no
directory. `sssctl domain-list` and
`sssctl domain-status <domain> -o` (online or
offline) need root.

**Who may log in** from the directory: SSSD's
`access_provider` defaults to `permit`, every
directory user; `realm join` and the IPA client
usually set it, so read the file. `simple` with
`simple_allow_groups`, `ldap` with
`ldap_access_filter`, `ipa` (HBAC) and `ad` restrict
it; realmd sets it with `realm permit -g <group>`.
sshd runs this PAM account check for key and
certificate logins too. Root only, and filtered by
key: `sssd.conf` holds the bind password.

```bash
grep -rhE '^[[:space:]]*(access_provider|simple_allow|ldap_access)' \
  /etc/sssd 2>/dev/null
```

A person removed from the directory may still
resolve from SSSD's cache for a while.

**Where one account comes from.** The first source
in `passwd:` that knows a name answers:

```bash
grep '^<name>:' /etc/passwd
getent -s <source> passwd <name>
```

In `/etc/passwd`: local (section 5). Otherwise
`getent -s` (glibc; exit 2 = not there) names the
source. Details for one account: `sssctl user-show
<name>` (SSSD, root), `wbinfo -i <name>` (winbind),
`userdbctl user <name>` (systemd), the LDAP server in
`/etc/nslcd.conf` (nslcd), the vendor's tool (an
agent). FreeBSD has no `getent -s`: found by `getent`
but not in `/etc/passwd` means the directory.

**macOS** uses Open Directory:

```bash
dscl /Search -read / CSPSearchPath
dsconfigad -show
```

Only `/Local/Default` → local accounts.
`/Active Directory/…` → bound to AD; `dsconfigad
-show` lists the domain and the AD groups with local
admin rights. `/LDAPv3/<server>` → an LDAP directory.
A `/Platform SSO` entry appears on current macOS
without Platform SSO being configured; it proves
nothing on its own.

One account: `dscl . -read /Users/<name> RecordName`
succeeds for a local one; otherwise
`dscl /Search -read /Users/<name> RecordName` finds it
in a directory node.

## 2. Home directory at first login

A directory account has no home until something
creates it. Without one, its `~/.ssh/authorized_keys`
cannot exist, so key logins fail; certificate logins
(`TrustedUserCAKeys`) and keys from the directory
(`AuthorizedKeysCommand`, e.g.
`sss_ssh_authorizedkeys`) still work, and the session
starts in `/`.

```bash
grep -RlE 'pam_(oddjob_)?mkhomedir' /etc/pam.d/ \
  /usr/lib/pam.d/ 2>/dev/null
```

`-R`, not `-r`: authselect (RHEL, Fedora) makes the
files in `/etc/pam.d` symlinks, which `-r` skips.

- **RHEL, Fedora:** `authselect current` lists
  `with-mkhomedir`; it needs `oddjobd` running
  (`systemctl is-active oddjobd`).
- **Debian, Ubuntu:** `pam_mkhomedir.so` in
  `/etc/pam.d/common-session`, enabled with
  `pam-auth-update --enable mkhomedir`.
- **FreeBSD:** the `security/pam_mkhomedir` port,
  listed in `/etc/pam.d/sshd`.
- **macOS:** the AD plugin creates local homes
  unless `-localhome` was disabled (`dsconfigad
  -show`).

Home directories on NFS or autofs are shared, not
created: check `mount` and `/etc/auto.master`.

**Where homes live** is not always `/home`: macOS
keeps them in `/Users` (its `/home` is an automount
point), and SSSD puts directory users where
`fallback_homedir` or `override_homedir` says (a `%d`
adds a level). The home roots are the parent
directories of the homes section 5 lists, plus the
SSSD template (root):
`grep -rhE '^[[:space:]]*(fallback|override)_homedir' /etc/sssd`.

## 3. The sudo model

**Where rules come from.** Files, plus a directory
when the `sudoers:` line in `nsswitch.conf` names one
(`sss` for SSSD and FreeIPA, `ldap` for sudo's own
LDAP). No `sudoers:` line means files only. The
files are the main `sudoers` and whatever it pulls
in with `@includedir` (`#includedir` in older files),
usually `/etc/sudoers.d/`; most rules live there, one
file per package or purpose.

The paths differ by OS and build (`/usr/local/etc`
on FreeBSD, `/usr/etc` on openSUSE Tumbleweed), so
take them from sudo, not from memory. The files are
mode `0440`: this needs root or `sudo -n`.
`visudo -c` names every file sudo parses, and a file
it complains about too; read the rules from those
with `grep`, never through an interpreter:

```bash
sudo -V | grep -i '^sudoers path'
V=$(visudo -c 2>&1)
printf '%s\n' "$V"
F=$(printf '%s\n' "$V" | sed -n 's|^\(/[^:]*\): .*|\1|p')
[ -n "$F" ] && grep -HvE '^[[:space:]]*(#|$)' $F
```

A file in an `@includedir` directory whose name
contains a `.` or ends in `~` is skipped without a
word: `visudo -c` does not list it, and its rules
are not in effect.

**Who is in the groups.** Most sudo rights come
through a `%group` rule, not one per user: `%sudo` on
Debian and Ubuntu, `%wheel` on RHEL and Fedora,
`%admin` on macOS. Only the groups the rules name
count. Members come from two places, the group's
member list and the accounts whose primary group it
is (the GID is field 3 of the `getent` line):

```bash
getent group <group>
awk -F: '$4 == <gid> {print $1}' /etc/passwd
```

macOS: `dscl . -read /Groups/<group> GroupMembership`.
For one person, `id -Gn <user>` lists all their
groups, directory groups included. A directory group
may show no members through `getent` (SSSD does not
enumerate by default); do not count it as empty.

**Effective rules for one account**, directory rules
included — the only view that shows those:

- As root: `sudo -l -U <user>`.
- As the account itself: `sudo -n -l`. It works
  without a password only when at least one rule has
  `NOPASSWD`; `sudo -n -ll` also names the file each
  rule comes from.

**What to note per user or group:**

- `ALL` or a list of commands.
- `NOPASSWD` on `ALL`, on some commands, or none.
- Run-as other than root.
- A password where people log in only with a
  certificate: it works only if PAM checks a password
  they have (e.g. the directory's through SSSD).
  Otherwise the user chooses: `NOPASSWD` for that
  group only (a certificate is then root for its
  lifetime), or each person sets a password.
- `Defaults !authenticate` (no password for anyone),
  `targetpw` or `rootpw` (the target's or root's
  password; openSUSE ships `ALL ALL=(ALL) ALL` with
  `targetpw`).

**Directory rules reachable?** With `sudoers: … sss`,
`sssctl domain-status <domain> -o` (root) must say
online. Offline, accounts and sudo rules are only as
current as SSSD's cache.

## 4. Which model a host uses

- **Role account:** admins log in as `root` or one
  shared admin account. With certificates, the
  principals decide who may; the key ID in the log
  shows who it was. Few or no personal accounts.
- **Directory:** personal accounts from a directory
  (section 1), sudo from the directory or from a
  directory group in the local files.
- **Local:** personal accounts in `/etc/passwd`
  (macOS: `/Local/Default`), created on each host,
  sudo through a local group (section 3). With a CA,
  a small team gets the same account name and UID on
  every host, the principal is the name, and a roster
  in `memory/network.md` lists them (Changing
  accounts or sudo rules → Team accounts).
- **Agent:** vendor software on the host serves or
  creates the accounts and usually handles sudo
  itself. Serving: its own source in `passwd:`.
  Creating: local accounts it adds and removes, e.g.
  Pangolin's Newt auth daemon (`useradd`, a sudo file
  `/etc/sudoers.d/90-pangolin-<user>`).

A host can mix them, e.g. a directory host with one
local break-glass account. Record the model that
admits the admins and name the exception.

Without creating accounts beforehand (an IdP issues
short-lived certificates): `rules/accounts-on-demand.md`.

## 5. Local accounts

The people's accounts in the local files: UID from
`UID_MIN` in `/etc/login.defs` (default 1000; macOS
501) up to below `nobody`. System accounts below
that: `heinzel-security` →
`references/user-accounts.md`. One call: name, UID,
home, shell, groups, then which of them have
`authorized_keys` (root for other accounts' `.ssh`;
`$SUDO` is empty as root, `sudo -n` otherwise):

```bash
min=$(sed -n 's/^UID_MIN[[:space:]]*//p' /etc/login.defs 2>/dev/null)
min=${min:-1000}; K=
while IFS=: read -r u x uid gid gecos h sh; do
  [ "$uid" -ge "$min" ] 2>/dev/null && [ "$uid" -lt 65534 ] || continue
  echo "$u uid=$uid home=$h shell=$sh groups=$(id -Gn "$u" | tr ' ' ,)"
  K="$K $h/.ssh/authorized_keys"
done < /etc/passwd
[ -n "$K" ] && $SUDO ls -l $K 2>/dev/null
```

No `awk` here: the guard denies an interpreter next
to a key path. Without root or sudo, `ls` sees only
the homes it may read: report the others' keys as
unchecked, not as absent. macOS: `dscl . -list /Users UniqueID`,
then `dscl . -read /Users/<name> NFSHomeDirectory
UserShell` per account.

On a directory host, ask the directory for all local
names at once: `getent -s <source> passwd <name>...`
(section 1) prints the ones it knows. Such a name
exists twice, and only the first source in `passwd:`
(usually `files`) can log in with it.

An account without a password (`!` or `*` in the
shadow field) still logs in with a key or
certificate: sshd refuses a locked account (`!`)
only with `usepam no` (`sshd -T`); there, `*` instead
(`usermod -p '*' <name>`).

## Certificate logins

A certificate proves who logs in, not that the
account exists. sshd looks the account up through NSS
before it checks the certificate: an unknown name is
`Invalid user`, the certificate never counts, and
`AuthorizedKeysCommand` and
`AuthorizedPrincipalsCommand` run only for accounts
that resolve. `getent passwd <name>` must answer
before a first login.

- `AuthorizedPrincipalsFile none` (sshd's default):
  the certificate must name the account itself.
- A principals file per account (`…/%u`): an account
  without its file accepts no certificate. On a host
  whose people come from a directory that locks out
  everyone without a file: keep `none` there, and
  files only for role accounts (`Match User`).
- With `none`, a principal named like a local account
  (`root`, `deploy`) logs in as that account: the CA
  must never sign such names for people.

Changes across hosts (connecting a directory, team
accounts): per host one call with ask, backup and a
fresh access test; a progress line in
`memory/network.md` until no host is pending; stop at
the first failed test; unreachable hosts are not done.

## Memory

One line in `memory/servers/<hostname>/memory.md`:

```markdown
- Accounts: directory (SSSD, AD example.com,
  access simple:%linux-admins), sudo from sss +
  %linux-admins ALL in /etc/sudoers.d/admins,
  mkhomedir on; local: breakglass
- Accounts: role (root via principals), sudo unused
- Accounts: local (team roster, certificates),
  sudo %sudo NOPASSWD
```

Three hosts, one line each.

Mark what a probe could not see:
`sudo rules unchecked (needs root)`. heinzel's own
sudo line stays separate (`- Sudo:`,
`rules/privilege-escalation.md`).

## What it means for heinzel

- **Role account:** heinzel logs in as that account
  (`rules/ssh-user.md`); root is either the login
  itself or `sudo` from the shared account.
- **Directory or local:** heinzel logs in as the
  user's personal account and depends on `sudo -n`:
  `rules/privilege-escalation.md` (passwordless,
  mixed mode, or unusable).

## Changing accounts or sudo rules

Ask first; both are privilege changes.

- **Directory host:** accounts, groups and directory
  sudo rules belong in the directory. heinzel does
  not write to it; it tells the user what to create
  there. Do not create a local account instead
  unless the user asks for a local one (e.g.
  break-glass or a service account).
- **Agent-managed accounts** and their sudo files
  belong to the agent: change them on its side, not
  by hand on the host, where the agent would undo it.
- **Sudo files:** as in `rules/deployment.md` →
  Restricted Sudo (one file in `sudoers.d`, checked
  with `visudo -c -f`, backed up). Name it without a
  `.`, then run `visudo -c` for the whole set: a
  file it rejects breaks sudo for everyone. Confirm
  with `sudo -l -U <user>`.

**Team accounts** (a few people who rarely change, a
CA, no directory): the same local account on every
host, created once as root, principal = account
name, which `AuthorizedPrincipalsFile none` admits
(Certificate logins). The
person, and heinzel for them (`rules/ssh-user.md`),
work as that account; root stays for break-glass.

- **Roster** under `## Team accounts` in
  `memory/network.md`, one line per person, e.g.
  `- janedoe: uid 1101, groups sudo`. The same UID on
  every host (free: `getent passwd <uid>` prints
  nothing), outside any directory or IdP range.
- **Create** per host (Certificate logins → Changes
  across hosts), in one call with the check, and the
  sudo group a
  rule names (section 3). No password (section 5).
  Linux, then FreeBSD:

  ```bash
  useradd -m -u <uid> -s /bin/bash -c "<Full Name>" \
    -G <group> <name> && id <name>
  pw useradd <name> -m -u <uid> -s /bin/sh \
    -c "<Full Name>" -G wheel -w no && id <name>
  ```

  macOS accounts come from the Mac's own management;
  heinzel does not create them. Then a fresh login
  with that person's certificate.
  Sudo for accounts without a password: section 3.
- **Remove:** revoke the person's certificates at the
  CA, or in the hosts' `RevokedKeys` list, then per
  host `userdel <name>` (`pw userdel` on FreeBSD); the
  home stays unless the user wants it gone (`-r`).
  Update the roster.
