# Version Check

Proactively check for newer stable versions of
software installed on servers. Nudge the user when
upgrades are available, but never force an upgrade.

**Mandatory:** All version lookups must use a live
web search. Never rely on training data for version
numbers. Cite the source URL when reporting.

## When to Check

### During Housekeeping

Check all Tier 1 software (see below) and add a
"Versions" section to the housekeeping report.

### When Software Is Touched

When configuring, troubleshooting, or otherwise
working with a specific piece of software during a
session, check whether the installed version is
current. Report inline if it is not.

### When Installing or Upgrading

Before installing or upgrading any software, search
for the current stable version. After install,
verify the installed version matches what was
expected and update server memory.

### Not Every Session

Do not check all software on every connect — only
during housekeeping or when a specific piece of
software is touched.

## What to Check

### Tier 1 — Always Check During Housekeeping

- **OS release:** Is the installed OS version still
  supported? Is a newer stable release available?
- **mise-managed runtimes:** Compare installed
  versions (from `memory.md`) against current
  stable/LTS releases.
- **Manually installed services:** Software listed
  in `memory.md` that was installed outside the
  distro package manager (e.g. Ollama,
  node_exporter, mise itself).

### Tier 2 — Check When Touched

Any software being actively worked on in the
current session. This includes distro packages if
the user is configuring or troubleshooting them.

### Tier 3 — Do Not Proactively Check

System packages managed by the distro package
manager (`apt`, `dnf`, `zypper`, `pkg`). These
are covered by the existing "pending updates"
housekeeping check.

## Stable Releases Only

Only compare against **stable, GA (general
availability), or LTS** releases. Ignore:

- Beta, RC, alpha, nightly, preview builds
- Development branches or snapshots
- Odd-numbered development releases (e.g.
  Fedora Rawhide, Node.js odd-numbered versions)

For language runtimes, prefer LTS versions when
the project uses LTS (e.g. Node.js LTS, not
Node.js Current).

## Version Check Procedure

1. **Read `memory.md`** for the server. Identify
   all installed software with version numbers.
2. **Web search** for the current stable version
   of each item being checked. Use official
   project sites or release pages.
3. **Compare** installed vs current.
4. **Classify** the result:
   - `UP TO DATE` — installed version matches or
     is within one patch release of current.
   - `UPDATE` — a newer stable version exists
     (minor or patch bump within same major).
   - `UPGRADE` — a new major version is available.
   - `EOL` — the installed version has reached
     end of life.

## Nudge Rules

### Severity

- `INFO` — patch update available (e.g.
  17.1 → 17.2). Mention in housekeeping only.
- `WARN` — minor or major update available (e.g.
  22.x → 24.x for Node.js LTS). Mention in
  housekeeping and inline when touched.
- `CRITICAL` — installed version is EOL or has
  known security vulnerabilities. Always mention.

### Cooldown

Do not repeat the same nudge within **14 days**
unless the available version has changed. Track
the last check date in server memory (see below).

### Inline Nudge Format

When nudging during interactive work, use a brief
one-liner after completing the immediate task:

```
Note: Ollama 0.20.0 is available (installed:
0.18.2). Run `ollama update` when convenient.
```

Do not interrupt the user's workflow. Place the
nudge after the current task output.

### Version Pins

If a server has a `version-pin` entry in
`memory.md`, do not nudge for that software:

```markdown
- version-pin: PostgreSQL 16 (legacy app
  dependency)
```

Still report pinned software in housekeeping with
a note explaining the pin, but do not flag it as
WARN.

## Housekeeping Report Section

Add this section to the housekeeping report after
the "System" section:

```
### Versions

Ollama       0.18.2   -> 0.20.0 available   WARN
PostgreSQL   17.1     -> 17.3 available      INFO
node_export  1.9.0    UP TO DATE
Node.js      22.19.0  -> 24.1.0 LTS avail.  WARN
Debian       13       UP TO DATE
```

**Rules:**

- One line per checked item.
- Show installed version, arrow and available
  version (if different), and severity.
- Items that are up to date show `UP TO DATE`
  with no severity tag.
- Sort: CRITICAL first, then WARN, then INFO,
  then UP TO DATE.

## OS End-of-Life Awareness

For OS releases, always check whether the
installed version is approaching or past its
end-of-life date. Use official sources:

- **Debian:** wiki.debian.org release lifecycle
- **Ubuntu:** ubuntu.com/about/release-cycle
- **RHEL/CentOS:** Red Hat lifecycle policy
- **FreeBSD:** freebsd.org/security
- **SUSE:** suse.com/lifecycle
- **macOS:** Apple typically supports current and
  two prior major versions

Severity:

- `WARN` if EOL is within 6 months
- `CRITICAL` if the OS is past EOL

## Server Memory

After a version check, update the server's
`memory.md` with a tracking line:

```markdown
- last-version-check: 2026-03-22 — Ollama
  0.18.2 (0.20.0 avail), PG 17.1 (17.3 avail),
  node_exporter 1.9.0 (current), Node 22.19.0
  (24.1.0 LTS avail), Debian 13 (current)
```

Replace the previous `last-version-check` line
(do not accumulate). This line serves as the
cooldown tracker — compare dates to decide
whether to re-check.

## Changelog

Log the version check per `rules/changelog.md`:

```bash
logger -t heinzel \
  "Version check: 2 updates available \
(Ollama, Node.js), 0 EOL"
```
