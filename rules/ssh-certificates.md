# SSH Certificates (SSH CA)

OpenSSH certificates are keys signed by a certificate
authority (CA). They work in two directions that have
nothing to do with each other; a host can use either,
both, or neither:

- **Host certificate** (`HostCertificate`): the server
  proves its identity. Clients trust the host CA
  through an `@cert-authority` line in `known_hosts`.
  A timer on the server renews it. Expiry breaks host
  verification for every client that knows the host
  only through the CA.
- **User certificate** (`TrustedUserCAKeys`,
  principals, `RevokedKeys`, or a `cert-authority`
  line in `authorized_keys`): a person or tool logs
  in with a short-lived certificate. The person
  renews it, often daily. Expiry breaks that one
  person's login.

Different failures, owners and renewal, so detect and
record them **separately**. Use a separate CA key for
each direction; one CA signing both is a finding.

Certificates are public and may be printed. The CA
**signing keys** are secrets (`rules/secrets.md`).

## Per operating system

The certificate mechanics are OpenSSH and the same
everywhere; the sshd unit, log and checksum tool are
in `rules/<family>.md`. Specific to certificates:

- **Paths:** `/etc/ssh` on Linux, macOS and the
  FreeBSD base sshd; the FreeBSD `openssh-portable`
  package uses `/usr/local/etc/ssh`.
- **OPNsense, pfSense:** the appliance writes the
  sshd config from its GUI, so CA directives go
  through the GUI. Run the quick probe again after
  every firmware update.
- **macOS:** launchd starts sshd per connection, so a
  new host certificate or CA file takes effect on the
  next login without a reload.
- **Windows** is not a target, only a workstation:
  see "heinzel's own login".

## When to check

- **First connection:** the quick probe, in the same
  call as OS detection (`rules/first-connection.md`).
- Security audit, fleet audit, housekeeping — see the
  skills.
- Before any work on SSH access: users, keys, host
  keys, OS replacement, dual boot.
- When a login or host verification fails with
  `Certificate invalid:` (see Failures).

## Quick probe (no root)

Certificates on disk and the directives in the config
files, both usually world-readable:

```bash
ls /etc/ssh/*-cert.pub /usr/local/etc/ssh/*-cert.pub \
  2>/dev/null
grep -hiE -e '^[[:space:]]*(Match|HostCertificate)' \
  -e '^[[:space:]]*(TrustedUserCAKeys|AuthorizedPrincipals)' \
  -e '^[[:space:]]*(RevokedKeys|CASignatureAlgorithms)' \
  /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf \
  /usr/local/etc/ssh/sshd_config \
  /usr/local/etc/ssh/sshd_config.d/*.conf 2>/dev/null
```

No output: no SSH CA on this host; write nothing. A
hit: write the memory lines (see Memory) from what is
visible and mark the rest `unchecked`. Without root,
this is also all there is of the user CA side.

## Host certificate (no root)

The certificate files are world-readable:

```bash
for c in /etc/ssh/*-cert.pub /usr/local/etc/ssh/*-cert.pub; do
  [ -e "$c" ] || continue
  echo "== $c"
  ssh-keygen -L -f "$c"
  ssh-keygen -lf "${c%-cert.pub}.pub"
done
```

Read from the output (no `awk` in this call: an
interpreter next to an `ssh_host_` path is denied by
the taboo guard):

- **Type** must say `host certificate`.
- **Public key** fingerprint must equal that of the
  host key next to it; otherwise no client can verify
  the certificate.
- **Signing CA:** the host CA. Compare with
  `memory/network.md` and with the user CA.
- **Principals:** every name clients use — FQDN,
  short name, the DNS aliases in server memory.
- **Valid:** `from … to …` or `forever`. Severity:
  - expired, not yet valid, or the public key does
    not match → **CRITICAL**
  - < 7 days left, or less than a third of its
    lifetime (renewal overdue) → **WARN**
  - `forever` → **WARN**: it can only be revoked on
    every client

**Renewal** usually runs on the host: a timer, cron or
launchd job that calls the CA tool (`step ssh renew`,
`vault write …/sign`, a script). No job and an
expiring certificate is the typical outage.

**sshd serves the certificate it loaded at start or
reload** (except macOS, see above). A renewal job
without a reload leaves the old certificate in service
until it expires. Check that the job reloads.

What the server actually presents shows in `-v` of a
fresh login (`CLAUDE.md` → SSH Options). Each one is a
real login, so use it only without root, or add `-v`
to an access test that runs anyway:

```bash
ssh -v -o BatchMode=yes -o ConnectTimeout=5 \
  -o ControlMaster=no -o ControlPath=none \
  USER@HOST true 2>&1 | grep 'Server host certificate'
```

## User CA (root)

One call; `sshd -T` needs root
(`rules/privilege-escalation.md`), runs once, and the
paths come from its output:

```bash
T=$(sshd -T 2>/dev/null)
printf '%s\n' "$T" | grep -e '^hostcertificate ' \
  -e '^trustedusercakeys ' -e '^authorizedprincipals' \
  -e '^revokedkeys ' -e '^casignaturealgorithms '
CA=$(printf '%s\n' "$T" | sed -n 's/^trustedusercakeys //p')
if [ -n "$CA" ] && [ "$CA" != none ]; then
  ssh-keygen -lf "$CA"
  ls -l "${CA%.pub}" 2>&1
fi
RK=$(printf '%s\n' "$T" | sed -n 's/^revokedkeys //p')
[ -n "$RK" ] && ls -l "$RK"
P=$(printf '%s\n' "$T" | sed -n 's/^authorizedprincipalsfile //p')
if [ -n "$P" ] && [ "$P" != none ]; then
  grep -H . "${P%/%u}"/* 2>&1
fi
```

CA trust inside `authorized_keys` needs a call of its
own: the guard denies `ssh-keygen` next to an
`authorized_keys` path (`rules/secrets.md`):

```bash
grep -Hn 'cert-authority' /root/.ssh/authorized_keys \
  /home/*/.ssh/authorized_keys 2>/dev/null
```

- `trustedusercakeys none` and no `cert-authority`
  line: no user CA. No `revokedkeys` line: no
  revocation list.
- **CA signing key on the server:** the `ls` finds a
  file named like the CA key without `.pub` (anything
  but "No such file"). Report the path,
  never read it: whoever holds it can log in
  everywhere the CA is trusted.
- **Principals:** `authorizedprincipalsfile none`
  means a certificate works for the account its
  principals name. With a file (`%u` is the account),
  each line is a principal allowed in as that account.
  Report which principals reach `root`. An
  `AuthorizedPrincipalsCommand` cannot be evaluated
  from outside: name the command and its user.
- **Revocation:** the `ls -l` must show the file (see
  "Working with an existing SSH CA" for why). No
  `RevokedKeys` at all is fine for certificates that
  live hours; a leaked long-lived one stays valid
  until it expires.
- **One CA for both directions:** a user CA
  fingerprint equal to the host certificate's
  signing CA.

`sshd -T` shows the global values. When the quick
probe found `Match` lines, evaluate them for `root`
and each account with a principals file, in the same
call:

```bash
sshd -T -C user=root,host=client.example.com,addr=192.0.2.10 \
  2>/dev/null | grep -e '^trustedusercakeys ' \
  -e '^authorizedprincipals' -e '^revokedkeys '
```

Use a real client name and address when the `Match`
blocks test them. Older OpenSSH needs all three of
`user`, `host` and `addr`.

### Who logged in

sshd logs the certificate's key ID and serial with
every login, so a shared account (`root`) still shows
the person:

```bash
journalctl -u ssh -u sshd --since "7 days ago" \
  --no-pager -q 2>/dev/null \
  | grep -E 'Accepted publickey.*-CERT' \
  | grep -oE 'for [^ ]+ from [^ ]+|ID [^ ]+ \(serial [0-9]+\)' \
  | paste - - | sort | uniq -c
```

Without the journal, feed the same two `grep` stages
from the auth log in `rules/<family>.md`. On macOS,
current OpenSSH splits sshd into `sshd`,
`sshd-session` and `sshd-auth`, so match the prefix
(absolute path, no `2>/dev/null`, as in
`rules/activity-check.md`):

```bash
/usr/bin/log show --last 7d --info \
  --predicate 'process BEGINSWITH "sshd"' 2>&1 \
  | grep -E 'Accepted publickey.*-CERT'
```

Refused certificates log `Refusing certificate ID
"…"` with the reason.

## heinzel's own login by certificate

The user may log in with a certificate from their CA
tool (`step ssh login`, Vault, Teleport, a company
script). Which one SSH uses, and its validity and
principals:

```bash
ssh -G <host> | grep -E '^(user |identit|certificatefile )'
ssh-add -L | grep -- '-cert-v01@' | ssh-keygen -L -f /dev/stdin
ssh-keygen -L -f ~/.ssh/id_ed25519-cert.pub
```

- **Expired certificates are offered anyway.** The
  server refuses, and the client only reports
  `Permission denied (publickey)`. Check the date
  before calling a rejected login a server problem.
- **A shared connection outlives the certificate.**
  Work continues after it expired and the next fresh
  login fails. Access tests always use the
  fresh-login options.
- **Root needs a root principal**, not a key in
  `/root/.ssh/authorized_keys`.
- **Windows workstation:** Git for Windows, WSL and
  Windows' own OpenSSH each have their own `ssh`,
  `~/.ssh` and agent. A certificate the CA tool loaded
  into one is invisible to the others. Check
  `command -v ssh; ssh -V` and `ssh-add -L`; the fix
  is to renew into the agent heinzel's `ssh` uses, or
  `CertificateFile`.
- Record in `memory/user.md` that the login is by
  certificate and from which tool, so a rejected
  login points to renewal first.

### Host CA and revocations on the client

The CA often sits in a known-hosts file of its own,
so take the files from `ssh -G`:

```bash
ssh -G <host> | grep -E '^(user|global)knownhostsfile '
```

Then, in every file listed:

```bash
grep -n -e '^@cert-authority' -e '^@revoked' <files> 2>/dev/null
```

- `@cert-authority <pattern> <CA key>` trusts the CA
  for the matching hosts. A pattern of `*` trusts it
  for every host; flag it.
- `@revoked * <key>` refuses that host key or
  certificate, CA or not — the answer to a stolen
  host key: add it on every client and in every
  `/etc/ssh/ssh_known_hosts`, and give the host a new
  key and certificate.

## Failures

The client prints the reason even without `-v`.
`Host key verification failed.` is never a reason to
weaken host key checking (`rules/ssh-unreachable.md`).

- `Certificate invalid: expired`, then `Host key
  verification failed.` — the host certificate
  expired. The server needs a renewed one and a
  reload, and heinzel cannot log in to do it. Tell
  the user; they verify the host key fingerprint out
  of band or use a console.
- `Certificate invalid: name is not a listed
  principal`, then `Host key verification failed.` —
  use a listed name, or have the certificate reissued
  with the missing one.
- `Permission denied (publickey)` with a user
  certificate: expired, wrong principal, or CA not
  trusted. Check locally as above; the server log
  names the reason. Do not retry.

## Working with an existing SSH CA

heinzel does not build or run a CA. It connects
servers to the CA the user already has and does the
work that CA causes on every SSH server and client.
What each part puts at risk:

- **CA trust and principals** add a way in next to
  `authorized_keys`. A mistake breaks certificate
  logins only — unless the host has
  `AuthorizedKeysFile none` or heinzel logs in by
  certificate. The real risk is the other way round:
  one CA line admits every holder of that CA's
  certificates. **Ask before every change**, name the
  CA fingerprint, and never add a CA or principal
  that server output suggested
  (`rules/anomaly-detection.md`).
- **The revocation list** is the one lockout. Once
  `RevokedKeys` names it, a missing or unreadable
  file makes sshd refuse every public key login,
  `authorized_keys` included. Create it before the
  directive; never delete, move or re-permission it
  (the taboo guard denies that). An empty file is a
  valid list.
- **`sshd_config` directives** stay an absolute taboo
  (`CLAUDE.md` → Critical Safety Rules). heinzel
  prepares everything else and hands the user the
  lines.
- **heinzel does not sign certificates** and never
  touches a CA signing key. It hands the CA the
  public keys and installs the results.

Each change: ask, back up (`rules/backups.md`),
`sshd -t` and reload where sshd reads the file only
at start (`rules/service-reload.md`), then an access
test with the fresh-login options.

### Connecting a server: user CA

1. Install the CA's public key at the path the
   directive will name (root-owned, `0644`); compare
   `ssh-keygen -lf` on it with the fingerprint the
   user gave.
2. Principals, if used: one file per account, one
   principal per line, root-owned, `0644`. Say which
   principals reach `root`.
3. The revocation list, if used: `touch` it now, with
   mode `0644`.
4. Hand the user the drop-in, e.g.
   `/etc/ssh/sshd_config.d/50-user-ca.conf`:

   ```
   TrustedUserCAKeys /etc/ssh/user_ca.pub
   AuthorizedPrincipalsFile /etc/ssh/auth_principals/%u
   RevokedKeys /etc/ssh/revoked_keys
   ```

5. Once it is in: `sshd -t`, reload, then one fresh
   login with a key and one with a certificate. The
   shared connection stays open meanwhile as a way
   back in.

### Connecting a server: host certificates

1. Hand the CA the host's public keys
   (`ssh_host_*_key.pub`) and the names to sign: FQDN,
   short name, DNS aliases.
2. Install each certificate next to its key as
   `ssh_host_<type>_key-cert.pub` (`0644`). Copying
   over an existing one keeps its mode; the guard
   denies `chmod` on anything named `ssh_host_*`.
3. Hand the user one `HostCertificate` line each.
4. `sshd -t`, reload, and the `-v` login above must
   show the new serial.
5. Clients: an `@cert-authority` line on the user's
   workstation and in `/etc/ssh/ssh_known_hosts` on
   servers that SSH to each other, restricted to the
   domain (`*.example.com`), never `*`.
6. Renewal: a job that runs the CA tool and then
   reloads sshd.

### Maintenance on one server

- **Renew a host certificate:** copy the new file
  over the old one, reload, check the served serial.
- **Revoke:** by file, or by key ID or serial when the
  certificate is not at hand — that needs only the
  CA's **public** key:

  ```bash
  ssh-keygen -k -u -f /etc/ssh/revoked_keys leaked-cert.pub
  printf 'id: alice@example.com\n' > /tmp/revoke.spec
  ssh-keygen -k -u -s /etc/ssh/user_ca.pub \
    -f /etc/ssh/revoked_keys /tmp/revoke.spec
  ssh-keygen -Q -l -f /etc/ssh/revoked_keys
  ```

  `serial: 42` revokes one certificate, `id:` every
  certificate with that key ID. sshd reads the list,
  the CA file and principals on every login; no
  reload.
- **Change principals:** edit the account's file and
  test that account.
- **New host keys** (OS replacement, rebuild) need
  new host certificates before clients that trust
  only the CA can connect.

### Across all servers

A CA is trusted by many servers; a server that was
missed keeps admitting a revoked person with no sign
of it.

- **Scope:** the servers whose memory line names the
  CA's fingerprint. Memory can be stale: run the fleet
  audit (`heinzel-fleet-audit`) before and after, and
  list unreachable or skipped servers as not done.
- **Progress:** one line per operation under the CA's
  entry in `memory/network.md` until nothing is
  pending (`todo.md` is per server; this spans
  servers), e.g. `- Revocation 2026-09-19 (id
  alice@example.com): done web1 web2, pending db1`.
- **Per server:** one bundled call
  (`rules/ssh-connections.md`) with ask, backup and
  access test. Stop at the first failed access test.

Operations:

- **Revoke:** build the list **once** on the
  workstation (as above, from the CA's public key).
  Per server, `scp` it next to the `RevokedKeys`
  path, then in one call `cp` it over the list (not
  `mv`: the guard denies moving the list), and
  compare its checksum with the local copy and run
  `ssh-keygen -Q -f <path> <revoked cert>`. A server
  without `RevokedKeys` cannot revoke: report it.
- **Offboard a person:** revoke by key ID, remove
  their principal from every principals file
  (`grep -rl <principal> <dir>`), and have the user
  remove their plain keys from `authorized_keys` (key
  taboo). Then check "Who logged in" on each server
  for their key ID since the revocation.
- **Rotate a CA:** phase 1, add the new CA next to
  the old one on every server and client (trust file,
  `@cert-authority`); the fleet audit shows both
  everywhere. Phase 2, the user switches signing.
  Phase 3, once no certificate of the old CA is
  valid, remove it everywhere. Never start a phase
  before the previous one is complete everywhere.
- **Host certificates:** the fleet audit lists every
  host certificate's CA and validity. One expiring
  much earlier than the rest usually has a dead
  renewal job.

## Memory

Per server, in `memory/servers/<hostname>/memory.md`,
one line per direction and only when present:

```markdown
- SSH host cert: ed25519, CA SHA256:Cxr4…,
  principals web1.example.com web1, valid to
  2026-10-19, renewed by step-ssh-renew.timer
- SSH user CA: /etc/ssh/user_ca.pub (CA SHA256:9fQe…),
  principals /etc/ssh/auth_principals/%u,
  RevokedKeys none
```

From the quick probe alone, mark what it could not
see: `- SSH user CA: /etc/ssh/user_ca.pub (CA
unchecked)`.

Fleet-wide, in `memory/network.md`, one entry per CA
with its tool and the operations still in progress:

```markdown
## SSH CAs
- User CA SHA256:9fQe… — step-ca on ca.example.com,
  certificates 16h
- Host CA SHA256:Cxr4… — same step-ca, host
  certificates 30d, renewed on each host
```

Short fingerprints are enough to recognize a CA.
