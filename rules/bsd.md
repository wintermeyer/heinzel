# BSD (FreeBSD, NetBSD, OpenBSD)

What the three BSDs share. Read it together with
the OS file (`rules/freebsd.md`, `rules/netbsd.md`,
`rules/openbsd.md`); where the two disagree, the OS
file wins. Every command lives in the OS file: the
three differ in almost all of them.

## Base and Packages

The base system (kernel and userland) and the
packages are two things with two update tools.
Check both, report both, and never read "packages
up to date" as "system patched".

## Firewall

- Run the parse-only test before every load. The OS
  file names it.
- The SSH pass rule names no interface: a login
  through a tunnel (`wg*`, `tun*`) needs it too.
- Arm the rollback timer first
  (`rules/rollback-timer.md`). The rollback reloads
  the saved ruleset; it never switches the filter
  off, unless it was off before.

## Automatic Security Updates

None of the three applies updates on its own. Flag
that to the user. Applying them unattended is the
user's decision, never a default; the notify-only
baseline is in the OS file.

## Journal

No `journalctl`. `logger -t heinzel` writes to
syslog and the entries land in `/var/log/messages`.
syslogd escapes every non-ASCII byte, so journal
lines stay ASCII (`rules/changelog.md`).

## Common Pitfalls

- **No `systemctl`, no `ip`, no `/etc/os-release`.**
  Services, interfaces and the version each have
  their own tool per OS.
- **No `sudo` in base.** The line that grants it
  (`sudoers`, `doas.conf`) is Heinzel Pro's work:
  write it into the report.
- **`pkill -f '<pattern>'` and `pgrep -f`** also
  match the shell that runs them. Over SSH that is
  heinzel's own session.
- **The boot loader is Heinzel Pro's**
  (`CLAUDE.md` → What Heinzel does not do). Read it,
  report it.
