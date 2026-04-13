# OS Detection (mandatory first step)

Before doing any work on a server, you **must** know
its OS.

## On first connection

0. **Check access control and DNS alias.** For remote
   servers: check blacklist, then read-only list
   (see `rules/access-control.md`), then DNS aliases
   (see `rules/dns-aliases.md`). If the hostname is
   an alias for a known server, skip OS detection.

1. Determine Linux or macOS: `uname -s`

2. **If Linux** — detect distro and version:
   ```
   . /etc/os-release && \
     echo "${ID}|${VERSION_ID}|${PRETTY_NAME}"
   ```
   Distro families: `debian`, `rhel`, `suse`.
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

1. Read memory file and changelog.
2. Check for `todo.md`.
3. Run the activity check
   (see `rules/activity-check.md`).
4. Read the matching rule file.
5. Verify OS version is still current. Update memory
   if changed.
