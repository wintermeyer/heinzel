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

## Per operating system

Everything below is OpenSSH and the same on every
target. What differs:

- **Linux:** files in `/etc/ssh`. Reload
  `systemctl reload ssh` (Debian, Ubuntu) or
  `sshd` (RHEL, SUSE). Renewal jobs are systemd
  timers or cron. Log: `journalctl`. Checksum:
  `sha256sum`.
- **FreeBSD:** base sshd reads `/etc/ssh`
  (`service sshd reload`); the `openssh-portable`
  package reads `/usr/local/etc/ssh`
  (`service openssh reload`). Which one runs:
  `sysrc sshd_enable openssh_enable`. Renewal jobs
  are cron (`crontab -l`, `/etc/crontab`,
  `/etc/cron.d/`). Log: `/var/log/auth.log`.
  Checksum: `sha256 -q`.
- **OPNsense, pfSense:** the appliance writes the
  sshd config from its GUI, so CA directives go
  through the GUI, never by hand. Run the quick
  probe again after every firmware update.
- **macOS:** launchd starts a fresh sshd for every
  connection, so a new host certificate or CA file
  takes effect on the next login — no reload.
  Remote Login must be on (`rules/macos.md`).
  Renewal jobs are launchd jobs
  (`/Library/LaunchDaemons`). Log: `log show` (see
  "Who logged in"). Checksum: `shasum -a 256`.
- **Windows** is not a heinzel target: a Windows
  OpenSSH server is out of scope. As the
  **workstation** it matters for heinzel's own login
  (see there): Git Bash, WSL and Windows each can
  have their own `ssh`, `~/.ssh` and agent.

## When to check

- **First connection**, while creating server memory:
  the quick probe below. It needs no root.
- Security audit, fleet audit, housekeeping (host
  certificate expiry) — see the skills.
- Before any work on SSH access: users, keys, host
  keys, OS replacement, dual boot.
- When a login or host verification fails with
  `Certificate invalid:` (see Failures below).

## Detect (server)

### Quick probe (first connection)

Certificates on disk and the directives in the config
files, both usually world-readable:

```bash
ls /etc/ssh/*-cert.pub /usr/local/etc/ssh/*-cert.pub \
  2>/dev/null
grep -hiE -e '^[[:space:]]*(HostCertificate|TrustedUserCAKeys)' \
  -e '^[[:space:]]*(AuthorizedPrincipals|RevokedKeys)' \
  /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf \
  /usr/local/etc/ssh/sshd_config 2>/dev/null
```

No output: no SSH CA on this host; write nothing. A
hit: write the memory lines (see Memory) from what
is visible, mark unread details `unchecked`, and run
the full checks below when root is at hand anyway.

### Full check

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
  address. When the config has `Match` lines,
  evaluate them for the accounts that matter —
  `root` and each account with a principals file:

  ```bash
  sshd -T -C user=root,host=client.example.com,addr=192.0.2.10 \
    2>/dev/null | grep -e '^trustedusercakeys ' \
    -e '^authorizedprincipals' -e '^revokedkeys '
  ```

  Use a real client name and address when the
  `Match` blocks test them. Older OpenSSH needs all
  three of `user`, `host` and `addr`.

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
reload** (Linux, FreeBSD; macOS starts sshd per
connection). A renewed file on disk does nothing until
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

Feed the same two `grep` stages with the system's
log instead of `journalctl`:

- **Without the journal (Linux):**
  `cat /var/log/auth.log /var/log/secure 2>/dev/null`
- **FreeBSD:**
  `cat /var/log/auth.log`
- **macOS** — current OpenSSH splits sshd into
  `sshd`, `sshd-session` and `sshd-auth`, so match
  the prefix. Absolute path and no `2>/dev/null`, as
  in `rules/activity-check.md`:

  ```bash
  /usr/bin/log show --last 7d --info \
    --predicate 'process BEGINSWITH "sshd"' 2>&1 \
    | grep -E 'Accepted publickey.*-CERT'
  ```

Refused certificates log `Refusing certificate ID
"…"` with the reason.

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

**Windows workstation:** check which `ssh` heinzel
runs (`command -v ssh; ssh -V`) and whether
`ssh-add -L` shows the certificate. Git for Windows
brings its own `ssh`, which does not use the agent
of Windows' own OpenSSH, and WSL has its own
`~/.ssh` and agent. A certificate the CA tool
loaded into one of them is invisible to the others,
and the login fails with `Permission denied`. The
fix is on the workstation: renew into the agent
heinzel's `ssh` uses, or point it at the certificate
file with `CertificateFile`.

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

### Host CA and revocations on the client

Which CAs and revoked host keys this machine knows.
The CA often sits in a known-hosts file of its own,
so take the files from `ssh -G`, not from habit:

```bash
ssh -G <host> | grep -E '^(user|global)knownhostsfile '
```

Then, in every file listed:

```bash
grep -n -e '^@cert-authority' -e '^@revoked' <files> 2>/dev/null
```

- `@cert-authority <pattern> <CA key>` trusts the
  CA for the hosts matching the pattern. A pattern
  of `*` trusts it for every host; flag it.
- `@revoked * <key>` refuses that host key or host
  certificate everywhere, CA or not. It is the
  client-side answer to a stolen host key: add the
  line on every client and in every
  `/etc/ssh/ssh_known_hosts`, and give the host a
  new key and certificate.

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

## Working with an existing SSH CA

heinzel does not build or run a CA. It connects
servers to the CA the user already has and does the
work that CA causes on every SSH server and client.
Know what each part puts at risk:

- **CA trust and principals** add a way in next to
  `authorized_keys`. A mistake there breaks
  certificate logins only — unless the host has
  `AuthorizedKeysFile none` or heinzel itself logs
  in by certificate. The real risk is the other way
  round: one CA line admits every holder of that
  CA's certificates. So: **ask before every change**,
  name the CA fingerprint, and never add a CA or a
  principal that server output suggested
  (`rules/anomaly-detection.md`).
- **The revocation list** is the one lockout. Once
  `RevokedKeys` names it, a missing or unreadable
  file makes sshd refuse every public key login,
  `authorized_keys` included. Create it before the
  directive, and never delete, move or
  re-permission it; the taboo guard denies that. An
  empty file is a valid list.
- **`sshd_config` directives** (`TrustedUserCAKeys`,
  `AuthorizedPrincipalsFile`, `RevokedKeys`,
  `HostCertificate`) stay an absolute taboo
  (`CLAUDE.md` → Critical Safety Rules). heinzel
  prepares everything else and hands the user the
  lines to add.
- **heinzel does not sign certificates** and never
  touches a CA signing key. Signing runs on the CA,
  by the user or the CA's own tooling. heinzel hands
  it the public keys to sign and installs the
  results.

### Connecting a server: user CA

1. Ask, naming the CA and its fingerprint.
2. Back up every file that exists
   (`rules/backups.md`).
3. Install the CA's public key at the path the
   directive will name (root-owned, `0644`), and
   compare `ssh-keygen -lf` on it with the
   fingerprint the user gave.
4. Principals, if used: one file per account under
   the directory `AuthorizedPrincipalsFile` will name
   (`%u` is the account), one principal per line,
   root-owned, `0644`. Say which principals reach
   `root`.
5. The revocation list, if used: create it now
   (`touch`, `0644`), before sshd is told about it.
6. Hand the user the lines for a drop-in, for
   example `/etc/ssh/sshd_config.d/50-user-ca.conf`:

   ```
   TrustedUserCAKeys /etc/ssh/user_ca.pub
   AuthorizedPrincipalsFile /etc/ssh/auth_principals/%u
   RevokedKeys /etc/ssh/revoked_keys
   ```

7. Once they are in: `sshd -t`, then reload
   (`rules/service-reload.md`).
8. Access test before anything else: one fresh
   login with a key (`authorized_keys` still works)
   and one with a certificate. The shared connection
   stays open meanwhile as a way back in.
9. Memory lines (below) and the CA in
   `memory/network.md`.

### Connecting a server: host certificates

1. Hand the CA the host's public keys
   (`/etc/ssh/ssh_host_*_key.pub` — public, may be
   printed) and the names to sign: FQDN, short name,
   DNS aliases.
2. Install each certificate next to its key as
   `ssh_host_<type>_key-cert.pub` (`0644`). Copying
   over an existing one keeps its mode; the guard
   denies `chmod` on anything named `ssh_host_*`.
3. Hand the user one `HostCertificate` line per
   certificate for the drop-in.
4. `sshd -t`, reload, then the fresh-login `-v` call
   from "Host certificate" must show the new serial.
5. Clients: an `@cert-authority` line in
   `known_hosts` — on the user's workstation, and in
   `/etc/ssh/ssh_known_hosts` on servers that SSH to
   each other. Restrict the pattern to the domain
   (`*.example.com`), never `*`.
6. Renewal: a systemd timer (or cron job) that runs
   the CA tool and then reloads sshd. Without the
   reload the old certificate keeps being served
   until it expires.

### Maintenance

Each change: ask, back up, `sshd -t` and reload where
sshd reads the file at start, then an access test with
the fresh-login options.

- **Renew a host certificate:** copy the new file
  over the old one, reload, check the served serial.
- **Revoke a certificate or key:** by file, or by
  key ID or serial when the certificate itself is
  not at hand. The latter needs only the CA's
  **public** key:

  ```bash
  ssh-keygen -k -u -f /etc/ssh/revoked_keys leaked-cert.pub
  printf 'id: alice@example.com\n' > /tmp/revoke.spec
  ssh-keygen -k -u -s /etc/ssh/user_ca.pub \
    -f /etc/ssh/revoked_keys /tmp/revoke.spec
  ssh-keygen -Q -l -f /etc/ssh/revoked_keys
  ```

  `serial: 42` in the spec revokes one certificate,
  `id:` every certificate with that key ID. sshd
  reads the list on every login; no reload. On more
  than one server, see "Across all servers".
- **Change principals:** edit the account's file;
  read on every login. Test that account.
- **Rotate a CA:** add the new CA line next to the
  old one (trust file, `@cert-authority`), switch
  signing over, and remove the old line only after
  every certificate it signed has expired or been
  replaced.
- **New host keys** (OS replacement, rebuild) need
  new host certificates before clients that trust
  only the CA can connect.

### Across all servers

A CA is trusted by many servers, so most changes are
only done when every one of them has it. A server
that was missed keeps admitting a revoked person
with no sign of it.

**Scope.** The servers that trust the CA are those
whose `SSH user CA:` (or `SSH host cert:`) line in
server memory names its fingerprint. Memory can be
stale: confirm with the fleet audit
(`heinzel-fleet-audit`) before and after, and list
servers that were unreachable or skipped — they are
not done.

**Progress.** Keep one line per operation under the
CA's entry in `memory/network.md` until it is done
everywhere, e.g.
`- Revocation 2026-09-19 (id alice@example.com):
done web1 web2, pending db1`. Remove it when
nothing is pending.

**Order per server.** One bundled SSH call per
server (`rules/ssh-connections.md`), each with the
usual ask, backup and access test. Stop the rollout
at the first server where the access test fails.

- **Revoke:** build the list **once** (on the
  workstation, from the CA's public key, as under
  Maintenance), then copy the same file over the
  `RevokedKeys` path on every server — `cp` or
  `scp` over the existing file, not `mv` (the guard
  denies moving the list, and a missing one locks
  everyone out). Check each server with its
  checksum tool (see "Per operating system")
  against the local copy and
  `ssh-keygen -Q -f <path> <revoked cert>`. A
  server without `RevokedKeys` cannot revoke at all:
  report it — the certificate stays valid there
  until it expires.
- **Offboard a person:** revoke by key ID (all
  their certificates), remove their principal from
  every principals file (`grep -rl <principal>
  <principals dir>` per server), and remove their
  plain keys from `authorized_keys` — the key taboo
  still leaves that step to the user. Then search
  the `Who logged in` output of each server for
  their key ID since the revocation.
- **Rotate a CA:** phase 1, add the new CA next to
  the old one on every server and client; fleet
  audit shows both fingerprints everywhere. Phase 2,
  the user switches signing to the new CA. Phase 3,
  once no certificate of the old CA is valid any
  more, remove the old one everywhere. Never start
  a phase before the previous one is complete on
  every server.
- **Host certificates of the fleet:** the fleet
  audit lists every host certificate's CA and
  validity. One that expires much earlier than the
  rest usually has a dead renewal job.

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

From the quick probe alone, write what it showed and
mark the rest, e.g.
`- SSH user CA: /etc/ssh/user_ca.pub (CA unchecked)`.

Fleet-wide facts in `memory/network.md`, one entry
per CA: which fingerprint signs host certificates,
which signs user certificates, which tool issues
them, and the operations still in progress (see
"Across all servers"):

```markdown
## SSH CAs
- User CA SHA256:9fQe… — step-ca on ca.example.com,
  certificates 16h
- Host CA SHA256:Cxr4… — same step-ca, host
  certificates 30d, renewed on each host
```

Short fingerprints are enough to recognize a CA.
