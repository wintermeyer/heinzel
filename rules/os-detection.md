# OS Detection (mandatory first step)

Before doing any work on a server, you **must** know
its OS.

## On first connection

0. **Check access control and DNS alias.** For remote
   servers: check blacklist, then read-only list
   (see `rules/access-control.md`), then DNS aliases
   (see `rules/dns-aliases.md`). If the hostname is
   an alias for a known server, skip OS detection.

1. Determine the OS: `uname -s`

   | `uname -s` | Read                              |
   |------------|-----------------------------------|
   | `Linux`    | `rules/linux.md` and step 2       |
   | `Darwin`   | `rules/macos.md`                  |
   | `FreeBSD`  | `rules/bsd.md`, `rules/freebsd.md` |
   | `NetBSD`   | `rules/bsd.md`, `rules/netbsd.md` |
   | `OpenBSD`  | `rules/bsd.md`, `rules/openbsd.md` |

   On NetBSD read the rule file before the next
   command: over SSH `PATH` lacks `/sbin` and
   `/usr/sbin` there. Anything else: tell the user,
   proceed cautiously with generic commands, and
   apply extra verify-before-running care.

2. **If Linux** — detect distro and version:
   ```
   . /etc/os-release && \
     echo "${ID}|${VERSION_ID}|${PRETTY_NAME}"
   ```
   Distro families: `debian`, `rhel`, `suse`,
   `arch`.
   **Unraid** (`ID=unraid-os`, also
   `/etc/unraid-version`) is not a family: read
   `rules/unraid.md` and skip the family mapping.
   Map the distro to a family via the os-release
   `ID` and `ID_LIKE` fields (e.g. `ubuntu` →
   `debian`; `centos`, `rocky`, `alma`, `fedora` →
   `rhel`; `opensuse*` variants → `suse`; `arch`,
   `cachyos`, `endeavouros` → `arch`). If no
   family file matches (e.g. Alpine), tell
   the user, proceed cautiously with generic
   commands, and apply extra verify-before-running
   care.
   Read `rules/<family>.md`.

3. Detect version and architecture, and gather
   hardware info, with the commands under **Version
   Detection** in the files just read.

4. Create a server memory file.

Every OS file has the same sections (Version
Detection, Package Manager, Firewall, Automatic
Security Updates, Service Manager, Service Classes,
Listening Ports, Journal, Rollback Timer, Common
Pitfalls), in the file itself or in `rules/linux.md`
/ `rules/bsd.md`. The other rule files point to them
by name. `bin/heinzel-lint-rules` checks that none
is missing.

## On subsequent connections

Subsequent connections run the same pipeline as the
first (see `rules/first-connection.md`), including
the blacklist and read-only checks. Specific to
known servers: read the memory file, the login's
`user-<login>.md`, changelog, and
`todo.md` (if present) before any work, read the
matching rule file, and verify the OS version is
still current — update memory if it changed.
