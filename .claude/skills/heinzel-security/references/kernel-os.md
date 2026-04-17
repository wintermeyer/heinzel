# Kernel / OS Security — Linux

These checks read sysctl values. No root needed.

## ASLR (Address Space Layout Randomization)

```bash
sysctl -n kernel.randomize_va_space
```

- `0` → **CRITICAL** (ASLR disabled)
- `1` → **WARN** (partial — should be 2)
- `2` → OK (full randomization)

## IP Forwarding

```bash
sysctl -n net.ipv4.ip_forward
```

On macOS:

```bash
sysctl -n net.inet.ip.forwarding
```

- `1` → **WARN** unless the server's `memory.md` mentions
  WireGuard, VPN, or router functionality. In that case → OK
  with note.
- `0` → OK

## ICMP Redirect Acceptance — Linux only

```bash
sysctl -n net.ipv4.conf.all.accept_redirects
```

- `1` → **WARN**
- `0` → OK

## SUID Core Dumps — Linux only

```bash
sysctl -n fs.suid_dumpable
```

- `1` → **WARN** (allows core dumps from SUID programs, potential
  information leak)
- `0` or `2` → OK (`2` is "suidsafe" — restricted)
