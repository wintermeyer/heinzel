# Firewall: native nftables, legacy rules, Docker

Three checks that `references/firewall.md` points to: a host
that filters with native nftables instead of ufw or
firewalld, iptables-legacy rules hidden next to nf_tables,
and ports Docker publishes past any of them. Linux only.

## Native nftables

Needs root or `sudo -n`; `nft` refuses to list for a normal
user. The grep keeps every table header and, for each input
chain, its name and `type` line:

```bash
systemctl is-active nftables
systemctl is-enabled nftables netfilter-persistent
nft list chains | grep -B1 -e ^table -e "hook input"
```

A packet has to pass every input chain of its family, so one
chain that drops is enough — an `accept` policy in another
table does not undo it. Default deny means one of:

- the input chain has `policy drop;`, or
- it has `policy accept;` but its last rule is an
  unconditional `drop` or `reject`. Check with:

  ```bash
  nft list chain <family> <table> <chain> | tail -3
  ```

A table of family `ip` covers IPv4 only; `inet` covers both.

Native nftables is *active* when `nftables.service` is
active or an input chain is default deny. Input chains that
fail2ban, Docker or kube-proxy add with `policy accept;`
filter nothing on their own.

- Not active → not a firewall: **CRITICAL** "No active
  firewall" when ufw and firewalld are inactive too
- Service active, not default deny → **WARN** "nftables
  input policy is not deny"
- Default deny, but `nftables.service` inactive and nothing
  in `is-enabled` reloads it → **WARN** "nftables rules will
  not survive a reboot"
- Default deny, service active → OK

## Mixed frameworks

On a host where `iptables` writes to nf_tables, rules loaded
through `iptables-legacy` still filter packets, but `nft` and
`iptables` do not show them. `iptables-legacy` loads its
kernel modules on demand, so calling it on a clean host
creates the tables it is meant to look for; the proc files
decide first whether it runs at all. Run as root: the proc
files are readable by root only.

```bash
iptables -V
if iptables -V 2>/dev/null | grep -q nf_tables &&
   cat /proc/net/ip_tables_names \
     /proc/net/ip6_tables_names 2>/dev/null | grep -q .; then
  iptables-legacy -S | grep -vc ^-P
  ip6tables-legacy -S | grep -vc ^-P
fi
```

- Either count > 0 → **WARN** "iptables-legacy rules active
  next to nf_tables, invisible to nft". List them with
  `iptables-legacy -S` and report which tool loads them.
- No count printed, or both 0 → OK

## Docker published ports

Docker rewrites the destination of published ports in the
`nat` table, before packets reach the INPUT chain that ufw
and firewalld filter
(https://docs.docker.com/engine/network/packet-filtering-firewalls/).
`-p 8080:80` is reachable from the internet even behind
`ufw default deny incoming`. Check whenever `command -v
docker` finds it; `docker ps` needs root or the `docker`
group:

```bash
docker info --format '{{.FirewallBackend.Driver}}'
docker ps --format '{{.Names}} {{.Ports}}'
for c in iptables ip6tables; do $c -S DOCKER-USER; done
```

A published port (an entry with `->`) is public unless bound
to `127.0.0.1:` or `[::1]:`. `ss` shows the same ports as
`docker-proxy` (`references/listening-services.md`); report
them once, here.

In `DOCKER-USER`, anything beyond `-N DOCKER-USER` (older
engines add a `-j RETURN` as well) is a user rule; read it
to see which ports and sources it covers.

`docker info` prints `iptables` or `nftables`; an engine
without that field predates the nftables backend. That
backend came with Docker Engine 29, is still experimental
and not available in Swarm mode
(https://docs.docker.com/engine/network/firewall-nftables/).
It has no DOCKER-USER chain; restrictions live in a separate
table with a base chain on Docker's hooks, visible in
`nft list chains`.

- Public port not covered by a DOCKER-USER rule (or its
  nftables equivalent) → **WARN** "Docker publishes
  <container> <port> past the firewall". Suggest binding it
  to `127.0.0.1` behind a reverse proxy, or a DOCKER-USER
  rule that limits the sources.
- All published ports local or restricted → OK
