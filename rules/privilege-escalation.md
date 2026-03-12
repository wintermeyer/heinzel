# Privilege Escalation

## Sudo

When connecting as a non-root user and a privileged
action is first needed, probe:

```
sudo -n true 2>/dev/null
```

- **Exit code 0** -> sudo works. Record
  `- Sudo: passwordless` in server memory.
- **Non-0** -> sudo requires password (unusable).
  Record `- Sudo: requires password (unusable)`.
  Proceed to root SSH fallback.

On subsequent connections, check server memory for
the sudo flag.

## Root SSH Fallback

When sudo is unusable and a privileged action is
needed, probe root SSH access once:

```
ssh -o BatchMode=yes -o ConnectTimeout=5 \
  root@hostname "id" 2>&1
```

- **Works:** record `- Root SSH: available`.
- **Fails:** record the following and enter
  unprivileged mode:
  ```
  - Sudo: requires password (unusable)
  - Root SSH: unavailable
  - Privilege mode: unprivileged
  ```

Only probe when a privileged action is actually
needed.

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
