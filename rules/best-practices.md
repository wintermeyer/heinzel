# Best Practices — Pre-Execution Review

Before executing a user's request, check it against
the anti-pattern catalog below. If a match is found,
suggest the better alternative. This rule is
**advisory, not blocking** — the user can always
override.

This rule supplements existing rules. When a more
specific rule exists (e.g. `rules/mise.md` for
runtimes), follow that rule's full procedure. This
rule catches patterns not covered elsewhere and
extends existing rules to user-directed actions.

## When to Check

**Trigger:** before executing any user request that:

- Installs software or runtimes
- Creates or configures services
- Changes file permissions or ownership
- Modifies firewall rules or network exposure
- Chooses file storage locations

**Do not trigger on:**

- Read-only commands (inspecting, querying, listing)
- Actions Claude chose proactively (other rules
  handle those)
- Housekeeping or security audit runs

## Interaction Protocol

### 1. Detect

Before executing, check the user's request against
the anti-pattern catalog (see below).

### 2. Suggest

If matched, present the alternative briefly:

```
**Suggestion:** Instead of <what user asked>,
<recommended alternative> — <why in one sentence>.

Proceed with <alternative>, or <original> as
requested?
```

Keep it to 3–4 lines. Do not lecture.

### 3. Respect Override

If the user confirms the original approach ("do it
anyway", "yes, use apt", etc.):

- Execute immediately, no further pushback.
- Log the override in the changelog:
  `(user override: <what was overridden>)`
- Do not repeat the same suggestion for the same
  task in this session.

## Suggestion Tiers

### Always Suggest

These patterns are almost never correct. Always
raise them, even if the user seems sure:

- `chmod 777` or `chmod -R 777`
- `curl | bash` (or `wget | sh`) as root for
  unknown software
- Disabling SELinux or AppArmor entirely
- Persistent config or data in `/tmp`
- Cron jobs that periodically restart a service
- Packages from Debian testing/unstable/sid or
  mixing Ubuntu releases

### Suggest Once

These patterns have legitimate uses but are usually
suboptimal. Suggest the alternative once. If the
user overrides, do not repeat for the same task:

- Runtime installation via distro package manager
- `nohup` or `screen` for long-running services
- Binding services to `0.0.0.0` instead of
  `127.0.0.1`
- Opening application ports directly in the
  firewall

## Anti-Pattern Catalog

### Package & Runtime Installation

**Runtime via apt/dnf/zypper**
When the user asks to install a language runtime
(Node.js, Python, Ruby, etc.) via the distro
package manager and mise is available on the server:
suggest mise. Distro packages are often outdated and
harder to manage per-user.
→ `mise use --global node@24`
Cross-reference: `rules/mise.md`

**curl | bash as root**
Piping unknown scripts into a root shell is a
security risk. Suggest the official package or repo
instead. Exceptions: known safe installers (mise,
Ollama, rustup) that are documented in other rules.
→ Use the distro package manager or the project's
official repository.

**Compiling from source**
When an official distro package or upstream repo
exists, prefer it. Source builds do not receive
automatic security updates.
→ Check for a distro package or official repo
first.

**Packages from testing/unstable/sid**
On Debian, installing from non-stable branches
breaks dependency chains and creates a fragile
system. On Ubuntu, mixing releases has the same
effect. This is an "Always suggest" pattern.
→ Use backports, upstream repos, static binaries,
or mise first. Only pin a single package from
testing as absolute last resort with user override.
Cross-reference: `rules/debian.md` (Stable Branch
Only)

### Process & Service Management

**nohup / screen / & for daemons**
Long-running services should be managed by systemd
(or rc on FreeBSD). systemd handles restarts,
logging, dependencies, and boot ordering.
→ Create a systemd unit file.

**Cron restart as a band-aid**
A cron job that restarts a service periodically
masks the root cause. Diagnose why the service
crashes instead.
→ Check logs, fix the underlying issue, configure
systemd `Restart=on-failure`.

**Application server running as root**
Services should run as a dedicated user with
minimal privileges.
→ Create a service user.
Cross-reference: `rules/deployment.md`

### Permissions & Security

**chmod 777 / chmod -R 777**
Gives read, write, and execute to everyone. Almost
never correct.
→ Identify the actual owner/group and use minimal
permissions (e.g. 750, 644).

**chmod 666 on sensitive files**
World-readable and writable. Credentials, keys, and
config files need restrictive permissions.
→ Use 640 or 600 with the correct owner and group.

**Disabling SELinux or AppArmor**
`setenforce 0` or disabling profiles hides the
actual permission problem and weakens the entire
system.
→ Identify the denied operation from audit logs and
create a targeted exception or policy.

**Docker --privileged without justification**
Grants the container full host access. Almost never
needed.
→ Use specific `--cap-add` capabilities instead.

### Network & Exposure

**App port directly exposed to the internet**
Opening application ports (3000, 4000, 8080, etc.)
to the world bypasses TLS and hardening.
→ Use nginx as a reverse proxy with TLS on 443.
Cross-reference: `rules/port-check.md`

**Broad firewall port ranges**
Opening ranges like 8000-9000 is overly permissive.
→ Open individual ports. Restrict source IPs where
possible.

**Binding to 0.0.0.0 when 127.0.0.1 suffices**
Services behind a local reverse proxy or accessed
only locally should bind to loopback. Databases
especially should never bind to all interfaces
without explicit need.
→ Bind to `127.0.0.1` or a Unix socket.

### File & Storage

**Persistent data in /tmp**
`/tmp` is cleared on reboot (and often by tmpwatch
or systemd-tmpfiles). Config and data stored there
will be lost.
→ Use `/etc` for config, `/var` for data, `/opt`
or `/srv` for applications.

**Application data in /root or user home**
Application data in home directories is fragile and
hard to back up systematically.
→ Use `/opt/<app>` or `/srv/<app>` with a dedicated
user.

**Hardcoded temp file paths**
Hardcoding `/tmp/myfile` risks collisions and
symlink attacks.
→ Use `mktemp` or `mktemp -d`.

### Maintenance Shortcuts

**Disabling automatic security updates**
Turning off unattended-upgrades (or equivalent) to
"fix" a problem removes a critical safety net.
→ Fix the specific package conflict or pin only
the affected package.

**--force on package managers**
`apt --force-yes`, `rpm --force`, etc. bypass
conflict checks that exist for a reason.
→ Understand the conflict first. Resolve it
properly.

**Editing package-managed config files directly**
Files in `/etc` managed by a package will be
overwritten or flagged on the next upgrade.
→ Use `.d/` drop-in directories, `dpkg-divert`,
or the application's override mechanism.
