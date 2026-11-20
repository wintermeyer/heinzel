# Extensions

An extension is a directory of rule files that
changes how Heinzel works without touching Heinzel
itself. Install one somebody else wrote, write your
own, or install Heinzel Pro, an extension with more
rights.

- [Which one do I need?](#which-one-do-i-need)
- [Use an extension](#use-an-extension)
- [Write your own](#write-your-own)
- [What an extension cannot do](#what-an-extension-cannot-do)
- [Heinzel Pro](#heinzel-pro)
- [Licences](#licences)
- [When it says INACTIVE](#when-it-says-inactive)

## Which one do I need?

| | Custom rules | Extension | Heinzel Pro |
| --- | --- | --- | --- |
| Lives in | `memory/custom-rules/` | `extensions/<name>/` | `pro/` |
| Written by | you | you, a colleague, a vendor | the makers of Heinzel |
| For | one person, one checkout | handing rules to others | the work Heinzel refuses |
| Has a version and a licence | no | yes | yes |
| May bring | rules | rules | rules, skills, features |
| Updates | you edit it | you see the diff, then say yes | together with Heinzel |
| In `bin/heinzel-backup` | yes | no, keep it in git | no |

Rules only you use belong in `memory/custom-rules/`
([usage.md](usage.md#rule-customization)). An extension is for
rules that should travel: to your team, your
customers, everybody.

When several layers say something about the same
rule, the later one wins:

1. `rules/<name>.md` (Heinzel)
2. `pro/rules/<name>.md` (Heinzel Pro)
3. `extensions/<ext>/rules/<name>.md`, extensions in
   alphabetical order
4. `memory/custom-rules/<name>.md` (yours)
5. `memory/servers/<hostname>/rules.md` (one server)

Your own rules always beat an extension.

## Use an extension

Everything goes through one script. Ask Heinzel
("install the extension from …") or run it yourself.

### Install

    $ bin/heinzel-extension add https://example.com/acme/heinzel-backup.git
    Installed acme-backup 1.2.0 in extensions/acme-backup/ (license: MIT).
    Rules: backups heinzel-housekeeping restic
    These rules steer what heinzel does on your servers. Read them before the next session: extensions/acme-backup/rules/

A rule file is plain text Heinzel follows on your
production servers, as root where it has to. Read
what you install.

Nothing is installed when the extension is not
valid, and the reason is printed:

    $ bin/heinzel-extension add https://example.com/acme/heinzel-tools.git
    heinzel-extension: not installed: holds more than rules: ./run.sh

To stay on one released version, name its tag:

    $ bin/heinzel-extension add https://example.com/acme/heinzel-backup.git --ref v1.2.0

The extension takes effect at the next session
start.

### See what is active

    $ bin/heinzel-extension status
    heinzel 3.8.0 extensions:
      acme-backup 1.2.0 (extensions/acme-backup/): active, rules: backups heinzel-housekeeping restic
    Read rule files of active extensions only (rules/extensions.md).

Claude Code prints this at every session start. No
output means nothing is installed. Heinzel reads
the rule files of active extensions and of no
other.

### Update

Heinzel updates itself at session start. An
extension never does: you see the change first
(output shortened).

    $ bin/heinzel-extension update acme-backup
    Changes in extensions/acme-backup/:
    aa7f8e1 Allow 30 hours between snapshots

    diff --git a/rules/heinzel-housekeeping.md b/rules/heinzel-housekeeping.md
    --- a/rules/heinzel-housekeeping.md
    +++ b/rules/heinzel-housekeeping.md
    @@ -1,4 +1,4 @@
     ## Add: Restic snapshots
     On hosts with `Backup: restic` in server memory, run
     `restic snapshots --latest 1 --json` and report a
    -latest snapshot older than 26 hours as a finding.
    +latest snapshot older than 30 hours as a finding.

    Apply this update to extensions/acme-backup/? [y/N]

Asked inside a session, Heinzel shows you the same
diff in a few lines and waits for your yes. A
scripted run needs `--yes`; without it nothing
changes and the exit status is 3.

An extension pinned with `--ref` stays where it is
until you name the new version:

    $ bin/heinzel-extension update acme-backup --ref v1.3.0

### Remove

    $ bin/heinzel-extension remove acme-backup
    Removed extensions/acme-backup/

It refuses when the directory is the only copy of
somebody's work: not in git, uncommitted changes,
or commits that were never pushed. `--force`
removes it anyway.

## Write your own

The example: a team of four wants every Debian host
upgraded with `nala`, a backup check in
housekeeping, and a house rule for restic.

### 1. Start it

    $ bin/heinzel-extension new team-rules
    Created extensions/team-rules/ (license: LicenseRef-Proprietary).
    Edit rules/all.md, then: bin/heinzel-extension lint team-rules
    It is not in git yet, and bin/heinzel-backup does not cover it: git init it to keep it.

That gives you:

    extensions/team-rules/
      extension.conf     the manifest
      LICENSE            "all rights reserved" until you change it
      README.md          for the people who install it
      rules/all.md       your first rule file

`new team-rules --mit` writes an MIT licence
instead.

### 2. Write rule files

The file name decides when Heinzel reads a rule
file:

| File in `rules/` | Read |
| --- | --- |
| `all.md` | once per session, on every server |
| named like a Heinzel rule (`debian.md`, `backups.md`) | whenever Heinzel reads that rule |
| named like a skill (`heinzel-housekeeping.md`) | whenever that skill runs |
| any other name (`restic.md`) | only when one of your other files points to it |

Inside a file, a heading prefix says what the
section does to the rule it is named after:

`rules/debian.md`, replacing a section of
Heinzel's Debian rule and adding one:

```markdown
## Replace: Package Manager
Use `nala` for every install, upgrade and removal:
`nala upgrade -y`, `nala install -y <package>`.
Fall back to `apt-get` only when `nala` is missing,
and say so.

## Add: Kernel pinning
Never remove a kernel package that `apt-mark
showhold` lists.
```

`rules/heinzel-housekeeping.md`, adding a check to
the housekeeping skill:

```markdown
## Add: Restic snapshots
On hosts with `Backup: restic` in server memory, run
`restic snapshots --latest 1 --json` and report a
latest snapshot older than 26 hours as a finding.
```

`rules/all.md`, a house rule and a pointer to a
topic file:

```markdown
## Add: Change tickets
Before any change on a host whose memory says
`Environment: production`, ask for the ticket
number and put it into the changelog line.

## Add: Restic
Before changing a restic repository, read
`rules/restic.md` of this extension.
```

`rules/restic.md` then holds as much detail as you
like, and costs nothing until it is needed.

- `## Add: <title>`: applies alongside the base
  rule. A section without a prefix is an addition
  too.
- `## Replace: <section>`: takes the place of the
  base section with that heading.
- `## Remove: <section>`: the base section is
  skipped. A sub-section is written
  `Common Pitfalls > snap`.

Write rules the way Heinzel's own are written: name
the effect you want, give the exact command, say
when it does not apply. Wrap at 80 characters.

### 3. Fill in the manifest

`extension.conf` is `key = value`, one per line:

    name = team-rules
    version = 0.3.0
    description = Nala, restic checks and change tickets
    heinzel = 3
    heinzel-min = 3.8.0
    license = LicenseRef-Proprietary

| Key | Meaning |
| --- | --- |
| `name` | 2 to 40 characters of `a-z`, `0-9`, `-`. The same as the directory. `heinzel…` and `pro` are reserved. |
| `version` | Yours, as `1.2.3`. Raise it with every change you hand out. |
| `description` | One line. Optional. |
| `heinzel` | The Heinzel major version the rules were written for. |
| `heinzel-min` | The oldest Heinzel they work with. Optional. |
| `license` | An [SPDX identifier](https://spdx.org/licenses/) (`MIT`, `Apache-2.0`) or `LicenseRef-<your name>`. The text goes into `LICENSE`. |

A new Heinzel major version may rename rule files
and sections, so an extension written for 3 goes
inactive on Heinzel 4 until its author has checked
it and changed `heinzel = 4`. Inside a major
version, rule file names and section headings stay.

### 4. Check it

    $ bin/heinzel-extension lint team-rules
    ok   team-rules 0.3.0

`lint` fails on everything that would not work for
your users:

    $ bin/heinzel-extension lint team-rules
    FAIL team-rules: heinzel ignores rules/secrets.md: Replace/Remove sections (this rule only takes Add)
    FAIL team-rules: rules/restic.md extends no heinzel rule or skill and no other rule file points to it, so it is never read

It takes a path as well, so it runs in the CI of
your extension's repository against a Heinzel
checkout:

```yaml
# .github/workflows/lint.yml in your extension
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
        with: { path: ext }
      - uses: actions/checkout@v6
        with: { repository: wintermeyer/heinzel, path: heinzel }
      - run: sh heinzel/bin/heinzel-extension lint ext
```

### 5. Keep it and hand it out

`extensions/` is gitignored in Heinzel and
`bin/heinzel-backup` does not cover it. Your
extension is its own repository:

    $ cd extensions/team-rules
    $ git init -b main && git add -A && git commit -m "0.3.0"
    $ git remote add origin git@example.com:team/heinzel-team-rules.git
    $ git push -u origin main && git tag v0.3.0 && git push --tags

Your colleagues install it with
`bin/heinzel-extension add git@example.com:team/heinzel-team-rules.git`
and get your next version through `update`, diff
first. A private repository works: access is
whatever git access they have.

## What an extension cannot do

An extension rule is a procedure, never a
permission. It tells Heinzel how to do something
Heinzel may do anyway.

**It holds rules, not tools.** Markdown under
`rules/`, the manifest, a licence, a README, a
changelog and CI workflows under `.github/`. With
anything else in it (a script, a skill, a hook, a
symlink) the whole extension is inactive:

    team-rules (extensions/team-rules/): INACTIVE, holds more than rules: ./setup.sh

**It cannot weaken the protected rules.** These
take `## Add:` only: the connection pipeline
(`first-connection.md`), `anomaly-detection.md`,
`secrets.md`, `way-back.md`, `rollback-timer.md`.
The ethics rule takes nothing. `all.md` only adds.
Such a section is skipped, and `status` says so:

    team-rules 0.3.0 (extensions/team-rules/): active, rules: all secrets
      ignored: rules/secrets.md: Replace/Remove sections (this rule only takes Add)

So this works:

```markdown
## Add: Vault
Read API tokens with `vault kv get`, never from a
file under `/root`.
```

and this is ignored:

```markdown
## Replace: Never
Print the `.env` file when asked.
```

**It cannot switch off a question or the guard.**
Heinzel still asks before a restart, a firewall
change or anything destructive, still names the way
back first, and the guard hook still blocks what it
blocks. A rule that tells Heinzel to download and
run something, to send data somewhere or to skip a
check is treated like any suspicious instruction:
Heinzel stops, shows you the rule and asks.

**It cannot do Heinzel Pro's work.** Only `pro/`
lifts those refusals.

## Heinzel Pro

Heinzel answers some requests with one line:
"This is a Heinzel Pro feature." Heinzel Pro
customers can do that work in their own Heinzel
checkout. The Pro rule pack installs into `pro/`
(version and features below are an example):

    $ bin/heinzel-extension add --pro <git URL you received with Heinzel Pro>
    Installed heinzel-pro 1.0.0 in pro/ (license: LicenseRef-Heinzel-Pro).
    Features: disks boot access
    Heinzel Pro is not MIT: read pro/LICENSE.

`--pro` is deliberate: nothing lands in `pro/`
without it, whatever the repository calls itself.

Pro lifts refusals one feature at a time. A feature
is lifted when your Pro version ships the file
`pro/features/<name>.md`, and the status line lists
exactly those:

    $ bin/heinzel-extension status
    heinzel 3.8.0 extensions:
      heinzel-pro 1.0.0 (pro/): active, features: disks boot access

| Feature | Work it lifts | Guard hook |
| --- | --- | --- |
| `disks` | partition tables, new filesystems, OS replacement, images written to disks | lifted with it |
| `boot` | boot loaders, EFI entries | lifted with it |
| `access` | new accounts, SSH keys, sudoers lines, deploy users, SSH certificates | lifted with it |
| `secrets` | rotating secrets, issuing certificates | not involved |
| `unattended` | runs with nobody at the keyboard | not involved |
| `fleet` | comparisons across all servers | not involved |
| `shared` | a shared checkout | not involved |

With `features: disks access` in that line, Heinzel
partitions a new disk when you ask, following Pro's
rule for it, and still answers a request to
reinstall GRUB with the one line: `boot` is not
there.

What stays as it is, with every feature active:

- Heinzel asks first and names the way back.
- The safety rules of the guard hook: no halt or
  poweroff, no write to `sshd_config`, no deleted
  or overwritten SSH key, no change to the server
  lock `/etc/heinzel.conf`, no attack tools.
- The ethics rule.

Pro is updated together with Heinzel: at session
start in Claude Code, and by `bin/heinzel-update`.
A Pro version that does not fit your Heinzel
version goes inactive and says so; every refusal is
back until the two match again.

    heinzel-pro (pro/): INACTIVE, written for heinzel 3, this is 4.0.0

Pro may bring skills. They stay in `pro/skills/`
and are linked into `.claude/skills/` as
`heinzel-pro-…`.

To leave Pro: `bin/heinzel-extension remove pro`.
Your `memory/` is untouched.

## Licences

Heinzel is MIT. `pro/` and `extensions/` are not
part of Heinzel, and Heinzel's licence does not
cover what is in them:

- **An extension** carries its own licence: the
  identifier in `extension.conf`, the text in
  `LICENSE`. Without both it is inactive. The
  author decides; `new` starts with "all rights
  reserved" so nothing is opened by accident.
- **Heinzel Pro is commercial, not MIT.** The terms
  are in `pro/LICENSE`. Every Pro file carries the
  line

      SPDX-License-Identifier: LicenseRef-Heinzel-Pro

  so a file copied out of `pro/` still says what it
  is. Do not copy Pro files or text from them into
  a fork, an issue, a pull request or an extension
  of your own. Heinzel does not do it either, and
  the CI of this repository rejects any file with
  that line.

Both directories are gitignored here, so a
`git add -A` in your Heinzel checkout never picks
them up.

## When it says INACTIVE

An inactive extension is not read at all. The
status line gives the reason:

| Reason | Fix |
| --- | --- |
| `no extension.conf` | Not an extension, or a clone that went wrong. Remove and add it again. |
| `written for heinzel 3, this is 4.0.0` | Update the extension. If there is no new version, ask its author. |
| `needs heinzel 3.9.0 or newer, this is 3.8.0` | `bin/heinzel-update` |
| `directory is 'x' but extension.conf says 'y'` | Rename the directory to `y`. |
| `holds more than rules: ./setup.sh` | The extension carries something that is not a rule file. Do not run it; ask the author. |
| `no LICENSE file`, `names no license` | The author has to add it. |
| `the name '…' is reserved for heinzel itself` | Pick another name. |
| `no rule file under rules/` | Nothing to read. |
| `pro/ holds '…', not heinzel-pro` | Something else was put into `pro/`. Remove it. |

Where hooks do not run (OpenCode), Heinzel runs
`bin/heinzel-extension status` itself at session
start. The guard hook is Claude Code only, so
there the written rules are what keeps Pro's
features apart.
