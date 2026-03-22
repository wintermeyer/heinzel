# CI/CD Deployment Users

When setting up automated deployments (GitHub
Actions, GitLab CI, etc.), **never use the root
account or a personal user account**. Always create
a dedicated deploy user with minimal privileges.

## Never Root for CI/CD

Automated pipelines must not SSH as root. If the
user asks to set up deployment with root, explain
the risk and create a dedicated user instead.

**Risks of root deployments:**

- A compromised CI secret grants full server access.
- No audit trail separating human from automated
  actions.
- Accidental destructive commands run unchecked.

## Create the Deploy User

Create a system user with no password and no login
shell. Adapt the username to the project if the
user prefers (e.g. `deploy-myapp`), default to
`deploy`.

### Linux

```bash
useradd --system --shell /usr/sbin/nologin \
  --create-home --home-dir /home/deploy deploy
```

### FreeBSD

```bash
pw useradd deploy -d /home/deploy \
  -s /usr/sbin/nologin -m \
  -c "CI/CD deploy user"
```

### Verify

```bash
id deploy
grep deploy /etc/passwd
```

The user should have no password set (`!` or `*`
in `/etc/shadow`). Confirm:

```bash
passwd -S deploy 2>/dev/null \
  || grep deploy /etc/shadow
```

## SSH Key for the Deploy User

Generate a dedicated keypair for the CI pipeline.
Do not reuse personal keys or the server's host
key.

### Generate the keypair

Run locally (not on the server):

```bash
ssh-keygen -t ed25519 -C "deploy@hostname" \
  -f deploy_ed25519 -N ""
```

This produces `deploy_ed25519` (private) and
`deploy_ed25519.pub` (public).

### Install the public key on the server

```bash
mkdir -p /home/deploy/.ssh
chmod 700 /home/deploy/.ssh
cat deploy_ed25519.pub \
  >> /home/deploy/.ssh/authorized_keys
chmod 600 /home/deploy/.ssh/authorized_keys
chown -R deploy:deploy /home/deploy/.ssh
```

### Store the private key as a CI secret

Tell the user to add the private key as a secret
in their CI system (e.g. GitHub Actions secret
named `DEPLOY_SSH_KEY`). **Never commit the
private key to a repository.**

### Restrict the authorized key (optional)

For maximum lockdown, prepend restrictions to the
key in `authorized_keys`:

```
no-port-forwarding,no-X11-forwarding,no-agent-forwarding ssh-ed25519 AAAA...
```

Discuss with the user whether these restrictions
fit their workflow.

## Deployment Directory

Grant the deploy user write access only to the
directory it needs.

```bash
mkdir -p /var/www/myapp
chown deploy:deploy /var/www/myapp
```

Adapt the path to the actual application. Common
locations:

- `/var/www/<app>` — web applications
- `/opt/<app>` — standalone services
- `/home/deploy/<app>` — when no system path fits

Do not grant ownership of directories outside the
deployment target.

## Restricted Sudo (Only If Needed)

If the deploy user must restart a service after
deployment, grant sudo for that specific command
only. **Never grant general sudo.**

```bash
visudo -f /etc/sudoers.d/deploy
```

Content:

```
deploy ALL=(root) NOPASSWD: /usr/bin/systemctl restart myapp.service
deploy ALL=(root) NOPASSWD: /usr/bin/systemctl reload myapp.service
```

**Rules for the sudoers entry:**

1. One line per allowed command — full path
   required.
2. Only `restart` and `reload` for the specific
   service. Never `start`, `stop`, or wildcards.
3. `NOPASSWD` is required (the deploy user has no
   password).
4. Validate syntax:
   `visudo -c -f /etc/sudoers.d/deploy`
5. Back up per `rules/backups.md` before writing.

If the application can reload without sudo (e.g.
via a signal file or socket), prefer that approach
and skip sudoers entirely.

## Login Shell Override for Deployment

The deploy user is created with
`/usr/sbin/nologin` for security, but SSH requires
a shell to execute commands.

**Preferred:** keep `nologin` and use SSH
`command=` restriction in `authorized_keys`:

```
command="/home/deploy/deploy.sh",no-port-forwarding ssh-ed25519 AAAA...
```

**Alternative:** if the deployment process needs a
full shell (e.g. rsync, multiple commands):

```bash
usermod -s /bin/bash deploy
```

Discuss the trade-off with the user: a full shell
is more flexible but increases the attack surface
if the key is compromised.

## Firewall

No special firewall changes needed. Deployment
uses the existing SSH port (22). Do not open
additional ports for the deploy user.

## Server Memory

After creating the deploy user, update the
server's `memory.md` with:

```markdown
- Deploy user: deploy (CI/CD, SSH key auth)
- Deploy target: /var/www/myapp
- Deploy sudo: systemctl restart myapp.service
```

Omit the sudo line if no sudo was configured.

## Changelog

Log the deployment user setup per
`rules/changelog.md`:

```bash
logger -t heinzel "Created deploy user 'deploy' \
for CI/CD, key auth, target /var/www/myapp"
```

## Removing a Deploy User

When the user asks to remove a deployment setup:

1. Remove the sudoers file:
   `rm /etc/sudoers.d/deploy`
2. Remove the user and home directory:
   - Linux: `userdel -r deploy`
   - FreeBSD: `pw userdel deploy -r`
3. Ask the user to remove the CI secret.
4. Update server `memory.md` — remove deploy
   entries.
5. Log the removal per `rules/changelog.md`.
