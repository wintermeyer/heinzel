# OS Detection (mandatory first step)

Before doing any work on a server, you **must** know
its OS.

## On first connection

0. **Check access control and DNS alias.** For remote
   servers: check blacklist, then read-only list
   (see `rules/access-control.md`), then DNS aliases
   (see `rules/dns-aliases.md`). If the hostname is
   an alias for a known server, skip OS detection.

1. Determine Linux, macOS, or FreeBSD: `uname -s`

2. **If Linux** — detect distro and version:
   ```
   . /etc/os-release && \
     echo "${ID}|${VERSION_ID}|${PRETTY_NAME}"
   ```
   Distro families: `debian`, `rhel`, `suse`.
   **Unraid** (`ID=unraid-os`, also
   `/etc/unraid-version`) is not a family: read
   `rules/unraid.md` and skip the family mapping.
   Map the distro to a family via the os-release
   `ID` and `ID_LIKE` fields (e.g. `ubuntu` →
   `debian`; `centos`, `rocky`, `alma`, `fedora` →
   `rhel`; `opensuse*` variants → `suse`). If no
   family file matches (e.g. Alpine, Arch), tell
   the user, proceed cautiously with generic
   commands, and apply extra verify-before-running
   care.
   Read `rules/<family>.md`. Gather hardware info
   (`lscpu`, `free -h`, `df -h`).

3. **If macOS** — detect version and arch:
   ```
   sw_vers -productVersion && uname -m
   ```
   Read `rules/macos.md`. Gather hardware info
   (`sysctl` for CPU/RAM, `df -h`).

4. **If FreeBSD** — detect version and arch:
   ```
   freebsd-version && uname -m
   ```
   Read `rules/freebsd.md`. Gather hardware info
   (`sysctl` for CPU/RAM, `df -h`,
   `zpool status` if ZFS).

5. Create a server memory file.

## On subsequent connections

Subsequent connections run the same pipeline as the
first (see `rules/first-connection.md`), including
the blacklist and read-only checks. Specific to
known servers: read the memory file, changelog, and
`todo.md` (if present) before any work, read the
matching rule file, and verify the OS version is
still current — update memory if it changed.
