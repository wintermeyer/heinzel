# When SSH Stops Answering

A host that suddenly stops accepting SSH is often
fine: a filter on the way blocks the client,
frequently because of heinzel's own connections (see
`rules/ssh-connections.md`).

## Login rejected

`Permission denied (publickey)` and `Too many
authentication failures` are answers, not outages:
no retry, no other user name, no root instead.
Guessed names and refused root logins are what
fail2ban counts, and its `ddos` and `aggressive`
modes count every rejected login
(`rules/ssh-connections.md` → 3). Tell the user.
For too many keys the fix is on the client:
`IdentitiesOnly yes` and one `IdentityFile` for the
host in `~/.ssh/config`; check with
`ssh -G <host> | grep -i identit`.

## Do not retry in a loop

This applies when SSH does not answer at all.

Reconnecting on failure is exactly the pattern rate
limits and IPS rules punish, and it keeps an existing
block alive.

1. Retry **once** with the fresh-login options
   (`CLAUDE.md` → SSH Options) plus `-v`. A stale
   shared connection is the cheap explanation, and
   `-v` shows every address tried (see Dual-stack).
2. If that fails too, stop. Wait several minutes
   before the next attempt, and never wrap SSH in an
   automatic retry.
3. Never try another port in its place
   (`rules/ssh-port.md`).

## Target or path?

Signs that something **on the way** blocks, not the
host: the address answers ping but the SSH port
times out (no `Connection refused`); `Connection
timed out during banner exchange`; it worked a few
times, then stopped, and recovers by itself after
minutes; another service on the same address still
answers:

    curl -sS -o /dev/null -w '%{http_code}\n' \
      https://<host>/

Then the host is up and a filter on the client's
path blocks SSH. Wait, or tell the user. Do not
chase routing, NAT or MTU. A check from inside the
target's network sees a clean path and proves
nothing about the client's. Firewall and IPS
changes: `CLAUDE.md` → Firewall & network.

## Dual-stack

OpenSSH tries a host's addresses one after another,
usually IPv6 first, and moves on only when an
address fails or `ConnectTimeout` runs out. A filter
that drops one family therefore shows as a delay of
`ConnectTimeout` on every new connection, and as a
failure once both families are blocked.

The `-v` retry shows it without an extra connection:

    debug1: Connecting to <host> [<address>] port 22.
    debug1: connect to address <address> port 22: <timeout>

One family timing out while the other connects
points to a per-family filter. A firewall or IPS
exception covers only the family written in it:
after adding one, test both with a fresh login
(`ssh -4 …`, `ssh -6 …`).

Do not probe with `nc -z` or `ssh-keyscan`: fail2ban
(modes `ddos` and `aggressive`) and sshd's
`PerSourcePenalties` count a connection that never
logs in. A successful login counts for neither.
