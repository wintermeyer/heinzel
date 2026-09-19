# SSH CA Issuing Rules

What a CA that signs user certificates lets people
get, whatever the product. heinzel does not run the
CA (`rules/ssh-certificates.md` → Working with an
existing SSH CA); it reads its rules where it can,
asks the user where it cannot, and reports.

Products and releases change: check the upstream
docs for the version in use before relying on a
field name here (`CLAUDE.md` → Software Release
Versions).

## Findings

For the security audit:

- Anyone who can reach the CA gets a certificate (no
  group restriction) → **WARN**.
- The requester chooses the principals, so anyone
  can ask for `root` or a role account → **CRITICAL**.
- Principals come from claims, but nothing keeps
  `root` and the role accounts out
  (`rules/ssh-certificates.md` → Principals) →
  **WARN**: a person whose email starts with `root@`
  gets `root`.
- The rule that signs user certificates also signs
  host certificates → **WARN**.
- Maximum lifetime above 24h → **INFO**.

Record the result on the CA's entry in
`memory/network.md` (`rules/ssh-certificates.md` →
Memory), e.g. `issuing: groups server-admins, root
denied, 16h`.

## Where to read them

Read-only; never a whole config, a secret or a token
(`rules/secrets.md`). Each product maps to the
findings as: who may get one / free principals and
host certificates / names kept out / lifetime.

- **Plain OpenSSH** (`ssh-keygen -s`): the signing
  process is the rule set; whoever holds the CA key
  signs any principal (`-n`) for any time (`-V`). Ask
  the user, and check where the key lives
  (`rules/ssh-certificates.md` → CA signing key on
  the server).
- **step-ca**, on a managed host, as root; `ca.json`
  holds secrets, so only these fields:

  ```bash
  S=$(systemctl show -p Environment step-ca 2>/dev/null \
    | sed -n 's/.*STEPPATH=\([^ ]*\).*/\1/p')
  $SUDO jq '{admin: .authority.enableAdmin, policy: .authority.policy,
    claims: .authority.claims,
    oidc: [.authority.provisioners[]? | select(.type == "OIDC")
      | {name, admins, groups, domains, claims,
         template: .options.ssh.templateFile}]}' \
    "${S:-/etc/step-ca}/config/ca.json"
  ```

  OIDC `groups`, `domains` / `admins` (emails or
  groups) / `policy.ssh.user` (`deny`, or an `allow`
  list without them) / `claims.maxUserSSHCertDuration`.
  With `enableAdmin: true` the provisioners live in
  the CA's database: ask the user for the same fields.
- **HashiCorp Vault, OpenBao** (a fork, CLI `bao`),
  SSH secrets engine: the user runs
  `vault read <mount>/roles/<role>` and hands over the
  output. The Vault policy on `<mount>/sign/<role>`
  and the groups the auth role binds /
  `allowed_users` empty or `*`,
  `allow_host_certificates` / `allowed_users_template`
  or `default_user_template` binding it to the
  identity / `max_ttl`.
- **Teleport** (own CA and node service): the user
  runs `tctl get roles`. Roles and `node_labels` /
  `allow.logins` (often from traits,
  `{{internal.logins}}`) / `deny.logins` /
  `options.max_session_ttl`.
- **BLESS** (AWS Lambda; last change 2020):
  `bless_deploy.cfg`. The Lambda's IAM policy / the
  caller names `remote_usernames` itself /
  `remote_usernames_blacklist`, and with kmsauth
  `kmsauth_remote_usernames_allowed` (`*` = any) /
  `certificate_validity_*`.
- **Others** (a cloud's CA, a script): the vendor's
  docs or the script, same questions.

A CA tool that offers to set up the host
(`step ssh config --host` and the like) writes
`sshd_config`: never run it; hand the user the lines
(`rules/ssh-certificates.md` → Connecting a server).

## When a login fails on the principal

`Invalid user`, or `Permission denied (publickey)`
with a valid certificate: the certificate's
principals do not contain the account name
(`ssh-keygen -L -f <cert>` next to
`getent passwd <name>`). The usual cause is the claim
the CA builds principals from, e.g. step-ca takes the
email (`jane.doe@example.com` gives `janedoe`,
`jane.doe` and the address) while the directory calls
the person `jdoe`; group principals may carry a path
(Keycloak: `/admins`, unless "Full group path" is
off).
