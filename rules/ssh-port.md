# SSH Port

The port sshd answers on is a fact of the host, not
a personal preference. It lives in server memory
(`memory/servers/<hostname>/memory.md`), so a team
that shares server memory shares it too — unlike
the SSH user name, which is personal and lives in
`memory/user.md` (`rules/ssh-user.md`).

    - SSH port: 2222

No line means port 22. Never write `- SSH port: 22`.

## Known port

- **The user names one** — `host:2222`,
  `ssh://user@host:2222`, `-p 2222`, "port 2222".
  Strip the port from the hostname before any memory
  lookup, blacklist check or directory name:
  `host:2222` is `memory/servers/host/`. An IPv6
  address carries a port only in brackets
  (`[2001:db8::1]:2222`); a bare one has none.
- **Known host, different port named:** replace the
  line and say so in one line. A port named once for
  a single call ("try 2200 this time") is not
  stored.
- **`~/.ssh/config` sets `Port`** for the host: ssh
  uses it without help, so heinzel adds nothing and
  does not copy it into memory — two sources drift.

On a first connection the memory file does not
exist until step 6 of `rules/first-connection.md`.
Use the port for every call of the onboarding and
write the line when the file is created.

## Use

With a stored port, add `-o Port=<port>` to the
standard or the fresh-login options
(`CLAUDE.md` → SSH Options) on every call:

    ssh -o BatchMode=yes … -o Port=2222 user@host
    scp -o BatchMode=yes … -o Port=2222 file user@host:
    rsync -e "ssh -o BatchMode=yes … -o Port=2222" …

Use `-o Port=` rather than the short flags: ssh
takes `-p`, but scp and sftp take `-P`, and a mix-up
sends the call to port 22.

A stored port wins over a `Port` in
`~/.ssh/config` (`CLAUDE.md` → SSH Options).

## Finding the port on first contact

Only when the user named no port, server memory has
none and the host is new. Known hosts never go
through this: if their port stops answering, follow
`rules/ssh-unreachable.md`.

### 1. Look in known_hosts — no connection

Skip this when the user has no alternative ports
(step 3). Otherwise check each of them in one call:

    ssh-keygen -F '[<host>]:52222'; ssh-keygen -F '[<host>]:2222'

A `# Host [<host>]:<port> found` line means the user
accepted that host's key on that port before, hashed
entries included. Use that port for the first call;
if it refuses or times out, continue with step 2
and skip it in step 3. A `Port` in `~/.ssh/config` needs no check: the plain
call in step 2 already uses it.

### 2. Try port 22

As usual. Read the error:

- `Connection refused` — the host is up, nothing
  listens on 22. Go to step 3.
- Timeout — the host is down or a filter drops the
  packets. Do **not** try other ports: that adds
  connections to a block that may be heinzel's own.
  Follow `rules/ssh-unreachable.md`, then ask
  (step 4).
- Any other answer (`Permission denied`, `Host key
  verification failed`, a login) — sshd is on 22.
  Handle it as usual.

### 3. Try the user's alternative ports

`memory/user.md` may list the ports the user runs
sshd on instead of 22 (`rules/ssh-user.md`):

    Alternative SSH ports: 52222, 2222

Try them in that order, **once each**, at most
three. A refused port: next one. A timeout: stop and
ask (step 4) — the host is now dropping packets. A
successful login: record the port as `- SSH port:`.
Any other answer (`Permission denied`, a banner
error): stop and ask — something listens there, but
it may be a container's SSH, not the host's sshd.

heinzel keeps **no** list of "common" ports: several
ports in a row on one host look like a port scan to
psad, portsentry and provider IPS. Never scan
(`nc -z`, `nmap`, `ssh-keyscan`;
`rules/ssh-connections.md` → 3).

### 4. Ask

Same picker rules as `rules/ssh-user.md`
(`AskUserQuestion`, ASCII fallback). Question:
*"Port 22 on `<host>` <refused / timed out>. Which
SSH port should heinzel use?"* Options:

1. the first alternative port not yet tried —
   "from your alternative ports"
2. `2222` — "a frequent alternative"
3. `Other…` — "type a port"

Drop an option whose port was already tried. If
both are gone, ask for the port as plain text.

Connect once with the answer. On success, record it
as `- SSH port:`. If the port is not yet in
`Alternative SSH ports:`, ask once more, on its own:
*"Also try `<port>` on new hosts when 22 refuses?"*
(yes / no). Yes appends it in `memory/user.md`.

## NAT and aliases

Behind a port forward, one address can reach
several hosts: `gw.example.com:2201` and
`gw.example.com:2202` are two machines. For alias
detection (`rules/dns-aliases.md`) a match needs the
same address **and** the same SSH port.

If the user named no port for the new name and the
address matches known hosts with a stored port, the
port is still open at that point. Ask which known
host it is (picker: each match as `host:port`, plus
"a different machine") instead of assuming 22.

The port heinzel connects to can also differ from
the port sshd listens on: a router forwards 2222 to
22 inside. The stored port is the connect port.

## Firewall

A firewall rule must keep open the ports sshd
**listens** on, not the connect port — all of them
when `sshd -T` lists several. Read them on the host
in the same call as the firewall status, before any
change:

    sshd -T | grep -i '^port '

(as root; unprivileged: `ss -tlnp` or
`sockstat -4l` on FreeBSD and look for sshd.)

If it is not 22, the shortcuts in the family rule
files open the wrong port: `ufw allow OpenSSH` and
firewalld's `--add-service=ssh` cover 22 only. Use
the port instead:

    ufw allow <port>/tcp
    firewall-cmd --permanent --zone=<zone> --add-port=<port>/tcp
    pass in on $ext_if proto tcp to port <port>   # pf
