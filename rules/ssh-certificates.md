# SSH Certificates (SSH CA)

OpenSSH certificates are keys signed by a certificate
authority (CA). They work in two directions that have
nothing to do with each other:

- **Host certificate:** the server proves its identity
  to clients. Clients trust the host CA through an
  `@cert-authority` line in `known_hosts` instead of
  one line per host key.
- **User certificate:** a person or tool logs in with
  a short-lived certificate. The server trusts the
  user CA through `TrustedUserCAKeys` (or a
  `cert-authority` line in `authorized_keys`) instead
  of a key per person in `authorized_keys`.

A host can use either one, both, or neither. Detect
and record them **separately**:

- **Host certificate:** set by `HostCertificate`,
  trusted on the clients, renewed by a timer on the
  server. Expiry breaks host verification for every
  client that knows the host only through the CA.
- **User certificate:** set by `TrustedUserCAKeys`,
  principals and `RevokedKeys`, trusted on the
  server, renewed by the person, often daily. Expiry
  breaks that one person's login.

Different failures, different owners, different
renewal: one line in memory for both would hide
which half is broken. Use a separate CA key for
each direction; one CA signing both is a finding.

Certificates themselves are public and may be
printed. The CA **signing keys** are secrets
(`rules/secrets.md`).

## When to check

- Security audit, fleet audit, housekeeping (host
  certificate expiry) — see the skills.
- Before any work on SSH access: users, keys, host
  keys, OS replacement, dual boot.
- When a login or host verification fails with
  `Certificate invalid:` (see Failures below).

## Detect (server)

`sshd -T` gives the effective values. It needs root
(`sudo -n sshd -T` otherwise):

```bash
sshd -T 2>/dev/null | grep \
  -e '^hostcertificate ' -e '^trustedusercakeys ' \
  -e '^authorizedprincipals' -e '^revokedkeys ' \
  -e '^casignaturealgorithms '
```

- No `hostcertificate` line: no host certificate.
- `trustedusercakeys none`: no user CA by sshd
  config. A `cert-authority` line in an
  `authorized_keys` still is one (below).
- No `revokedkeys` line: no revocation list.
- `sshd -T` shows the global values. A `Match`
  block can set principals or CA keys per user or
  address; read the config for them.

Without root, read the config files. They are
usually world-readable:

```bash
grep -hiE -e '^[[:space:]]*(Match|HostCertificate)' \
  -e '^[[:space:]]*(TrustedUserCAKeys|AuthorizedPrincipals)' \
  -e '^[[:space:]]*(RevokedKeys|CASignatureAlgorithms)' \
  /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf \
  2>/dev/null
```

CA trust inside `authorized_keys`:

```bash
grep -Hn 'cert-authority' /root/.ssh/authorized_keys \
  /home/*/.ssh/authorized_keys 2>/dev/null
```

## Host certificate

For each `hostcertificate` path (usually
`/etc/ssh/ssh_host_<type>_key-cert.pub`; the FreeBSD
port uses `/usr/local/etc/ssh`, so adjust the glob
to the path `sshd -T` shows):

```bash
for c in /etc/ssh/*-cert.pub; do
  [ -e "$c" ] || continue
  echo "== $c"
  ssh-keygen -L -f "$c"
  ssh-keygen -lf "${c%-cert.pub}.pub"
done
```

Read from the output:

- **Type** must say `host certificate`.
- **Public key** fingerprint must equal the
  fingerprint of the host key next to it. A
  mismatch means the certificate belongs to an old
  key and no client can verify it.
- **Signing CA** fingerprint: the host CA. Compare
  with `memory/network.md` and with the user CA.
- **Valid:** `from … to …` or `forever`.
- **Principals:** every name clients use — FQDN,
  short name, the DNS aliases in server memory. A
  missing name fails verification for whoever uses
  it.

Keep `awk` out of this call: an interpreter next to
an `ssh_host_` path is denied by the taboo guard.
Work out the remaining days by hand.

Renewal usually runs on the host: look for a timer
or cron job (`systemctl list-timers`, `crontab -l`,
`/etc/cron.d/`) that calls the CA tool (`step ssh
renew`, `vault write …/sign`, a script). No job and a
certificate that expires is the typical outage.

**sshd serves the certificate it loaded at start or
reload.** A renewed file on disk does nothing until
`sshd` reloads, and a job that renews without a
reload leaves the old certificate running until it
expires. After the renewal job, check that it
reloads.

Without root, the client sees what the server
presents. One fresh login (`CLAUDE.md` → SSH
Options, fresh-login set) with `-v`:

```bash
ssh -v -o BatchMode=yes -o ConnectTimeout=5 \
  -o ControlMaster=no -o ControlPath=none \
  USER@HOST true 2>&1 | grep 'Server host certificate'
```

The line names serial, key ID, CA and validity. No
line: no certificate presented.

## User certificates

When `TrustedUserCAKeys` is set:

```bash
ssh-keygen -lf <trustedusercakeys path>
ls -l <trustedusercakeys path>
```

The first lists every trusted user CA by
fingerprint. Then check:

- **The CA signing key must not live on the
  server.** A file with the same name without
  `.pub` (or any `*ca*` file that is not `.pub`) in
  `ls -la /etc/ssh`: report it, never read it. Whoever
  holds it can log in everywhere the CA is trusted.
- **Principals.** `authorizedprincipalsfile none`
  means a certificate works for the account named
  in its principals. With a file (`%u` is the
  account), each line is a principal that may log in
  as that account:

  ```bash
  ls -l /etc/ssh/auth_principals
  grep -H . /etc/ssh/auth_principals/*
  ```

  Report which principals reach `root`. An
  `AuthorizedPrincipalsCommand` cannot be evaluated
  from outside: name the command and its user.
- **Revocation.** A `revokedkeys` file that is
  missing or unreadable makes sshd refuse **every**
  public key login. Check it exists:
  `ls -l <revokedkeys path>`. No `RevokedKeys` at
  all is fine for certificates that live hours; for
  long-lived ones, a leaked certificate stays valid
  until it expires.
- **One CA for both directions.** A user CA
  fingerprint equal to the host certificate's
  signing CA.

### Who logged in

sshd logs the certificate's key ID and serial with
every login, so a shared account (`root`) still
shows the person:

```bash
journalctl -u ssh -u sshd --since "7 days ago" \
  --no-pager -q 2>/dev/null \
  | grep -E 'Accepted publickey.*-CERT' \
  | grep -oE 'for [^ ]+ from [^ ]+|ID [^ ]+ \(serial [0-9]+\)' \
  | paste - - | sort | uniq -c
```

On hosts without the journal, read
`/var/log/auth.log` or `/var/log/secure`. Refused
certificates log `Refusing certificate ID "…"`
with the reason.

## heinzel's own login by certificate

The operator may log in with a certificate from
their CA tool (`step ssh login`, Vault, Teleport,
a company script). Which one SSH uses:

```bash
ssh -G <host> | grep -E '^(user |identit|certificatefile )'
ssh-add -L 2>&1 | grep -c -- '-cert-v01@openssh.com'
```

Validity and principals of a certificate file or of
the ones in the agent:

```bash
ssh-keygen -L -f ~/.ssh/id_ed25519-cert.pub
ssh-add -L | grep -- '-cert-v01@' | ssh-keygen -L -f /dev/stdin
```

- **Expired certificates are offered anyway.** The
  client does not check the date; the server
  refuses, and the client only reports
  `Permission denied (publickey)`. Check the date
  before calling a rejected login a server problem.
- **A shared connection outlives the certificate.**
  The standard options reuse a master that logged in
  while the certificate was valid, so work continues
  after it expired and the next fresh login fails.
  Access tests always use the fresh-login options.
- **Root needs a root principal.** Whether a
  certificate reaches `root` depends on its
  principals and the server's principals file, not
  on `/root/.ssh/authorized_keys`.
- Record in `memory/user.md` that the login is by
  certificate and from which tool, so a rejected
  login points to renewal first.

## Failures

The client prints the reason even without `-v`:

- `Certificate invalid: expired` followed by
  `Host key verification failed.` — the host
  certificate expired and the client knows the host
  only through the CA. The server needs a renewed
  certificate and an sshd reload, and heinzel cannot
  log in to do it. Tell the user; they verify the
  host key fingerprint out of band or use a console.
  **Never** get around it with
  `StrictHostKeyChecking=no` or `accept-new`.
- `Certificate invalid: name is not a listed
  principal` followed by `Host key verification
  failed.` — the name heinzel used is not in the
  host certificate. Use a listed name, or have the
  certificate reissued with the missing name.
- `Permission denied (publickey)` with a user
  certificate: expired, wrong principal, or CA not
  trusted. Check locally as above; the server log
  names the reason (`Refusing certificate …`). Do
  not retry (`rules/ssh-unreachable.md`).

## Changes

- **heinzel does not sign certificates** and never
  touches a CA signing key. Signing is issuing
  credentials; it runs on the CA, by the operator or
  the CA's own tooling.
- **Installing a renewed host certificate** is a
  credential rotation: ask first, back up the old
  file (`rules/backups.md`), copy the new one over
  the path `HostCertificate` names, run `sshd -t`,
  reload sshd (`rules/service-reload.md`), then check
  the served certificate with the fresh-login `-v`
  call above. Copying over the existing file keeps
  its mode; the guard denies `chmod` on anything
  named `ssh_host_*`.
- **Turning host or user certificates on or off**
  means editing `sshd_config`: never
  (`CLAUDE.md` → Critical Safety Rules). Hand the
  user the lines.
- **CA trust, principals and revocation files**
  (`TrustedUserCAKeys`, `AuthorizedPrincipalsFile`,
  `RevokedKeys`, `cert-authority` lines) are
  operator-only, like `authorized_keys`. A wrong
  line grants a whole CA access or locks every
  certificate out, heinzel's own included. The taboo
  guard denies writes to the common file names; a
  path `sshd -T` shows outside them is just as
  protected by this rule. Hand the user the
  command, for example revoking a leaked
  certificate:

  ```bash operator
  ssh-keygen -k -u -f /etc/ssh/revoked_keys leaked-cert.pub
  ```

  After any such change the user runs an access
  test with the fresh-login options.
- **New host keys** (OS replacement, rebuild) need
  new host certificates before clients that trust
  only the CA can connect.

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

Fleet-wide facts in `memory/network.md`: which CA
fingerprint signs host certificates, which signs
user certificates, and which tool issues them.
Short fingerprints are enough to recognize a CA.
