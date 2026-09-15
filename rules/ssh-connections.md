# SSH Connections: Few and Shared

sshd `MaxStartups` and `PerSourcePenalties` (OpenSSH
9.8+), fail2ban and sshguard, firewall rules that
rate-limit new connections to port 22, and network
IPS signatures for SSH scans ("N connections in M
seconds") all count **TCP connections, not
commands**. A busy heinzel session can trip them and
lock itself out — and the block looks like a broken
host. If that has already happened, see
`rules/ssh-unreachable.md`.

## 1. Bundle commands

One call per logical step, not one per command:

    ssh … host 'sh -s' <<'EOS'
    cmd1
    cmd2
    EOS

- Send several files in one `scp`/`rsync`.
- Do not poll a host every few seconds. Run a long
  job on the host (`nohup`, `systemd-run`, `daemon`)
  and read its log at an interval of minutes.
- `ProxyJump` costs a connection to the jump host
  **and** one to the target.

## 2. Share connections

The standard options in `CLAUDE.md` → SSH Options
turn on OpenSSH connection sharing (`ControlMaster`):
repeated calls ride **one TCP connection per local
user, remote user, host and port**. Later calls are
several times faster, open no new connection, and
key agents that confirm each use ask only once.

It does not help with the first connection per host
and remote user, with the first one after
`ControlPersist` expires, or with **failed logins**,
which are never shared and still earn
`PerSourcePenalties`.

### Why these values

- **On the command line, not in `~/.ssh/config`.**
  Sharing works on every machine heinzel runs from
  without setup. Command-line options take precedence
  over the config file, so a `ControlMaster` block the
  user keeps for their own sessions neither helps nor
  interferes.
- **Under `~/.cache/heinzel/`, not `~/.ssh/`.** The
  taboo guard (`.claude/hooks/guard-taboos.sh`) treats
  paths under `.ssh/` as SSH key material. A socket
  path there makes every remote command that runs
  `rm`, `mv` or `chmod` look like a key operation, and
  it is blocked. Not `/tmp` either: keep the socket in
  a directory only the local user can write to.
- **`%C`** is a fixed-length hash of local host,
  remote host, port, user and jump host. Readable
  names (`%r@%h:%p`) can exceed the Unix socket path
  limit (104 bytes on macOS); SSH then fails the call
  with `ControlPath too long` instead of falling back
  to a normal connection.
- **`ServerAliveInterval`** retires a master whose
  network path died (VPN switch, sleep). Without it,
  later calls can hang, and `ConnectTimeout` does not
  apply to a reused connection.

### Fresh-login options

The second option set in `CLAUDE.md` → SSH Options
(`ControlMaster=no`, `ControlPath=none`). Use it for:

- **Access tests.** Anything that answers "can this
  login still succeed?" — after changing
  `authorized_keys`, an account, its shell or groups,
  PAM, host keys, or firewall rules on the SSH port,
  and the root SSH probe in
  `rules/privilege-escalation.md`. A shared master
  answers from the login **before** the change, so a
  broken login reads as working. Make all related
  changes first, then run one fresh-login call that
  also prints what you need (`id; groups`).
- **A call that hangs or fails while sharing** — a
  stale master, or `Session open refused by peer`
  (sshd `MaxSessions`, default 10 per connection).
  Retry **once** this way. If that fails too, follow
  `rules/ssh-unreachable.md`.

Always write the fresh-login set out in full. Placed
after the standard options, `ControlPath=none` is
ignored — SSH keeps the first value of a repeated
option.

### Caveats

- **Never close a master you did not start.** Other
  heinzel sessions and scripts on the same local
  account use the same socket path, and
  `ssh -O exit`/`-O stop` ends their sessions too.
  For experiments, use a complete option set with its
  own path (e.g. `~/.cache/heinzel/test-%C`) and close
  only that one.
- **Login records understate activity.** `last`,
  `who` and the sshd log show one login for many
  calls. Use `rules/activity-check.md` to judge
  whether someone else is working on the host.
- **Security.** While a master is open, any process
  of the same local user can use it without key
  approval. Keep `~/.cache/heinzel` at `0700`; on a
  shared account, shorten `ControlPersist`.
