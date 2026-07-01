# Secrets Hygiene

Secrets are objects to manage, never content to
display. Heinzel routinely works next to private
keys, password files, and tokens — none of their
values may ever appear in the conversation, in
reports, in memory files, in changelogs, or in
emails.

This rule governs how heinzel handles secrets.
Detecting *misconfigured* secrets (world-readable
keys, weak permissions) is the job of the
`heinzel-security` skill.

## What Counts as a Secret

- SSH private keys (`~/.ssh/id_*`,
  `/etc/ssh/ssh_host_*_key`)
- TLS/SSL private keys (`/etc/ssl/private/`,
  `*.key`, `*.pem` containing `PRIVATE KEY`)
- `/etc/shadow` and password hashes
- `.env` files and application config with
  credentials (database URLs with passwords,
  `secret_key_base`, API tokens)
- `~/.netrc`, `~/.aws/credentials`,
  `~/.config/gcloud/`, cloud provider tokens
- Mail credentials (`msmtprc`, `sasl_passwd`)
- Backup repository passwords (restic/borg env
  and password files)

When in doubt, treat it as a secret.

## Inspect via Metadata, Never Content

Existence, ownership, permissions, and size are
almost always what actually matters:

```
ls -l /etc/ssl/private/example.key
stat /root/.restic-env
wc -c /var/www/app/.env
file /etc/ssh/ssh_host_ed25519_key
```

Fingerprints identify keys without exposing them:

```
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
openssl x509 -noout -subject -enddate \
  -fingerprint -in /etc/ssl/certs/example.crt
```

Check whether a key matches a certificate by
comparing hashes of the public parts — never by
printing either file:

```
openssl x509 -noout -pubkey -in example.crt \
  | sha256sum
openssl pkey -pubout -in example.key | sha256sum
```

## Commands That Leak

- Never `cat`, `head`, `tail`, `less`, or `grep`
  (without `-c`/`-l`) a file from the list above.
- When a config that embeds credentials must be
  shown, redact on the fly:

  ```
  sed 's/\(password[ =:]*\).*/\1REDACTED/I' \
    /etc/app/config.ini
  ```

- Watch for accidental leaks: `ps aux` can show
  passwords in argv, `env` output can contain
  tokens, debug logs can echo credentials. If
  server output unexpectedly contains a credential,
  do **not** repeat the value — report *that* it
  leaked, where, and recommend rotating it.

## Never Pass Secrets on the Command Line

A secret handed to a command as an argument
(`-p hunter2`, `--password=…`, `-u user:pass`,
`--token …`) is not private. `argv` is
world-readable through `ps aux` and
`/proc/<pid>/cmdline`, it is written to the shell
history file, and any tool or wrapper that logs
its own invocation copies the value into the
systemd journal or syslog. Run the command in a
loop and every one of those copies multiplies.
Cleartext credentials then sit in those logs long
after the task, readable by anyone who can read
the journal, and scrubbing them all afterwards is
not feasible.

So before running a command, check whether it
takes a secret as an argument. When it does, feed
the secret in a way that keeps it out of `argv`,
preferring, in order:

1. **A credentials file the tool reads natively.**
   The value never touches the command line.
2. **An environment variable the tool reads.** The
   value goes into the child's environment, not
   its `argv`; `/proc/<pid>/environ` is readable
   only by the owner and root, unlike the
   world-readable `cmdline`. Load it from a file
   (`VAR=$(cat /path/creds) cmd …`) so the literal
   never reaches shell history either.
3. **An interactive prompt or stdin.** Omit the
   flag and let the tool ask, or pipe the secret
   in.
4. **An inline argument (last resort only).** If a
   tool offers no other channel, tell the user the
   value will leak and treat it as a credential to
   rotate afterwards.

Common tools, and the channel to use instead of an
inline password:

- `psql` / `pg_dump` / `pg_restore`: a `~/.pgpass`
  line (mode 600), or `PGPASSWORD` in the
  environment.
- `cypher-shell` (Neo4j): `NEO4J_USERNAME` and
  `NEO4J_PASSWORD` in the environment, or omit
  `-p` and answer the prompt.
- `mysql` / `mariadb`: a `~/.my.cnf` `[client]`
  section (mode 600) or a `mysql_config_editor`
  login-path, never `-pSECRET`.
- `redis-cli`: `REDISCLI_AUTH` instead of `-a`.
- `curl` / `wget`: `~/.netrc` (with `--netrc`) or
  a `--config` file, not `-u user:pass`.
- `restic` / `borg`: a `*_PASSWORD_FILE` variable
  pointing at a mode-600 file, not a password on
  the line.

When a tool is unfamiliar, check its `--help` for
a credentials-file or environment-variable option
before falling back to an inline flag.

### When a Secret Has Already Leaked

Sometimes the value is already in the journal,
shell history, or a live process list: heinzel's
own earlier commands, or an operator who ran, say,
`cypher-shell -p …` in a loop. Then:

- Do not repeat the value anywhere. Report *that*
  it leaked, where, and roughly how widely (one
  journal entry versus hundreds).
- **Rotation is the remedy, not deletion.** Treat
  the old value as compromised: reliably scrubbing
  every journal, syslog, and shell-history copy is
  not feasible, so the fix is to replace the
  secret, not to try to erase it.
- **Never rotate on your own.** A rotation is a
  change the user must approve first. Explain the
  leak, recommend rotating, and get an explicit OK
  before touching the credential.
- **Rotation has side effects; keep them minimal.**
  Every consumer still using the old value breaks
  the moment it changes: app configs and `.env`
  files, connection strings, other services, cron
  jobs, backup and monitoring scripts, and clients
  on other hosts. Before rotating, map that blast
  radius so the impact is known. Present a plan
  that updates the secret and every consumer
  together, note which services need a reload or
  restart, and spell out the risk in plain
  language. Proceed only once the user agrees.
- **Verify afterwards.** Confirm the services and
  clients that use the credential still
  authenticate, and record the change with the
  redaction rules above (its location and mode,
  never its value).
- Switch the workflow to a non-leaking channel
  above so the replacement does not leak the same
  way.

## Redaction in Heinzel Artifacts

Changelog entries (`logger -t heinzel`),
`memory.md`, `todo.md`, pre-replacement
inventories, and email bodies record that a
credential exists, its location, and its
permissions — never its value.

Good:

```
logger -t heinzel "Rotated DB password for app \
(value in /var/www/app/.env, mode 600)"
```

Bad:

```
logger -t heinzel "Set DB password to hunter2"
```

## Email Attachments

Files likely to contain secrets are
**default-refuse** for the `heinzel-email` skill:
`.env`, `id_*`, `*_key`, `*.pem` with private key
material, `shadow`, `msmtprc`, `.netrc`, cloud
credential files, anything under
`/etc/ssl/private/`. Warn the user explicitly and
attach only on an explicit per-file override. The
content preview itself would leak — preview these
files with `ls -l` + `file` instead of showing
lines.

## Never Into the Repo Tree

Never copy key material or credential files
anywhere under the heinzel repo. `memory/` (and
`memory/servers/` in team mode) can be shared via
git — a committed key is a published key. This
generalizes the rule in `rules/os-replacement.md`
→ Certificates: store such material outside the
repo (e.g. `~/heinzel-keys/<hostname>/` with mode
`0700` on the directory and `0600` on files) and
record only the *path* in memory or inventories.

## Secrets the User Pastes Into Chat

Sometimes the user pastes a password or token
directly. Then:

- Use it for the immediate task only. Never write
  the value into any repo file, memory, changelog,
  todo, or email.
- When placing it on a server, create the target
  file with safe permissions *before* writing the
  content:

  ```
  install -m 600 /dev/null /etc/app/secret.conf
  ```

- Suggest pointing heinzel at an existing file
  path next time instead of pasting.
- If the value transited an untrusted channel,
  recommend rotating it.
