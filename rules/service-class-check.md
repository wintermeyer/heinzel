# Service Class Conflict Check

Before installing any package, verify that the
install would not add a second member of a service
class already present on the host (for example,
installing Apache when Nginx is already running).
**This check is mandatory — do not skip it.**

This rule complements `rules/port-check.md`. Port
check catches *runtime* binding collisions; this
rule catches the *install-time* case where two
services of the same class land on the same host
and fight for the same role.

## When to Check

- A user asks to install a class-member package
  directly (`apt-get install apache2`).
- A user asks to install a higher-level package
  whose dependencies may include a class member
  (e.g. a webmail suite, a monitoring dashboard,
  a PHP stack).
- A user asks to enable a package already on disk
  that would start a second service in the class.
- Creating a systemd or rc unit that would start a
  class member.

**Do not trigger on:**

- Read-only commands (`dpkg -l`, `rpm -qa`,
  `systemctl status`).
- Housekeeping and security-audit runs — they do
  not install software.
- Upgrades of an *already-installed* class member
  to a newer version of the same package.

## Service Classes

- **Web server:** apache2, httpd, nginx, caddy,
  lighttpd
- **Database:** postgresql, mariadb-server,
  mysql-server
- **MTA:** postfix, exim4, sendmail, opensmtpd,
  msmtp-mta, nullmailer, dma. The last three are
  lightweight MTAs that claim `/usr/sbin/sendmail`
  via Debian's alternatives system and play the
  same role as the full servers above.
- **Time sync:** chrony, ntp (provides ntpd),
  openntpd, systemd-timesyncd
- **DNS resolver:** unbound, bind9 (RPM: `bind`),
  dnsmasq, pdns-recursor, knot-resolver,
  systemd-resolved
- **Firewall manager:** ufw, firewalld, and native
  nftables — the last only when `systemctl is-enabled
  nftables` says `enabled` (the package sits unused on
  most Debian hosts). Debian's stock
  `/etc/nftables.conf` starts with `flush ruleset`, so
  starting, reloading or stopping that unit wipes
  ufw's or firewalld's rules. Raw `iptables` is a
  backend, not a member. FreeBSD's pf and ipfw are in
  base, no frontend packages compete; the same holds
  for OpenBSD's pf.
- **Container runtime:** docker.io, docker-ce,
  moby-engine, podman, containerd.io

Extensions live in
`memory/custom-rules/service-class-check.md` using
the repo's standard `## Add:`, `## Replace:`, and
`## Remove:` heading prefixes. Per-host overrides
live in `memory/servers/<hostname>/rules.md`.

## Detection Procedure

Run both phases in order. If either phase flags a
class member, halt and apply the prompt from
"If a Conflict Is Found" below.

### Phase 1 — Already-installed probe

Query the package database for every class member
listed above: run the probe from the **Service
Classes** section of the host's OS file
(`rules/debian.md`, `rules/rhel.md`,
`rules/suse.md`, `rules/arch.md`,
`rules/freebsd.md`, `rules/netbsd.md`,
`rules/openbsd.md`, `rules/macos.md`).

Members that ship in the base system or inside
systemd never show up in the package database. The
same section names them and their probe; on Linux
read `rules/linux.md` → Service Classes as well.

### Phase 2 — Pending-install dry-run

Before executing the real install, run the package
manager in simulate mode against the user's
request and scan the resolved plan for class
members. This is the step that catches transitive
pulls — the exact scenario this rule exists for.

The dry-run command is in the same **Service
Classes** section. Match the resulting package list
against the class table.

## If a Conflict Is Found

1. **Never run the install.** Stop before any
   state-changing command.
2. Report to the user in one line:
   *"Installing `<requested>` would add
   `<class-member>`, but `<existing-member>` is
   already installed as the host's
   `<class>`."*
3. Present four options:
   - **(a) Keep the existing service.** Look for
     an install variant of the user's target that
     works with the already-installed member
     (e.g. the `-nginx` flavour of a package, or
     a reverse-proxy config that fronts it).
   - **(b) Remove the existing service first.**
     Treat as a destructive action — confirm
     separately, back up its config per
     `rules/backups.md`, and close any ports it
     owned.
   - **(c) Run both side by side.** Hand off to
     `rules/port-check.md` for a non-default port
     or a Unix socket; the new service must not
     bind to the port the existing one uses.
   - **(d) Abort.**
4. **Do not proceed without an explicit choice.**
   Silence, "go ahead", or "do what you think is
   best" all require one more round of
   confirmation — name the option the user is
   picking.

**Option (c) does not apply to every class.** For
classes where only one member can reasonably own
the role on a host, "run both side by side" is not
a real option and must be refused:

- **Time sync** — only one daemon can own the
  system clock. Two running at once either race
  or one silently wins.
- **Firewall manager** — two frontends stomp each
  other's rules and can cut off SSH. Listed in
  CLAUDE.md's "Firewall & network" warning for
  exactly this reason.

For those two classes, present only options (a),
(b), and (d).

Log the outcome per `rules/changelog.md`:

```bash
logger -t heinzel \
  "Declined <pkg> install on <host>: \
<existing> already serves <class>"
```

or, on acceptance of option (b) or (c):

```bash
logger -t heinzel \
  "Added <new> alongside <existing> as <class> \
on <host> (user choice: <option>)"
```

## If Clear

No class member is installed and the dry-run does
not add one, **or** the only class member the
dry-run adds is the one the user explicitly asked
for (no conflict): proceed with the install.

After the install completes, record the canonical
class member in
`memory/servers/<hostname>/memory.md`:

```markdown
- Web server: nginx
- Database: postgresql
- MTA: postfix
- Time sync: chrony
- DNS resolver: unbound
- Firewall manager: ufw
- Container runtime: podman
```

If an entry already exists for the class, leave
it. If option (b) replaced the existing member,
update the entry. If option (c) added a second
member, record both on one line with a note:

```markdown
- Web server: nginx (primary), apache2 (on :8080)
```

## Changelog

Log the install decision per `rules/changelog.md`
as shown above under "If a Conflict Is Found". For
the clear path, the regular install log line is
enough — no extra entry is required from this
rule.
