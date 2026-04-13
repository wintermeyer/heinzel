# Debian & Ubuntu

Rules for Debian, Ubuntu, and derivatives.

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

**Step 2 — Install the specific package:**

```
apt-get update
apt-get -t testing install <package>
```

**Step 3 — Verify no collateral upgrades:**

```
apt list --installed 2>/dev/null | grep testing
```

If more than the intended package was pulled from
testing, flag this to the user immediately.

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
- `/etc/os-release` — full distro info
- `lsb_release -a` — if `lsb-release` is installed

## Firewall

- **Expected:** `ufw` (Uncomplicated Firewall)
- Check status: `ufw status verbose`
- If `ufw` is not installed, flag it to the user.
- **Critical:** before enabling `ufw`, always allow SSH
  first: `ufw allow OpenSSH`. Enabling `ufw` without an
  SSH rule locks you out of the server immediately.
- After enabling, verify the default policy:
  `ufw status verbose` — look for
  `Default: deny (incoming)`. If incoming is set to
  `allow`, fix with `ufw default deny incoming`.

## Automatic Security Updates

- **Expected:** `unattended-upgrades`
- Config: `/etc/apt/apt.conf.d/50unattended-upgrades`
- Check if active: `systemctl status unattended-upgrades`
- If not installed, flag it to the user.

## Service Manager

- `systemctl` (systemd)
- Check service: `systemctl status <service>`
- Logs: `journalctl -u <service>`

## Directory Conventions

- Config files: `/etc/`
- Web roots: `/var/www/`
- Logs: `/var/log/`
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
- `systemctl restart` vs `systemctl reload` — prefer
  `reload` when the service supports it (e.g. nginx)
  to avoid downtime.
- **Before enabling `ufw`**, always allow SSH first:
  `ufw allow OpenSSH` (or `ufw allow 22/tcp`). Running
  `ufw enable` without an SSH rule locks you out of
  the server immediately. The safe sequence is:
  `ufw allow OpenSSH && ufw enable`.
- After that, `ufw` must be enabled (`ufw enable`) —
  installing alone does nothing.
- Debian's `nginx` uses `sites-available/` +
  `sites-enabled/` symlinks. Ubuntu follows the same
  pattern. Do not put configs directly in `conf.d/`
  unless there is no `sites-available/` directory.
- `unattended-upgrades` requires both the package and
  the apt config — check both.
