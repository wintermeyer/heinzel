# Network Profile

What heinzel records about a host's network, how
it probes it, and what counts as a finding. The
profile answers four questions before anyone
touches the network:

1. **Who owns the configuration?** Which manager,
   which file, and whether something regenerates it.
2. **What is the stack?** IPv4 and IPv6, which
   address ranges, static or dynamic.
3. **Does it work?** Default routes, name
   resolution, and outbound reachability per
   address family. Configured IPv6 is often broken
   IPv6.
4. **Does the outside agree?** A, AAAA and PTR
   records against the addresses the host really
   has.

Every probe here is read-only.

## When

- **Full profile:** on first connection, on a known
  host without `network.md`, when `Probed:` is older
  than 90 days, and when the user asks about the
  network. Announce it in one line ("network profile
  for this host — one moment").
- **Every other connection:** the quick check in
  `rules/first-connection.md` step 7. Re-run the full
  profile only when it shows a difference.
- **After heinzel changes** anything in the network,
  DNS or firewall configuration: re-run the profile
  and update `network.md` in the same step.

Linux needs one SSH call for the whole profile.
Nothing needs root except the netplan grep, which
follows the privilege ladder of the fleet audit
(`sudo -n`, else `unknown(needs-root)`).

## Where it goes

`memory/servers/<hostname>/network.md`, next to
`memory.md`. `memory.md` keeps its `- IP:` line
(`rules/dns-aliases.md` depends on it) and gains one
summary line:

```markdown
- Network: dual-stack, v6 egress OK — see network.md
```

`network.md` holds current facts only. Replace
stale values; do not append history (that is what
`changelog.log` is for):

```markdown
# Network — host.example.com
Probed: 2026-09-19

## Summary
- Stack: dual-stack (v4 public, v6 GUA)
- Egress: v4 OK, v6 OK (deb.debian.org)

## Management
- Manager: netplan → systemd-networkd
- Source: /etc/netplan/50-cloud-init.yaml
- cloud-init: owns network config (datasource
  as reported by cloud-id)
- Conflicts: none

## Interfaces
- Uplink: eth0, MTU 1500, physical
- Overlay: wg0 · Container interfaces: 3
- Virtualization: kvm

## IPv4
- 203.0.113.10/32 static, public
- Default: via 172.31.1.1 dev eth0

## IPv6
- 2001:db8:1:2::1/64 static, GUA
- Default: via fe80::1 dev eth0, static
- RA: networkd (userspace), kernel accept_ra 0
- Forwarding: 0 · Temporary addrs: none
- Interface ID: manual · DNS64: none

## DNS
- resolv.conf: symlink → systemd-resolved stub
- Upstream: 2 v4 + 1 v6 on eth0, link-provided
- Search: none · DNSSEC: no · DoT: no
- nsswitch hosts: files dns
- Own name: hostname -f resolves to itself

## Public DNS (from workstation)
- A: matches · AAAA: matches
- PTR v4: host.example.com, forward-confirmed
- PTR v6: missing

## Findings
- INFO: no PTR for 2001:db8:1:2::1
```

Record only what a probe showed. Never infer a
hosting provider from an address range or a
gateway; name one only when `cloud-id` or the user
said so (see CLAUDE.md → Never fabricate server
facts).

**Secrets.** Network configs can embed private keys
and passwords; `rules/secrets.md` lists them. The
probes read only named keys and never print a
config file whole. A proxy URL can carry a
password: report that a proxy is set, never its
value.

## Probe — Linux

One call. `n` names the container and VM interfaces
that are counted, never listed; extend it in one
place when a new kind turns up. Set `T` first when
an override names the egress target (see Egress
test).

```bash
n='veth|cali|cni|flannel|vnet|tap|fwbr|fwpr|fwln|lxc'
n="$n|docker|br-[0-9a-f]{12}"
up=$(ip -4 route show default \
  | sed -n 's/.* dev \([^ ]*\).*/\1/p' | head -1)
[ -n "$up" ] || up=$(ip -6 route show default \
  | sed -n 's/.* dev \([^ ]*\).*/\1/p' | head -1)
# No default route at all: take the link SSH came in on.
[ -n "$up" ] || up=$(ip route get "${SSH_CONNECTION%% *}" \
  2>/dev/null | sed -n 's/.* dev \([^ ]*\).*/\1/p')
echo "uplink=$up"
[ -e "/sys/class/net/$up/device" ] && echo "uplink-physical=yes"
[ -d "/sys/class/net/$up/bridge" ] && echo "uplink-bridge=yes"
if [ "$(id -u)" = 0 ]; then S=""
elif sudo -n true 2>/dev/null; then S="sudo -n"
else S=-; fi

echo "### A manager"
for u in systemd-networkd NetworkManager networking \
         network wicked systemd-resolved resolvconf \
         dhcpcd connman; do
  printf '%s=%s\n' "$u" \
    "$(systemctl is-active "$u" 2>/dev/null)"
done
ls -d /etc/netplan/*.yaml /etc/network/interfaces \
  /etc/network/interfaces.d/* /etc/systemd/network/* \
  /etc/sysconfig/network-scripts/ifcfg-* \
  /etc/sysconfig/network/ifcfg-* 2>/dev/null
grep -hE '^[[:space:]]*(auto|allow-hotplug|iface) ' \
  /etc/network/interfaces \
  /etc/network/interfaces.d/* 2>/dev/null
if command -v networkctl >/dev/null 2>&1; then
  networkctl list --no-pager --no-legend \
    | grep -vE " ($n)"
  networkctl status "$up" --no-pager -n0 2>/dev/null \
    | grep -E 'Network File|State:|Address|Gateway|DNS'
fi
if command -v nmcli >/dev/null 2>&1; then
  nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device \
    2>/dev/null | grep -vE "^($n)"
  c=$(nmcli -g GENERAL.CONNECTION device show "$up" \
    2>/dev/null)
  [ -n "$c" ] && nmcli -g ipv4.method,ipv6.method \
    connection show "$c"
fi
if ls /etc/netplan/*.yaml >/dev/null 2>&1; then
  if [ "$S" = - ]; then echo "netplan=unknown(needs-root)"
  else $S grep -hE \
    '^[[:space:]]*(renderer|dhcp4|dhcp6|accept-ra):' \
    /etc/netplan/*.yaml
  fi
fi
if command -v cloud-init >/dev/null 2>&1; then
  echo "cloud-id=$(cloud-id 2>/dev/null)"
  echo "cloud-init-unit=$(systemctl is-enabled \
    cloud-init.service 2>/dev/null)"
  [ -e /etc/cloud/cloud-init.disabled ] \
    && echo "cloud-init=disabled"
  grep -rlsE 'config:[[:space:]]*disabled' \
    /etc/cloud/cloud.cfg /etc/cloud/cloud.cfg.d/
fi
echo "virt=$(systemd-detect-virt 2>/dev/null)"

echo "### B links"
ip -br link | grep -vE "^(lo|$n)"
echo "container-ifs=$(ip -br link | grep -cE "^($n)")"
for t in bond vlan wireguard; do
  printf '%s: ' "$t"
  ip -o link show type "$t" 2>/dev/null \
    | cut -d: -f2 | tr -d ' ' | tr '\n' ' '
  echo
done
ip -o addr show dev "$up"
ip -o addr show | grep -E ': (wg|tailscale|zt|tun)[^ ]* '
ip -4 route show default; ip -6 route show default
ip -4 rule; ip -6 rule

echo "### C sysctl"
echo "ip_forward=$(cat /proc/sys/net/ipv4/ip_forward)"
for i in all "$up"; do
  for k in disable_ipv6 accept_ra forwarding; do
    echo "$i/$k=$(cat "/proc/sys/net/ipv6/conf/$i/$k" \
      2>/dev/null)"
  done
done

echo "### D dns"
ls -l /etc/resolv.conf
grep -m3 '^#' /etc/resolv.conf
grep -E '^(nameserver|search|domain|options)' \
  /etc/resolv.conf
[ -L /etc/resolv.conf ] || lsattr /etc/resolv.conf \
  2>/dev/null
if command -v resolvectl >/dev/null 2>&1; then
  resolvectl dns 2>/dev/null \
    | grep -E "^(Global|Link [0-9]+ \($up\))"
  resolvectl domain 2>/dev/null \
    | grep -E "^(Global|Link [0-9]+ \($up\))"
  resolvectl status --no-pager 2>/dev/null \
    | grep -E 'resolv.conf mode|Protocols' | sort -u
fi
grep '^hosts:' /etc/nsswitch.conf
ss -lnu 'sport = :53' | tail -n +2
ss -lnt 'sport = :53' | tail -n +2
hostname -f
getent hosts "$(hostname -f)"
echo "dns64=$(getent ahostsv6 ipv4only.arpa \
  | grep -v '^::ffff:' | head -1)"

echo "### E egress"
echo "proxy-env=$(env | grep -ciE '^(https?|all)_proxy=')"
echo "proxy-apt=$(apt-config dump 2>/dev/null \
  | grep -ciE '^Acquire::https?::Proxy ')"
echo "proxy-dnf=$(grep -hciE '^proxy[[:space:]]*=' \
  /etc/dnf/dnf.conf /etc/yum.conf 2>/dev/null \
  | grep -c '^[1-9]')"
echo "proxy-suse=$(grep -c '^PROXY_ENABLED=\"yes\"' \
  /etc/sysconfig/proxy 2>/dev/null)"
[ -n "$T" ] || T=$(grep -rhoE 'https?://[^/ "]+' \
  /etc/apt/sources.list /etc/apt/sources.list.d/ \
  /etc/yum.repos.d/ /etc/zypp/repos.d/ 2>/dev/null \
  | sort -u | head -3)
[ -n "$T" ] || echo "egress=no-target"
for t in $T; do
  h=${t#*://}; ok=0
  v4=$(getent ahostsv4 "$h" | head -1)
  v6=$(getent ahostsv6 "$h" | grep -v '^::ffff:' | head -1)
  echo "resolve $h: v4=${v4%% *} v6=${v6%% *}"
  for f in 4 6; do
    if [ "$f" = 4 ] && [ -z "$v4" ]; then
      c=no-a
    elif [ "$f" = 6 ] && [ -z "$v6" ]; then
      c=no-aaaa
    elif command -v curl >/dev/null 2>&1; then
      c=$(curl -"$f" -sS -o /dev/null --connect-timeout 3 \
        -m 5 -w '%{http_code}' "$t/" 2>/dev/null)
    elif command -v wget >/dev/null 2>&1; then
      wget -"$f" -q -t 1 -T 5 --spider "$t/" 2>/dev/null
      c="wget-exit=$?"
    else
      c=no-client
    fi
    case $c in
      000|wget-exit=4|no-a|no-aaaa|no-client) ;;
      *) ok=1 ;;
    esac
    echo "egress$f $t=$c"
  done
  [ "$ok" = 1 ] && break
done
```

Reading **A (manager)**:

- `networkctl status` names the `.network` file in
  use. A path under `/run/systemd/network/` with
  `netplan` in its name means netplan generated it:
  the source of truth is the YAML.
- `networking=active` alone is not ifupdown in
  charge: Debian runs the unit even when
  `/etc/network/interfaces` configures only `lo`.
  The `iface` lines decide.
- `network=active` is the legacy initscripts service
  (RHEL 8 and older); `wicked` is SUSE's manager.
- **cloud-init** owns the network when it is
  installed, enabled, and nothing disables its
  network config. It renders the configuration on
  the first boot of every new instance and, for some
  datasources, on every boot; hand edits to its
  output can vanish. `cloud-init=disabled` or a
  masked unit means it was switched off
  (`rules/cloud-image.md` → cloud-init Hanging).
- **Conflict:** two managers that both show the same
  interface as managed (networkctl `configured` and
  nmcli `connected`, or an ifupdown `iface` stanza
  plus either).

Reading **B (links, addresses, routes)**:

- The uplink is the device of the default route.
  `wg*`, `tailscale0`, `zt*` and `tun*` are overlays.
- **Dynamic addresses** carry `dynamic` and a finite
  `valid_lft`: in practice DHCP for IPv4, SLAAC or
  DHCPv6 for IPv6. `proto kernel_ra` marks an
  address the kernel built from a Router
  Advertisement; a /128 with `dynamic` is usually
  DHCPv6. Confirm with the manager's view (A).
- `temporary` marks an RFC 4941 privacy address,
  `mngtmpaddr` the address it is derived from,
  `deprecated` one that is no longer preferred.
- **Interface ID from the MAC (EUI-64):** the last 64
  bits contain `ff:fe` in the middle and match the
  link's MAC with the seventh bit flipped.
- `ip rule` beyond the defaults (local, main and
  default for IPv4; local and main for IPv6) is
  policy routing. `wg-quick` and Tailscale add their
  own rules; name the owner.
- A default route with `proto ra` and `expires`
  lives only as long as Router Advertisements keep
  arriving.

Reading **C (kernel)**:

- `disable_ipv6=1` on `all` or the uplink: IPv6 is
  off.
- `accept_ra`: `0` the kernel ignores RAs, `1` it
  accepts them unless forwarding is on, `2` it
  accepts them even with forwarding. The uplink's
  own value counts; `all/accept_ra` does not
  override it. ifupdown defaults to `2` for
  `inet6 auto` but to `1` for `inet6 dhcp`
  (interfaces(5)).
- **Who handles RAs.** systemd-networkd always sets
  the kernel's `accept_ra` to 0 and processes RAs
  itself. `accept_ra=0` with a `proto ra` default
  route therefore means a userspace manager does the
  work; only `accept_ra` 1 or 2 puts the kernel in
  charge.
- Whether forwarding itself is acceptable is the
  security audit's call
  (`heinzel-security` → `references/kernel-os.md`).

Reading **D (DNS)** — `/etc/resolv.conf` tells you
who writes it:

- Symlink to `stub-resolv.conf`: systemd-resolved,
  applications ask the stub on 127.0.0.53.
- Symlink to `/run/systemd/resolve/resolv.conf`:
  resolved writes the upstream servers directly.
- Symlink to `/run/NetworkManager/…`, or header
  `Generated by NetworkManager`: NetworkManager.
- Symlink to `/run/resolvconf/…` or a resolvconf
  header: resolvconf or openresolv.
- Symlink to `/run/netconfig/…`: SUSE netconfig.
- A plain file without a generator header: static,
  by hand or by cloud-init. An `i` in `lsattr` means
  someone made it immutable to stop a manager.

Also:

- Servers on the uplink that the manager's config
  does not set came from DHCP or from RDNSS in a
  Router Advertisement. Write "link-provided" unless
  the config shows the source.
- A listener on port 53 is a local resolver. Name it
  with the DNS resolver class of
  `rules/service-class-check.md`.
- `ipv4only.arpa` has only A records (RFC 7050), so
  an IPv6 answer for it comes from a DNS64 resolver
  and carries the NAT64 prefix. glibc's `getent
  ahostsv6` also lists IPv4-mapped addresses
  (`::ffff:…`) for names without AAAA; they are not
  DNS answers, hence the `grep -v`.
- `127.0.1.1` for the own name comes from
  `/etc/hosts`: Debian's default, not a finding. It
  matters only for a service that must announce its
  public name (an MTA, for instance).

## Probe — FreeBSD

```bash
sysrc -a | grep -E \
  -e '^(ifconfig_|ipv6_|defaultrouter|rtsold|gateway_enable)' \
  -e '^(resolv|local_unbound|dhclient|cloudinit|nuageinit)'
ifconfig -a | grep -E '^[a-z]|inet6? |nd6 options|status:'
netstat -rn -f inet | grep '^default'
netstat -rn -f inet6 | grep '^default'
sysctl net.inet.ip.forwarding net.inet6.ip6.forwarding \
  net.inet6.ip6.accept_rtadv
grep -E '^(nameserver|search|domain|options)' \
  /etc/resolv.conf
```

- `rc.conf` is the source of truth.
  `ifconfig_<if>="DHCP"` (or `SYNCDHCP`) is DHCP;
  `ifconfig_<if>_ipv6="inet6 accept_rtadv"` together
  with `rtsold_enable="YES"` is SLAAC.
- `nd6 options` on each interface: `ACCEPT_RTADV`
  accepts RAs, `IFDISABLED` means IPv6 is off.
- With `ip6.forwarding=1` FreeBSD ignores RAs by
  default. Check `sysctl -d net.inet6.ip6.rfc6204w3`
  on the host before relying on that knob.

## Probe — macOS

```bash
networksetup -listnetworkserviceorder
scutil --nwi
ifconfig | grep -E '^[a-z]|inet6? '
route -n get default 2>/dev/null \
  | grep -E 'gateway|interface'
route -n get -inet6 default 2>/dev/null \
  | grep -E 'gateway|interface'
scutil --dns | grep -E '^resolver|nameserver|search domain|if_index' \
  | head -40
sysctl net.inet.ip.forwarding net.inet6.ip6.forwarding
```

Then `networksetup -getinfo "<service>"` for the
primary service (first in `scutil --nwi`): DHCP or
manual for IPv4, Automatic, Manual or Off for IPv6.

- `ifconfig` flags on IPv6 addresses: `autoconf`
  (SLAAC), `temporary` (privacy address), `secured`
  (stable, not from the MAC).
- `scutil --dns` shows the resolver order, including
  per-domain resolvers set by VPN clients.

## Egress test

One request per address family to a host the machine
already talks to, so the test adds no new third
party: on Linux the first answering repository host
(section E of the probe), on FreeBSD the `pkg`
repository (`pkg -vv | grep url`), on macOS Apple's
update host `swscan.apple.com`. On FreeBSD use
`fetch -4` / `fetch -6` with `-q -T 5 -o /dev/null`;
on macOS `curl` as in the Linux probe.

Hosts behind an internal mirror or a strict egress
filter override the target through the rule-override
chain (CLAUDE.md → Rule Overrides): a
`## Replace: Egress test target` section in
`memory/custom-rules/network.md` (fleet-wide) or in
`memory/servers/<hostname>/rules.md`. On Linux, set
`T` to that URL before the probe.

Reading the result:

- **Any HTTP status** (even 403 or 404), or wget
  exit 0 or 8: the family reaches the internet.
  curl `000`, wget exit 4, or a fetch error: it
  does not.
- `no-aaaa` / `no-a`: the target has no record of
  that family, so the result is `inconclusive`, not
  `broken`. The probe
  moves on to the next repository host; if none has
  AAAA, ask the user for a target.
- **Both families fail** on every target: check the
  repositories before calling egress dead.
- `egress=no-target`: no repository host found (a
  distro without apt, dnf or zypper). Set `T` through
  the override and run again.
- `resolve` empty in both families on every target:
  name resolution fails (see Findings).
- **A proxy is configured** (any `proxy-*` count
  above 0): direct
  egress may be blocked on purpose. Record
  `Egress: via proxy` and do not report a failed
  direct test as a finding.
- ULA-only IPv6 without NAT66 has no global v6
  egress by design. Record it; it is not broken.

Finding out the public address behind NAT needs an
external echo service. Do that only when the user
asks.

## Public DNS view

Run on the **workstation**, not on the server: it
shows what clients see. Use the address-only filters
from `rules/dns-aliases.md` (a bare `dig +short` can
return a CNAME target):

```bash
dig +short A <hostname> | grep -E '^[0-9.]+$'
dig +short AAAA <hostname> | grep ':'
dig +short -x <each public address>
```

Resolve each PTR name the same way to confirm it
points back. The check of the A record against
`- IP:` stays with `rules/dns-aliases.md` → IP
Verification; here compare A and AAAA with the
addresses on the uplink:

- An A or AAAA pointing at an address the host does
  not have breaks inbound connections for clients
  of that family. Exception: a private IPv4 on the
  host with a public A record is 1:1 NAT. Record
  `NAT` rather than a mismatch.
- A PTR that does not resolve back to the same
  address (no forward confirmation) hurts mail
  delivery. A generic PTR from the provider's pool
  (e.g. `dynamic-…pool.<isp>`) is not the host's own
  name; for a mail host it counts as missing.
- A GUA without an AAAA record is normal for a host
  that only connects outwards.

## Classification

**IPv4:**

- `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`:
  private (RFC 1918).
- `100.64.0.0/10`: shared address space, CGNAT
  (RFC 6598). Tailscale uses it on `tailscale0` too:
  there it is an overlay, not the uplink.
- `169.254.0.0/16`: link-local. As the only IPv4
  address it means DHCP failed.
- `192.0.0.0/29` on a CLAT interface: 464XLAT.
- `192.0.2.0/24`, `198.51.100.0/24`,
  `203.0.113.0/24`: documentation ranges, never on
  a real host.
- Anything else outside loopback and multicast:
  public.

**IPv6:**

- `2000::/3`: global unicast (GUA). Exceptions below.
- `fd00::/8`: unique local (ULA). `fc00::/8` is
  undefined; treat it as a misconfiguration.
- `fe80::/10`: link-local. Only this means IPv6 has
  no usable address.
- `fec0::/10`: site-local, deprecated since 2004.
- `2002::/16` (6to4) and `2001::/32` (Teredo):
  legacy tunnels.
- `2001:db8::/32`: documentation, never on a real
  host.
- `64:ff9b::/96`: NAT64 well-known prefix, seen in
  DNS64 answers and routes, not as a host address.

**Stack** (from the uplink's addresses, default
routes and the egress test; container bridges do
not count — Docker with IPv6 puts a ULA on its
bridge on any host):

- `dual-stack`: usable IPv4 and IPv6 GUA, both with
  a default route.
- `v4-only`: IPv6 off, or link-local only.
- `v6-only`: no IPv4 default route. Add `+ NAT64`
  when DNS64 answers, `+ 464XLAT` with a CLAT
  address.
- `v4 + ULA`: IPv6 only inside the site.
- Append `v6 broken` when a GUA and a default route
  exist but the v6 egress test fails, and `no v6
  route` when a GUA exists without a default route.

## Findings

The one list for onboarding (the `## Findings`
section in `network.md`), housekeeping and the fleet
audit; consumers refer to it instead of restating
it. Severities follow the housekeeping report
format.

**CRITICAL**

- Name resolution fails (`getent` on the egress
  target returns nothing in any family).
- A GUA exists and the firewall filters IPv4 but not
  IPv6. See `heinzel-security` →
  `references/firewall-ipv6.md`.

**WARN**

- `v6 broken` or `no v6 route` (see Stack). Clients
  prefer IPv6 and hang or fall back slowly; `apt`
  and `curl` stall.
- **The RA/forwarding trap:** the kernel handles RAs
  with `accept_ra=1` on the uplink, forwarding is on
  there (`forwarding=1`, typically set later by
  Docker, libvirt or a VPN role), and the IPv6
  default route comes from RAs. The kernel stops accepting RAs, and
  the route dies when its `expires` counter hits
  zero, or already has. Fix: `accept_ra=2` on the
  uplink, or a static IPv6 default route.
- Two managers claim the same interface (see
  Reading A).
- `/etc/resolv.conf` is a static file while
  systemd-resolved or NetworkManager is active: the
  manager's DNS settings are silently ignored.
- Only nameservers of a family the host cannot
  reach (e.g. IPv6 resolvers on a host with broken
  IPv6).
- A or AAAA record points at an address the host
  does not have (outside the NAT exception).
- IPv6 disabled via sysctl while an AAAA record is
  published or the manager configures IPv6.
- Several default routes in one family with equal
  metric.
- An address Classification marks as deprecated,
  undefined, legacy or documentation, or
  `169.254.0.0/16` as the only IPv4 address.
- The uplink is down (`operstate` not `up`) on a
  configured interface.
- No PTR, or a PTR without forward confirmation, on
  a public address of a host that sends mail
  (`memory.md` lists an MTA).

**INFO**

- cloud-init owns the network configuration (see
  Reading A): edits belong in
  `/etc/cloud/cloud.cfg.d/`, or cloud-init must be
  switched off first (`rules/cloud-image.md`).
- Temporary (privacy) IPv6 addresses on a server:
  the outgoing source address rotates and breaks
  allow-lists on the far side.
- Interface ID derived from the MAC (EUI-64): the
  address changes when the NIC does and exposes the
  MAC.
- A server whose address depends on a DHCP lease.
- `/etc/resolv.conf` marked immutable.
- Only one upstream nameserver.
- No PTR on a public address (without an MTA).
- `hostname -f` does not return an FQDN, or does not
  resolve.

## Before changing the network

Network and firewall changes can cut off SSH
(CLAUDE.md → Firewall & network): discuss first.
Then:

- **Edit the owner's source, not its output.** The
  netplan YAML, not the generated `.network` file;
  the NetworkManager connection (`nmcli connection
  modify`), not `/etc/resolv.conf`; the cloud-init
  config when cloud-init owns the network.
- **Test with a safety net.** `netplan try` rolls
  back unless confirmed. For other managers,
  schedule a job that restores the backup before
  applying, and cancel it once a fresh SSH login
  still works — the same pattern as the pf rollback
  in `rules/freebsd.md`.
- Back up every file first (`rules/backups.md`) and
  re-run the profile afterwards.
