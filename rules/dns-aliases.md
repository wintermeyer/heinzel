# DNS Aliases

The same physical server can have multiple DNS names.
heinzel detects this automatically using the `- IP:`
field in server memory files.

**Canonical name** = the first hostname used for a
server. Additional DNS names become filesystem
symlinks to the canonical directory.

## Detection (on every new hostname)

When connecting to a hostname with no
`memory/servers/<hostname>/` directory (and not a
symlink):

1. **Resolve the IP(s) the way `ssh` does.** First
   apply the SSH client config: a `Host` alias in
   `~/.ssh/config` can point anywhere through
   `HostName`. `ssh -G` prints the name ssh will
   really connect to, without connecting:
   ```
   ssh -G <hostname> 2>/dev/null | \
     awk '$1=="hostname"{print $2}'
   ```
   Resolve that name. Ask the system resolver, not
   DNS directly: only it sees `/etc/hosts`, the
   search domain and the resolvers a VPN adds per
   domain (macOS scoped resolvers, systemd-resolved
   split DNS). Collect every IPv4 address, not just
   the first. On Linux:
   ```
   getent ahostsv4 <hostname> | \
     awk '{print $1}' | sort -u
   ```
   On macOS:
   ```
   dscacheutil -q host -a name <hostname> | \
     awk '$1=="ip_address:"{print $2}' | sort -u
   ```
   Elsewhere (FreeBSD), use `getaddrinfo`:
   ```
   python3 - <hostname> <<'EOF'
   import socket, sys
   for a in sorted({i[4][0] for i in socket.getaddrinfo(
           sys.argv[1], None, socket.AF_INET)}):
       print(a)
   EOF
   ```
   Only when neither is available, query DNS with
   `dig`, which misses everything above. Filter for
   addresses — a bare `dig +short` can return a
   CNAME target instead of an IP:
   ```
   dig +short +time=2 +tries=1 A <hostname> | \
     grep -E '^[0-9.]+$'
   ```
   Verify the syntax of the tool you use on the
   machine running the query (see CLAUDE.md →
   Verify Before Running). If the blacklist or
   read-only check already resolved the name this
   way, reuse that result; otherwise resolve it
   here. If nothing resolves, the IP comparisons
   cannot run: tell the user so.

2. **Compare against known servers.** Scan existing
   `memory/servers/*/memory.md` files (skip
   symlinks) for a matching `- IP:` line and the
   same SSH port (`rules/ssh-port.md` → NAT and
   aliases).

3. **Match found -> alias.**
   - Create symlink:
     `ln -s <canonical> memory/servers/<alias>`
   - Add `- DNS alias: <alias>` to canonical
     `memory.md`.
   - Skip OS detection.

4. **No match -> new server.** Normal first-connection
   flow. Include resolved IP as `- IP:` field.

## Subsequent Connections via Alias

Follow the symlink, read canonical `memory.md`. Use
the **alias hostname** (not canonical) for SSH
commands and `user.md` lookups. Each alias can have
its own SSH user.

## IP Verification

On every connection to a known server, verify the
current IP matches `- IP:` in memory. Resolve as in
Detection step 1 and compare against the full set
of resolved IPs: round-robin DNS gives a host
multiple A records, and any overlap with the stored
IP(s) counts as a match. Note multi-A hosts in
server memory instead of alarming. Only when there
is no overlap at all, **stop and tell the user.**
Ask whether the server migrated (update IP) or the
alias now points elsewhere (detach it).

## Removing an Alias

1. Delete the symlink from `memory/servers/`.
2. Remove the `- DNS alias:` line from canonical
   `memory.md`.
3. Remove the alias from `memory/user.md` if present.
