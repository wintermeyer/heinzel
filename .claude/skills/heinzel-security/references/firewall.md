# Firewall

## Linux

Verify a firewall is installed, active, and the default incoming
policy is deny/drop. An inactive or missing firewall on a Linux
server is **CRITICAL** — aligned with the housekeeping severity.

Three variants count as a firewall: ufw, firewalld, and native
nftables (Debian's own default: `nftables.service` loading
`/etc/nftables.conf`). Check them in that order and judge the
host by the first one that is active. Report **CRITICAL** "No
active firewall" only when none of the three is.

`references/firewall-nftables-docker.md` checks native
nftables and iptables-legacy rules. Run its Docker check
whenever `command -v docker` finds Docker, whatever the
firewall.

### Debian/Ubuntu (ufw)

```bash
ufw status verbose
```

- Not installed or inactive → check native nftables
- Active but default incoming is not `deny` → **WARN** "Firewall
  default incoming policy is not deny"
- Active and default deny → OK

### RHEL/Fedora/SUSE (firewalld)

```bash
firewall-cmd --state
firewall-cmd --get-default-zone
```

Then check the default zone's target:

```bash
firewall-cmd --zone=<zone> --get-target
```

- Not running → check native nftables
- Zone target is `ACCEPT` → **WARN** "Default zone target is
  ACCEPT (allows all incoming)"
- Zone target is `default` (reject/drop) → OK

## macOS

Check Application Firewall status:

```bash
/usr/libexec/ApplicationFirewall/socketfilterfw \
  --getglobalstate
```

- Disabled → **INFO** (not WARN — common on macOS behind NAT,
  consistent with housekeeping severity)
- Enabled → OK
