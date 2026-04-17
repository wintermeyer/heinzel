# Firewall

## Linux

Verify a firewall is installed, active, and the default incoming
policy is deny/drop.

### Debian/Ubuntu (ufw)

```bash
ufw status verbose
```

- Not installed or inactive → **WARN** "No active firewall"
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

- Not running → **WARN** "No active firewall"
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
