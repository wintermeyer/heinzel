# Privilege Escalation

**Local mode:** when the target is the local
machine, skip the root SSH fallback entirely. If
sudo is unusable, go straight to unprivileged mode
(see `CLAUDE.md` → Local mode).

## Sudo

When connecting as a non-root user and a privileged
action is first needed, probe in one call:

```
command -v sudo && { sudo -n true; echo "rc=$?"; sudo -n -l; }
```

`sudo -n true` alone fails the same way for a user
who may run some commands without a password; the
listing tells them apart.

- **`sudo` not found** -> record
  `- Sudo: unavailable (not installed)`.
  Proceed to root SSH fallback.
- **`rc=0`** -> sudo works. Record
  `- Sudo: passwordless` in server memory.
- **`rc` non-0, listing printed** -> `NOPASSWD` for
  selected commands: mixed mode (below).
- **`rc` non-0, both say "a password is required"**
  -> record `- Sudo: requires password (unusable)`.
  With `-n`, sudo prints this also for a user with
  no sudoers entry; record
  `- Sudo: no sudoers entry (unusable)` only when
  the output says "not in the sudoers file" or "may
  not run sudo". Proceed to root SSH fallback.

When sudo is unusable, name the ways out once: a
`NOPASSWD` rule for heinzel's account limited to
what it needs, a role account (`rules/accounts.md`),
or unprivileged mode. Do not pick one yourself.

On subsequent connections, check server memory for
the sudo flag. Where accounts and sudo rules come
from: `rules/accounts.md`.

## Mixed Mode

`sudo -n -l` lists `NOPASSWD` rules for some
commands only. Record them in one line, full paths
as sudo prints them:

```
- Sudo: NOPASSWD for selected commands (mixed):
  /usr/bin/systemctl, /usr/bin/journalctl
```

- **Covered** (in the recorded list): run it with
  `sudo -n`, no pre-check. Only when a rule limits
  the arguments and the list cannot settle the call,
  `sudo -n -l <command> <args>` exits 0 if a rule
  allows exactly that call.
- **Not covered:** treat as if sudo were unusable:
  root SSH fallback, else defer it to the sysadmin
  report (Unprivileged Mode, step 3–4). Never try a
  covered command as a way around a missing one
  (an editor or pager under sudo opens a root
  shell); that is escalation the rule did not grant.
- **"a password is required" at run time:** the
  rules changed. Probe `sudo -n -l` again and update
  memory.

## Root SSH Fallback

When sudo is unusable and a privileged action is
needed, probe root SSH access once, with the
fresh-login options (`CLAUDE.md` → SSH Options) — a
shared root connection opened earlier would answer
even if root login has been disabled since:

```
ssh -o BatchMode=yes -o ConnectTimeout=5 \
  -o ControlMaster=no -o ControlPath=none \
  root@hostname "id" 2>&1
```

- **Works:** record `- Root SSH: available`.
- **Fails:** keep the recorded sudo line, add the
  following, and enter unprivileged mode:
  ```
  - Root SSH: unavailable
  - Privilege mode: unprivileged
  ```

Only probe when a privileged action is actually
needed. On later connections, read `Root SSH:` from
server memory instead of probing again: a refused
root login can count toward a fail2ban ban
(`rules/ssh-connections.md` → 3).

## Unprivileged Mode

When neither `sudo` nor root SSH is available.

**1. Announce** to the user that you'll work as
the current user and produce a sysadmin report.

**2. Continue with userspace:** read-only inspection,
home directory, user-space tools, user-level cron
and systemd services.

**3. Defer root tasks:** package install/remove,
system services, firewall, system config files,
system users/groups. Announce each deferral briefly.

**4. Sysadmin report** at session end:

```
## Sysadmin Report for [hostname]

These tasks require root access. The server runs
[OS].

### Package Installation
    apt-get install -y nginx
Why: [brief reason]

### Firewall
    ufw allow 80/tcp
Why: [brief reason]
```

Use distro-correct commands, group by category,
include specific commands and brief "why" context.
