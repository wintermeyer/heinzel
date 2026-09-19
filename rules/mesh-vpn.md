# Mesh VPNs and Tunnels

Servers spread over sites, clouds and home offices are
often connected by a mesh VPN rather than a company
network: admins reach them through it, and they reach
each other. Per host heinzel records which VPN or
tunnel it is in, with which address and role, whether
it is connected, and whether the agent brings its own
SSH server or exposes sshd. How heinzel itself reaches
the host: `rules/access-path.md`.

Common in self-hosting, homelabs and small companies:

| Agent | Policy lives | SSH |
|---|---|---|
| Tailscale (+ Headscale) | control server | own server |
| NetBird | management server | own server |
| WireGuard (wg-quick, wg-easy, Netmaker) | the host | — |
| ZeroTier | network controller | — |
| Nebula (+ Defined Networking) | the host | admin console |
| Pangolin (Newt) | Pangolin server | own server |
| Cloudflare Tunnel | Cloudflare / config | exposes sshd |

OpenVPN and IPsec are usually site-to-site or
hub-and-spoke; record them like WireGuard.

## When to check

- **First connection:** the probe below, in the OS
  detection call (`rules/first-connection.md`).
- Before work on SSH access or accounts, before
  firewall changes on port 22 or a VPN interface, and
  before touching an agent.
- When heinzel's own login behaves unlike sshd (see
  "heinzel's own login").

## Probe (no root)

```bash
PS=$(ps ax -o comm=)
printf '%s\n' "$PS" \
  | grep -E -e '(^|/)(tailscaled|headscale|netbird)$' \
    -e '(^|/)(zerotier-one|nebula|dnclient|newt|cloudflared)$' \
    -e '(^|/)(wireguard-go|netclient|openvpn|charon(-systemd)?)$' \
  | sort -u
case $PS in *cloudflared*)
  ps ax -o comm=,args= | grep -c -- '^[^ ]*cloudflared .*--token' ;;
esac
if command -v ip >/dev/null 2>&1; then
  ip -br link show type wireguard
  ip -br addr | grep -E '^(tailscale|zt|nebula|tun)'
else
  ifconfig -g wg 2>/dev/null
  ifconfig -l
fi
ls -d /Applications/Tailscale.app \
  /Applications/WireGuard.app 2>/dev/null
if command -v tailscale >/dev/null 2>&1; then
  echo "== tailscale"
  tailscale version 2>&1 | head -n 1
  tailscale ip 2>&1
  tailscale status --json --peers=false 2>&1 \
    | grep -e '"BackendState"' -e '"Online"' \
      -e '"KeyExpiry"' -e '"Expired"'
  P=$(tailscale debug prefs 2>&1)
  printf '%s\n' "$P" | grep -e '"RunSSH"' \
    -e '"ControlURL"' -e '"OperatorUser"'
  printf '%s\n' "$P" | sed -n \
    '/"AdvertiseRoutes": null/p; /"AdvertiseRoutes": \[/,/]/p'
fi
if command -v netbird >/dev/null 2>&1; then
  echo "== netbird"
  netbird status 2>&1 | grep -e '^Daemon' \
    -e '^Management' -e '^Signal' -e '^NetBird IP' \
    -e '^Profile' -e '^SSH Server' -e '^Session expires' \
    -e '^Peers count' -e 'daemon'
fi
```

What finds what:

- **Processes:** Tailscale, a Headscale server,
  NetBird, ZeroTier, Nebula and `dnclient`, Newt,
  `cloudflared`, userspace WireGuard, Netmaker's
  `netclient`, OpenVPN, strongSwan (`charon`) — also
  inside containers. The `cloudflared` line counts
  whether its token is in `ps` arguments without
  printing them; it is anchored on the process name so
  that it does not count the probe itself.
- **Interfaces:** kernel WireGuard has no process;
  `ip -br link show type wireguard` lists it whatever
  its name (wg-quick, Netmaker's `netmaker`, NetBird's
  `wt0`), `ifconfig -g wg` on FreeBSD. On macOS names
  say little (`utun*`).
- **macOS apps:** the App Store and standalone
  Tailscale and the WireGuard app run under other
  process names; the `ls` finds them.

Not found by this probe:

- An agent in a container with its own network
  namespace (the wg-easy server, Tailscale or NetBird
  in Docker): the process shows, its interface and
  CLI do not. When that is the case, name the
  container, with root:

  ```bash
  for rt in docker podman; do
    command -v "$rt" >/dev/null 2>&1 || continue
    "$rt" ps --format '{{.Names}} {{.Image}}' 2>&1 \
      | grep -iE -e 'tailscale|headscale|netbird|wg-easy' \
        -e 'wireguard|zerotier|nebula|newt|cloudflared'
  done
  ```

  Record agent and container; its state stays
  unchecked. Rootless Podman containers show only for
  their own account.
- Services whose process names heinzel does not know
  (Firezone gateway, Twingate, others). A VPN the user
  names: record it anyway.

## Agents

Per agent: whether it is **connected** (installed and
running is not enough), when its login **expires**,
and where its keys are (`rules/secrets.md`: read only
the fields named here).

An expiry on a server is usually a forgotten setting
(servers should not expire): name it. Within 7 days,
tell the user; severities: `heinzel-housekeeping` →
Mesh VPNs.

What cuts a host off a VPN: stopping, restarting or
upgrading the agent, taking it down, a policy, ACL or
firewall change on the VPN, an expiry. Where heinzel
or other hosts depend on that path (subnet router,
WireGuard hub, lighthouse, control server):
`rules/access-path.md` → Only one way in.

### Tailscale and Headscale

- **Connected:** `BackendState` `Running` and
  `"Online": true` (in `Self`, reached the control
  server). `NeedsLogin`, `NeedsMachineAuth` (waits for
  approval), `Stopped` (`tailscale down`), or
  `"Expired": true`: not connected. Addresses:
  `tailscale ip`.
- **Expiry:** `KeyExpiry` (in `Self`); none on a server
  with key expiry disabled in the admin console.
- **Control server:** the same client works with
  Tailscale's hosted one or a self-hosted Headscale.
  `ControlURL` `https://controlplane.tailscale.com` or
  `https://login.tailscale.com` is Tailscale's, with
  the policy in its admin console. Anything else is
  self-hosted; check from the workstation (no SSH):

  ```bash
  curl -fsS <ControlURL>/health
  curl -fsS <ControlURL>/version
  ```

  `{"status":"pass"}` is Headscale; `/version` (0.26
  and newer) gives its version. No answer: ask the
  user what runs there.
- **Headscale:** the policy is on its server
  (`headscale policy get`, or the file named by
  `policy.path`); when that server is in
  `memory/servers/`, heinzel reads it there, with that
  host's own onboarding. SSH check mode and
  `localpart:` users need Headscale 0.29 or newer.
  While it is down, logged-in nodes keep their
  connections for a while, but new logins, key
  renewals and policy changes stop.
- **Routes:** an `AdvertiseRoutes` list makes the host
  a subnet router (`0.0.0.0/0` and `::/0`: exit node).
- **`OperatorUser`** may change the agent's settings
  without root, SSH included.

### NetBird

- **Connected:** `Management: Connected` and `Signal:
  Connected`; `Peers count: 3/5 Connected` shows how
  many peers are reachable. `Daemon status:
  NeedsLogin`, `LoginFailed` or `SessionExpired`: not
  connected. Address: `NetBird IP`.
- **Expiry:** `Session expires`, for peers logged in
  through SSO with login expiration on.
- **Management:** the server whose dashboard holds the
  policy.
- **Keys:** the JSON state files hold the WireGuard
  private key (see NetBird SSH for the grep).

### WireGuard

Plain `wg-quick`, systemd-networkd, NetworkManager,
and tools built on it (wg-easy, Netmaker, Firezone).
With root:

```bash
wg show
```

- `wg show` prints peers, endpoints, allowed IPs and
  the last handshake, and hides the keys. Other `wg`
  subcommands and output modes may print them: use
  only plain `wg show`.
- **Connected:** WireGuard has no such state;
  `latest handshake` says when traffic last flowed.
  Without `persistent keepalive`, an old handshake
  only means no recent traffic. No expiry.
- **Keys:** `/etc/wireguard/*.conf` (`PrivateKey`),
  systemd-networkd `*.netdev`, NetworkManager
  connections. Own address: `ip addr`.
- **Policy:** each peer's `AllowedIPs` and the host
  firewall; Netmaker and Firezone keep theirs on their
  server.
- **Hub:** a peer every host has, with a fixed
  endpoint.

### ZeroTier

With root (`zerotier-cli` needs the auth token):

```bash
zerotier-cli info
zerotier-cli listnetworks
```

- **Connected:** `info` says `ONLINE` (`TUNNELED`:
  online over the TCP relay, slow), and the network's
  status in `listnetworks` is `OK`. `ACCESS_DENIED`
  (not authorized on the controller), `NOT_FOUND`,
  `REQUESTING_CONFIGURATION`,
  `AUTHENTICATION_REQUIRED`: not connected.
- **Expiry:** only with single sign-on: `AUTH OK,
  expires in: …` or `AUTH EXPIRED`.
- **Controller:** the first 10 hex digits of the
  network ID are the controller's node address. Equal
  to this node's own address, or a `controller.d`
  directory in the ZeroTier home: this host is a
  self-hosted controller. Otherwise my.zerotier.com or
  another self-hosted one (ztncui, zero-ui): ask. Flow
  rules and member authorization live only there.
- **Keys:** `identity.secret` and `authtoken.secret`
  in `/var/lib/zerotier-one` (FreeBSD
  `/var/db/zerotier-one`, macOS
  `/Library/Application Support/ZeroTier/One`).

### Nebula

Config usually `/etc/nebula/config.yml` (the service
passes `-config`); Defined Networking's managed client
is `dnclient` with its state in `/var/lib/defined`.
With root (`nebula-cert` may be missing where only
`nebula` is installed; then ask for the dates):

```bash
nebula-cert print -path /etc/nebula/host.crt
sed -n '/^lighthouse:/,/^[a-z]/p; /^sshd:/,/^[a-z]/p' \
  /etc/nebula/config.yml
```

- **Connected:** no status command; the logs say
  whether handshakes succeed.
- **Expiry:** `notAfter` of the host certificate, and
  of `ca.crt`. Expired: the host drops out.
- **Certificate:** name, networks (own address),
  groups. **Lighthouses:** `am_lighthouse`, `hosts`.
- **Policy:** `firewall.inbound` and
  `firewall.outbound` in the config, by Nebula group.
- **Keys:** `pki.key` (`host.key`), `sshd.host_key`;
  print only the blocks above.
- **Admin console:** `sshd.enabled` (off by default)
  starts an SSH console on `sshd.listen` (never port
  22) for `authorized_users`. It controls Nebula
  itself, it is no login shell; when on, record who
  may use it.

### Pangolin (Newt)

Newt connects a site to a Pangolin server (reverse
proxy and VPN); it runs as a process or container,
without its own unit. Its WireGuard is in userspace
unless started `--native`.

- **Connected:** no status command; its log says.
- **Config:** `~/.config/newt-client/config.json` of
  the account that runs it, `CONFIG_FILE`, or
  `--config-file`. `newt --show-config` masks the
  secret; the file and a `--secret` argument do not.
- **SSH:** on unless `--disable-ssh` (`DISABLE_SSH`,
  `disableSsh`), see "SSH servers in agents". Its auth
  daemon **creates local accounts** (`useradd`) and
  sudo rules (`/etc/sudoers.d/90-pangolin-<user>`;
  sudo skips the file when the name has a dot, so
  `jane.doe` gets no sudo), and writes the CA it admits
  to `/etc/ssh/ca.pem`.
  Pangolin, not heinzel, manages those accounts. With
  `newt` running, a `trustedusercakeys /etc/ssh/ca.pem`
  in sshd makes Pangolin the user CA for sshd too; the
  path alone proves nothing.

### Cloudflare Tunnel

`cloudflared` connects outbound to Cloudflare and
publishes local services; no interface, no VPN
address.

- **Connected:** no status command; its log says.
- **Config:** `/etc/cloudflared`, `~/.cloudflared` or
  `/usr/local/etc/cloudflared`; a tunnel managed from
  the dashboard has its routes there, not on the host.
- **Ways in:** an ingress `service: ssh://…` publishes
  sshd; Cloudflare Access (browser SSH, short-lived
  certificates) decides who reaches it. The host
  firewall does not see it: the connection is
  outbound.

  ```bash
  grep -Hn 'ssh://' /etc/cloudflared/*.y*ml \
    /usr/local/etc/cloudflared/*.y*ml \
    ~/.cloudflared/*.y*ml 2>/dev/null
  ```

- **Keys:** `cert.pem`, the tunnel's `<UUID>.json`,
  and the token. A token count above 0 in the probe:
  the token is in `ps` for every account → move it
  into a token file (`rules/secrets.md` → Never Pass
  Secrets on the Command Line).

## SSH servers in agents

Tailscale, NetBird and Newt serve SSH themselves, on
port 22 of the VPN address. sshd does not see these
logins, so none of this applies to them:
`sshd_config` and its hardening, `authorized_keys`,
sshd's CA trust and principals, fail2ban, the sshd log,
`last`. Who may log in, and as which account, is
decided by a policy **outside the host**.

- **Firewall:** Tailscale SSH and Newt are served
  inside the agent and never pass the host firewall;
  closing 22 in ufw or firewalld does not stop them.
  NetBird puts its redirect (22 → 22022) into
  nftables/iptables itself. None shows up on port 22
  in `ss` or `lsof`; NetBird shows `:22022` on its own
  IP (kernel mode only).
- **Accounts:** Tailscale and NetBird map a person to
  a local account that must already exist; Newt
  creates them.
- **Access path:** a session that came in on an agent
  address (`rules/access-path.md`) went to the agent
  when the server port is `22022` (NetBird) or the
  address is Tailscale's with `RunSSH` on; otherwise
  to sshd.

### Tailscale SSH

`tailscale set --ssh`; on in the probe:
`"RunSSH": true` (since 1.100 also `tailscale get
ssh`). Linux, and macOS with the open-source
`tailscaled` only: the App Store and standalone apps
cannot serve SSH. Who: tailnet identity plus the `ssh`
rules (accept or check) of the policy file.

The rules that apply to this node arrive compiled
with its network map (root):

```bash
T=$(printf '\t')
tailscale debug netmap 2>&1 \
  | sed -n "/^$T\"SSHPolicy\": null/p; /^$T\"SSHPolicy\": {/,/^$T}/p"
```

The format is internal to Tailscale and may change;
read it, do not build on it. Each rule has:

- `principals`: `userLogin` (a person), `nodeIP` (a
  device, also tagged ones) or `any: true` (everyone
  on the tailnet).
- `sshUsers`: requested account → local account.
  `"root": "root"` admits root; `"*": "="` admits every
  account by its own name, root included unless the
  map also has `"root": ""` (how `autogroup:nonroot`
  arrives; an empty value never matches).
- `action`: `accept: true` is accept mode;
  `holdAndDelegate` (a URL) is check mode — the person
  confirms with the identity provider again first.
  `recorders` means sessions are recorded.

`SSHPolicy: null` with `RunSSH` on: no rule admits
anyone to this node. Group names and a check rule's
`checkPeriod` stay with the control server.

### NetBird SSH

`netbird up --allow-server-ssh` (0.61 or newer for the
current model); on in the probe: `SSH Server:
Enabled`. Who: OIDC login (JWT) plus the access policy
in the dashboard, which reaches the host only as
hashes. Flags, root:

```bash
grep -rHE --include='*.json' \
  '"(ServerSSHAllowed|EnableSSH[A-Za-z]*|DisableSSHAuth)"' \
  /var/lib/netbird /var/db/netbird /etc/netbird 2>/dev/null
```

The active profile is the file of the `Profile:` line
(`default.json` for `default`); `/var/db/netbird` is
FreeBSD, `/etc/netbird/config.json` older clients.

- `ServerSSHAllowed: true` without anyone turning it
  on: a config from before the setting existed is
  switched on at upgrade.
- `EnableSSHRoot: true`: admits `root`.
- `DisableSSHAuth: true`: no OIDC login; any peer the
  network policy lets through gets in, with no person
  behind the login.
- SFTP and port forwarding: allowed where `true`.
- **Client side:** the NetBird client writes
  `/etc/ssh/ssh_config.d/99-netbird.conf`, a `Match`
  block for peer names with `StrictHostKeyChecking no`
  and a `ProxyCommand netbird ssh proxy` that checks
  the peer's host key against NetBird's management
  instead. `stricthostkeychecking no` there is not the
  "any host key accepted" finding.

### Where the policy is

heinzel sees the compiled Tailscale rules (root) and
the NetBird and Newt switches on the host, never the
policy that admits people: the Tailscale admin
console, Headscale's policy, the NetBird dashboard,
the Pangolin server. Ask the user for it, or for read
access, when a finding depends on it. Never change it:
that is a change for every host at once, made by the
user.

### Who logged in

- **Tailscale** (Linux, root):

  ```bash
  journalctl -u tailscaled --since "7 days ago" \
    --no-pager -q | grep 'access granted to'
  ```

  Each line names the tailnet login and the local
  account (`ssh-user "root"`).
- **NetBird:** `netbird status -d` lists the open
  sessions (local account, JWT user, source). Past
  logins, root: `grep -e 'SSH auth' -e 'SSH connection
  from NetBird peer' /var/log/netbird/client.log` (the
  second is the only line without OIDC; a `--log-file`
  on the service's command line wins).
- **Newt:** its own output (container or process
  log); heinzel has no probe for it.

### heinzel's own login

When heinzel came in on an agent's SSH server, then:

- keys, certificates and `sshd_config` play no part;
  a `Permission denied` means the policy, not the key.
- **Tailscale check mode** prints a URL and waits
  until the user confirms in a browser. The shared
  connection (`CLAUDE.md` → SSH Options) is then
  reused for its lifetime.
- **NetBird with OIDC** needs a browser login through
  the NetBird client; `BatchMode` cannot do it.
- To reach sshd, use the host's other address.

### Changing it

Turning an agent's SSH server on or off opens or
closes a way in: ask first, and keep another way in
(`rules/access-path.md` → Only one way in).

- `tailscale set --ssh=false`, and a restart of
  `tailscaled`, end every Tailscale SSH session.
- NetBird: `netbird down`, then `netbird up
  --allow-server-ssh=false`; the VPN is down
  meanwhile.
- Newt: `--disable-ssh` and a restart; the tunnel is
  down meanwhile.

## Security audit

For `heinzel-security`: put the probes into the audit's
sshd calls. One report line per agent found; none when
there is none.

- An agent, or its SSH server, on while `network.md` →
  Mesh VPN has no entry for it or says off → **WARN**
  (a way in nobody recorded)
- Tailscale, per rule, root counting via `"root":
  "root"` or `"*": "="` without `"root": ""`: root by
  `accept` (no check) → **WARN**, for `any: true`
  principals → **CRITICAL**; other accounts for
  `any: true` → **WARN**
- NetBird: `EnableSSHRoot` and `DisableSSHAuth` both
  `true` → **CRITICAL** (root for any peer the network
  policy admits, no person behind it); either one alone
  → **WARN**
- Tailscale `OperatorUser` set → **INFO**, name the
  account (it can turn SSH on without root)
- SFTP or port forwarding allowed (NetBird flags,
  Tailscale `allowLocalPortForwarding`) → **INFO**
- Session recording (`recorders`) → OK, name it
- Policy not readable from the host (Tailscale without
  root, NetBird always) → **INFO** "policy not
  checked", and ask the user for it
- Newt SSH on → **INFO**, and list the accounts and
  `/etc/sudoers.d/90-pangolin-*` files it created
- Nebula `sshd.enabled` → **INFO**, name `listen` and
  the `authorized_users`
- Cloudflare Tunnel ingress `ssh://` → **INFO** (sshd
  reachable through Cloudflare; Access decides who); its
  token in `ps` arguments → **WARN**
- Agent found, no SSH server of its own → OK
- Expiry and connection state: `heinzel-housekeeping`
  → Mesh VPNs and WireGuard

Report line: `heinzel-security` →
`references/report-format.md`.

## Memory

Per server, the details go into a `## Mesh VPN`
section of `memory/servers/<hostname>/network.md`, the
host's network profile where there is one; otherwise
create the file with this section only. One line per
agent, also when its SSH server is off, so turning it
on later shows as a change:

```markdown
## Mesh VPN
- Tailscale 1.102.4, 100.101.102.103, connected,
  control Headscale 0.29.3 hs.example.com, no key
  expiry, routes 10.0.0.0/24; SSH on, root by check,
  others accept (netmap 2026-09-19)
- WireGuard wg0 10.8.0.5, hub vpn.example.com
- Tailscale in container ts-proxy
  (tailscale/tailscale); state unchecked
- Nebula nebula1 192.168.100.7, groups servers, cert
  to 2027-01-10; admin sshd off
- NetBird 0.79.0, 100.92.1.7, not connected
  (SessionExpired); SSH on, flags unchecked
```

Without root, mark what is missing `unchecked`.

`memory.md` gets one summary line, which the rules and
skills that read only `memory.md` key on:

```markdown
- Mesh VPN: Tailscale (SSH on), WireGuard — see
  network.md
```

Fleet-wide, in `memory/network.md`, one entry per
network: agent, control server (Tailscale, or
Headscale with host and version; ZeroTier controller;
Nebula lighthouses; WireGuard hub), where the policy
lives, subnet routers and what they route. Whether the
workstation is in it goes to `memory/user.md`
(personal).
