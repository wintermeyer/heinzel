# When SSH Stops Answering

A host that suddenly stops accepting SSH is often
fine: something on the way — a rate limit, an IPS, a
firewall — has blocked the client, frequently because
of heinzel's own burst of connections (see
`rules/ssh-connections.md`).

## Do not retry in a loop

Reconnecting on failure is exactly the pattern rate
limits and IPS rules punish, and it keeps an existing
block alive.

1. Retry **once** with the fresh-login options
   (`CLAUDE.md` → SSH Options) — a stale shared
   connection is the cheap explanation.
2. If that fails too, stop. Wait several minutes
   before the next attempt, and never wrap SSH in an
   automatic retry.

## Target or path?

Signs that something **on the way** blocks, not the
host: ICMP answers but the SSH port times out (no
`Connection refused`); other ports on the same
address stay open; `Connection timed out during
banner exchange`; it worked a few times, then
stopped, and recovers by itself after minutes.

Confirm in **one call to a neighbour host** in the
target's network:

    ssh … neighbour 'curl -fsS -o /dev/null <health-url>;
      nc -z -w 3 <target> 22 && echo ssh-port-open'

Both fine there → the host is healthy and the block
sits on the client's path. Reproducing it needs a
vantage point behind the **same firewall as the
client**; tests from inside the target network look
clean and prove nothing. Do not chase routing, NAT or
MTU first — tunnel MTUs around 1280–1420 are normal.
Firewall and IPS changes: `CLAUDE.md` → Firewall &
network.

## Dual-stack

`ssh` prefers IPv6 and clients fall back to IPv4
quickly, so a block on one family reads as "works
sometimes". Probe both without logging in — a shared
connection would otherwise answer for either:

    nc -z -4 -w 5 <host> 22; nc -z -6 -w 5 <host> 22

If one family answers and the other does not, and
only on the SSH port, suspect a per-family filter.

## Exceptions for IPS and rate limits

When the user decides to exempt heinzel's traffic:

- **An exception covers only the address family
  written in it.** Check both, with the probe above.
- **Prefer destination-side exceptions** (the
  servers' addresses). Client IPv6 prefixes from
  consumer ISPs rotate, and exempting a whole client
  network removes its internet traffic from
  inspection too.
