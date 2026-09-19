# Accounts on Demand

People sign in to an identity provider (IdP, via
OIDC), get a short-lived SSH certificate from a CA,
and log in to servers where nobody created their
account by hand. The server never sees the IdP: it
sees a certificate and a name that must resolve at
login (`rules/accounts.md` → Certificate logins).
Nothing at login time can create
the account in time; `pam_mkhomedir` creates only the
home (`rules/accounts.md` → 2).

Products and releases below change often: check the
upstream docs for the version in use before relying
on a line (`CLAUDE.md` → Software Release Versions).

## The ways

Which source a login account comes from:
`rules/accounts.md` → 1. On demand means one of these
(models: `rules/accounts.md` → 4):

- **Directory:** SSSD or `nslcd` resolves every
  directory user; mkhomedir creates the home; the
  principal must be the directory user name. Without
  an LDAP directory: SSSD's `id_provider = idp`
  (SSSD 2.11+, Keycloak and Entra ID over their REST
  APIs; Technology Preview in RHEL 10.2, test
  certificate logins first), or Kanidm as IdP and
  directory in one.
- **Role account:** the CA puts the person's IdP
  groups into the principals; each role account's
  principals file lists the groups it admits.
- **Agent:** Smallstep SSH (commercial `step-ssh`),
  the authentik Agent (`libnss-authentik`, preview),
  Google OS Login, Teleport. Install one only when
  the user asks for that product.

Created ahead instead, for a few people: team
accounts (`rules/accounts.md` → Changing accounts or
sudo rules).

## Who may log in

When an IdP stands behind the CA, limit access in
three places:

- **Who gets a certificate** (CA): only the IdP
  groups meant for server access.
- **Which names it carries** (IdP): heinzel cannot
  see the IdP. Ask the user to confirm that users
  cannot edit the claims that become principals
  (email, username; authentik blocks both by default,
  Keycloak's default user profile allows both).
- **Who may log in here** (host): the directory's
  access rule (`rules/accounts.md` → 1).

**Offboarding:** disable the person in the IdP first
(no new certificates), then revoke the certificates
still valid: the last one lasts to its end.

## Connecting hosts to the directory

Across hosts as in `rules/accounts.md` →
Certificate logins. Record the IdP and the directory
in `memory/network.md`. Per server:

1. **Client:** SSSD with its LDAP backend from the
   distro (`rules/<family>.md`), LDAPS to the
   directory, and the access rule
   (`rules/accounts.md` → 1). authentik's LDAP
   provider, for example
   (<https://integrations.goauthentik.io/infrastructure/sssd/>):
   `ldap_user_name = cn`, `default_shell` set (no
   `loginShell`), local UIDs below 2000 (groups 4000).
   `sssd.conf` is root-only `0600` and holds the bind
   password: the user writes it into the file, never
   on a command line or into memory
   (`rules/secrets.md`).
2. **NSS and PAM:** RHEL, Fedora
   `authselect select sssd`; Debian, Ubuntu
   `libnss-sss` and `libpam-sss`. mkhomedir per
   `rules/accounts.md` → 2. Then
   `getent passwd <name> && id -Gn <name>` must show
   the person and their groups.
3. **Sudo:** the same `%group` file on every host
   (`rules/accounts.md` → Changing accounts or sudo
   rules).
4. **sshd:** CA trust as the user's CA requires,
   principals `none` (`rules/accounts.md` →
   Certificate logins); the directives go through the
   user, never into `sshd_config` by heinzel.
   On the first host, the principals in
   `ssh-keygen -L -f <cert>` must contain the name
   `getent passwd` finds. The access test uses the
   certificate of a person who never logged in
   there; the home must appear.
5. **Memory:** the `Accounts:` line
   (`rules/accounts.md` → Memory).
