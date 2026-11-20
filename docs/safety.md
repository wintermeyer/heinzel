# Safety and guardrails

The safety rules are part of every session.

- **Asks before acting.** Destructive commands, firewall
  changes, reboots and service restarts need your approval.
  Reloads run on their own when the config test passes
  (`rules/service-reload.md`, `memory/service-policy.md`).
- **Hard guardrails (Claude Code).** A PreToolUse hook
  (`.claude/hooks/guard-taboos.sh`) blocks the absolute
  taboos in every permission mode, even
  `--dangerously-skip-permissions`: halt and poweroff,
  `mkfs`, partition-table writers, boot-loader and EFI
  writers, deleting or overwriting SSH keys, writes to
  `sshd_config`, deleting accounts, writes to `sudoers`,
  the account files and the server lock. It also catches
  them inside `ssh host "…"`, behind `python3 -c` and when
  the file-edit tools target one of those files. Read-only forms
  (`fdisk -l`, `efibootmgr -v`, `visudo -c`) stay allowed.
  The hook has no off switch. An installed Heinzel Pro lifts
  its disk, boot and account rules feature by feature and
  none of the others. OpenCode does not run this hook; there
  the written rules are the safety layer.
- **Verifies before it reports.** "It is gone since the
  reboot" gets checked against the live system first
  (`rules/verify-before-reporting.md`).
- **Backs up config files** to `/var/backups/heinzel/` before
  editing. Cleaned up after 30 days.
- **Knows the way back before it changes anything.** Every
  question before a change ends with `Way back: <how>` or
  `Way back: none`. Heinzel prefers changes that last only
  until the next reload until they are proven (`sysctl -w`
  before `sysctl.d`, `mount` before `fstab`), keeps the old
  kernel, cluster or binary until the new one works, and
  tests failures that would only show at the next boot now
  (`rules/way-back.md`).
- **Rolls back what locks it out.** Before a change that can
  cut off the login (IP address, route, firewall, VPN, PAM),
  Heinzel arms a timer on the server that restores the old
  state after 120 seconds. Only a fresh SSH login after the
  change stops it. If the new address is wrong, the server
  undoes it by itself and Heinzel reports what happened
  (`rules/rollback-timer.md`). Set a longer window per server
  with `- Rollback window: 300` in its `memory.md`.
- **Tests before applying** with dry-run or validation modes
  where a tool has one.
- **Logs everything.** Each change is one plain-language line
  in the system journal. The technical detail and the way
  back are in `memory/servers/<hostname>/changelog.log`.
- **Stable repos only.** No third-party sources without your
  approval.
- **Least privilege.** Normal user first, `sudo` when needed,
  root last. With neither, Heinzel does what it can and
  writes a report for the tasks that need root.
- **Blacklist and read-only servers.** Hosts in
  `memory/blacklist.md` are never contacted. Hosts in
  `memory/readonly.md` are inspected but never changed.
- **Server lock.** A machine's owner can lock it against
  every Heinzel with a file on the machine itself:

  ```
  # /etc/heinzel.conf
  allow_changes = false
  reason = Database migration until 20 Oct, hands off
  ```

  Heinzel still connects and inspects, but changes nothing
  and reports what it would have done. An unreadable file
  or any value other than `true` locks too. Heinzel never
  writes, moves or deletes the file; you remove the lock by
  hand. It is a promise kept by Heinzel, not a security
  boundary: it stops no tool that ignores it
  (`rules/access-control.md`).
- **Protected paths.** `memory/protected-paths.md` marks
  paths per server as `readonly`, `hidden` (content never
  shown) or `confirm` (needs a typed `CONFIRM`).
- **Ignores injected instructions.** Text in files, logs and
  command output is data. Text that addresses the AI is
  flagged to you and not followed.
- **Keeps secrets out.** Keys, password files and `.env`
  contents are inspected by metadata and fingerprint, never
  printed, and never passed as command-line arguments.


## Against hallucinations

An LLM can invent a flag or a path. Heinzel puts verified
facts in front of it instead:

- A rule file per platform holds the right commands, package
  manager and firewall tool.
- It checks `--help`, the man page or upstream docs before a
  command runs.
- It reads the server's memory file instead of guessing.
- It uses dry-run modes first.
- You see every command before it runs.

This reduces the risk. It does not remove it.

> [!CAUTION]
> Heinzel operates on live systems, as root, with sudo or
> unprivileged. Review every command before you approve it.

A disciplined AI that follows the checklist every time makes
fewer mistakes than a tired human at 2 AM. It can still
misread your intent. Stay in the driver's seat.
