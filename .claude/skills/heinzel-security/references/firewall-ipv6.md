# Firewall — IPv6 Coverage

A firewall that filters only IPv4 leaves every
service open over IPv6. Check this whenever the host
has a global IPv6 address (`ip -6 addr show scope
global`, or `network.md`). Linux only. Reading the
nftables or iptables rules needs root or `sudo -n`;
without either, list the check under "Skipped (needs
root)" (`references/unprivileged.md`).
`/etc/default/ufw` is world-readable.

**ufw:**

```bash
grep '^IPV6=' /etc/default/ufw
```

`IPV6=no` → ufw writes no IPv6 rules.

**firewalld:** filters both families in one ruleset.
No extra check.

**Neither ufw nor firewalld:** first find out which
kernel framework the `iptables` command writes to:

```bash
iptables -V
```

- `(nf_tables)`, or no `iptables` at all: nftables
  holds every rule, including those added through
  the `iptables` command. `iptables -S` shows only
  the latter and misses native rules from
  `/etc/nftables.conf`, so read nftables directly:

  ```bash
  nft list chains | grep -E '^table|chain |hook input'
  ```

  IPv6 is filtered when a chain with `hook input`
  sits in a table of family `inet` or `ip6` and has
  `policy drop` (or ends in a drop/reject rule — then
  check its rules with `nft list chain <family>
  <table> <chain>`). Input chains only in family `ip`
  are the gap.
- `(legacy)`: the old framework, invisible to `nft`.
  Compare the policies of both families:

  ```bash
  iptables -S INPUT | head -1
  ip6tables -S INPUT | head -1
  ```

  `-P INPUT DROP` for IPv4 next to `-P INPUT ACCEPT`
  for IPv6 is the gap.

No input chain in any family means no inbound
filtering at all — report that under "No active
firewall" in `references/firewall.md`, not here.

- The gap above → **CRITICAL** "Firewall does not
  filter IPv6"
