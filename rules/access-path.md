# Access Path

How heinzel reaches a host: directly over the LAN or
the internet, through a VPN or tunnel, or several of
these. It decides what may cut heinzel off.

## Which path this session took

`SSH_CONNECTION` is `client-ip client-port server-ip
server-port`; sshd and the SSH servers in VPN agents
all set it. Print it in the activity-check call
(`rules/activity-check.md`), no extra call:

```bash
echo "SSH_CONNECTION=$SSH_CONNECTION"
```

A jump host or `ProxyCommand` hides the path: the
server address is then the target's as the jump host
sees it. Check on the workstation first (no
connection):

```bash
ssh -G <host> | grep -i -e '^proxyjump ' -e '^proxycommand '
```

Any line other than `none`: **via** that jump host or
command (NetBird's `netbird ssh proxy`: via NetBird),
which then is part of the path. Otherwise the
**server address** says the path:

- an address of a mesh VPN agent on the host → **via
  that VPN** (`rules/mesh-vpn.md`, which also tells
  sshd from the agent's own SSH server)
- `127.0.0.1` or `::1` → **a local tunnel**
  (Cloudflare Tunnel, a port forward)
- private (`10/8`, `172.16/12`, `192.168/16`,
  `fc00::/7`) → **LAN**, or a site VPN
- `100.64.0.0/10` of no known agent: carrier-grade NAT
  or an unknown VPN; say unknown
- anything else → **WAN**

Local mode has no path.

## Other paths

Unknown until tested; record `untested`. Test one only
when it matters: before work that could cut the
current path (firewall on the SSH port or a VPN
interface, the VPN agent, the network config), when
the current path fails, or when the user asks. One
access test with the fresh-login options
(`rules/ssh-connections.md` → Access tests):

- to the direct address: `- IP:` in server memory
  (`rules/dns-aliases.md`) or one the user gives. Never
  one from `ip addr` on the host: a LAN address behind
  NAT says nothing about the workstation's route.
- to a VPN address: only if the workstation is in that
  VPN (`rules/mesh-vpn.md`, run locally).

Outcomes: `works`, `timeout` and `refused`
(`rules/ssh-unreachable.md` → Target or path?), or
`denied`: SSH answers, the login is refused; do not
repeat (`rules/ssh-connections.md` → 3).

## Only one way in

When the `Access:` line names a single path that
works, anything that cuts it cuts heinzel off: a
firewall change on it, stopping the VPN agent, a
bastion or port forward going away. Ask first, never
inside an unattended run, and test the path again
after the change. What cuts a VPN path:
`rules/mesh-vpn.md` → Agents.

## Memory

One `Access:` line per remote host in
`memory/servers/<hostname>/memory.md`:

```markdown
- Access: heinzel via Tailscale (web1.tail1234.ts.net,
  sshd); direct 203.0.113.10 timeout (2026-09-19)
- Access: direct (WAN); other paths untested
```

Update it when the session's path differs from it.
