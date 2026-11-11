# Debian & Ubuntu

Rules for Debian, Ubuntu, and derivatives. Read
`rules/linux.md` with it: systemd, the journal,
listening ports and the rollback timer are there.

## Package Manager

- Use `apt-get` (not `apt`) — it's more reliable for
  non-interactive/scripted use.
- Always run `apt-get update` before installing or upgrading.
- Dry-run before upgrading: `apt-get --dry-run upgrade`
- Non-interactive install: `apt-get install -y <package>`

## Stable Branch Only

**Always install packages from the stable branch.**
Never add `testing`, `unstable`, `sid`, or
`experimental` sources unless there is absolutely
no other option and the user explicitly requests it.

### Why This Matters

Mixing releases breaks dependency chains. A single
package from `testing` can pull in dozens of
dependencies that replace stable libraries, leading
to a partially upgraded system that is difficult to
maintain and may break on the next `apt-get upgrade`.

### Preferred Alternatives (in order)

Before reaching for `testing` or `unstable`:

1. **Stable backports.** Check if the package is in
   `<codename>-backports`. Backports are rebuilt from
   testing for the stable release and receive security
   support.
   ```
   apt-get -t <codename>-backports install <package>
   ```
2. **Upstream project repository.** Many projects
   provide their own Debian repos with current
   packages built for stable (e.g. PostgreSQL,
   Docker, Node.js, nginx). These are purpose-built
   and do not pull in unrelated testing dependencies.
3. **Flatpak or AppImage.** For desktop applications
   on workstations (not servers), sandboxed formats
   avoid polluting the system.
4. **Build from source or use a static binary.** For
   CLI tools or services, install to `/usr/local/` or
   `/opt/` to keep the package manager untouched.
5. **mise.** For language runtimes, use mise instead
   of any Debian package. See `rules/mise.md`.

### Last Resort: Pinned Single Package

If none of the above work and the user explicitly
confirms, install a **single pinned package** from
testing — never add testing as a general source.

**Step 1 — Add testing as a secondary source with
low priority:**

```
echo "deb http://deb.debian.org/debian testing main" \
  > /etc/apt/sources.list.d/testing.list

cat > /etc/apt/preferences.d/99-testing-low << 'EOF'
Package: *
Pin: release a=testing
Pin-Priority: 100
EOF
```

Priority 100 means testing packages are never
installed automatically — only when explicitly
requested with `-t testing`.

**Warning:** a package pinned at priority 100 is
frozen — it stops receiving updates, including
security fixes, and must be tracked manually. See
`rules/version-check.md`.

**Step 2 — Install the specific package:**

```
apt-get update
apt-get -t testing install <package>
```

**Step 3 — Verify no collateral upgrades:**

```
apt-cache policy <package>
```

The line marked `***` shows the installed version;
check which repo it came from. Repeat for any
dependencies the install pulled in. If more than
the intended package came from testing, flag this
to the user immediately.

**Step 4 — Document in server memory:**

```markdown
- apt-pinning: <package> from testing (reason:
  <why stable/backports was insufficient>)
```

**Step 5 — Log the override:**

```bash
logger -t heinzel \
  "Installed <package> from testing (pinned, \
user override: stable had no option)"
```

### What to Check on Existing Servers

During housekeeping, verify the sources list:

```
grep -r "testing\|unstable\|sid\|experimental" \
  /etc/apt/sources.list /etc/apt/sources.list.d/
```

If non-stable sources are found without pinning,
flag as **WARN** in the housekeeping report.

### Ubuntu Equivalent

On Ubuntu, the same principle applies: use the
release the server was installed with. Do not mix
in packages from a newer Ubuntu release. Prefer
PPAs from the upstream project over random
third-party PPAs.

## Version Detection

- `/etc/debian_version` — Debian version number
- `lsb_release -a` — if `lsb-release` is installed
- Lifecycle: wiki.debian.org release lifecycle;
  Ubuntu: ubuntu.com/about/release-cycle

## Firewall

- **Expected:** `ufw` (Uncomplicated Firewall)
- Check status: `ufw status verbose`
- If `ufw` is not installed, flag it to the user.
- **Critical:** before enabling `ufw`, always allow SSH
  first: `ufw allow OpenSSH` (or `ufw allow 22/tcp`).
  Enabling `ufw` without an SSH rule locks you out of
  the server immediately. The safe sequence is:
  `ufw allow OpenSSH && ufw enable`. Both cover
  port 22 only: allow every other port sshd listens
  on as well (`CLAUDE.md` → Firewall & network).
- After enabling, verify the default policy:
  `ufw status verbose` — look for
  `Default: deny (incoming)`. If incoming is set to
  `allow`, fix with `ufw default deny incoming`.
- **Native nftables** is installed on Debian with
  its unit off, and counts as a firewall once
  enabled: `nftables.service` loads
  `/etc/nftables.conf`, whose stock version starts
  with `flush ruleset`, so starting, reloading or
  stopping it wipes ufw's rules. A host that runs it
  needs no ufw on top. Checks: `heinzel-security` →
  `references/firewall-nftables-docker.md`.

## Automatic Security Updates

- **Expected:** `unattended-upgrades`
- Config: `/etc/apt/apt.conf.d/50unattended-upgrades`
- Activation also requires
  `APT::Periodic::Unattended-Upgrade "1";` — usually
  set in `/etc/apt/apt.conf.d/20auto-upgrades`.
- Check if active: `systemctl status unattended-upgrades`
  and `systemctl status apt-daily-upgrade.timer`
- If not installed, flag it to the user.

## Service Classes

Installed members (`rules/service-class-check.md`,
phase 1):

```bash
dpkg-query -W \
  -f='${db:Status-Status} ${Package}\n' \
  apache2 nginx caddy lighttpd httpd \
  postgresql mariadb-server mysql-server \
  postfix exim4 sendmail opensmtpd \
  msmtp-mta nullmailer dma \
  chrony ntp openntpd \
  unbound bind9 dnsmasq pdns-recursor \
  knot-resolver \
  ufw firewalld \
  docker.io docker-ce podman containerd.io \
  2>/dev/null | awk '$1=="installed"{print $2}'
```

Then, for the firewall class:
`systemctl is-enabled nftables 2>/dev/null`.

Install dry run (phase 2):

```bash
apt-get install --simulate -y <pkg> 2>/dev/null \
  | awk '/^Inst /{print $2}'
```

## Directory Conventions

- Web roots: `/var/www/`
- Sites config (nginx): `/etc/nginx/sites-available/` and
  `/etc/nginx/sites-enabled/`
- Sites config (Apache): `/etc/apache2/sites-available/` and
  `/etc/apache2/sites-enabled/`

## Notes

- Debian and Ubuntu use the same package manager and mostly
  the same conventions, but package names and available
  versions may differ.
- Ubuntu may have `snap` packages — prefer `apt-get` unless
  the user specifically wants snaps.

## Common Pitfalls

- Use `apt-get` not `apt` — `apt` is for interactive
  use and its output format is unstable.
- Before enabling `ufw`, allow SSH first — see the
  lockout warning in the Firewall section above.
- `ufw` must be enabled (`ufw enable`) — installing
  alone does nothing.
- Prefer `apt-get upgrade` for routine updates.
  `apt-get dist-upgrade` (or `full-upgrade`) may
  remove packages — always dry-run with `-s` first
  and ask the user.
- Debian's `nginx` uses `sites-available/` +
  `sites-enabled/` symlinks. Ubuntu follows the same
  pattern. Do not put configs directly in `conf.d/`
  unless there is no `sites-available/` directory.
- `unattended-upgrades` needs three things: the
  package, `APT::Periodic::Unattended-Upgrade "1";`
  (usually `/etc/apt/apt.conf.d/20auto-upgrades`),
  and an active `apt-daily-upgrade.timer` — check
  all three.
