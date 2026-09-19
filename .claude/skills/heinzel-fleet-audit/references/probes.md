# Fleet Audit Probes

The probe commands run on each audited host. All are
read-only. Group them into a single SSH invocation per host
to minimise round-trips:

```bash
ssh <standard options from CLAUDE.md → SSH Options> USER@HOST '
echo "###ua###"; <ua probe>
echo "###sshd###"; <sshd probe>
echo "###fw###"; <firewall probe>
echo "###mta###"; <mta probe>
echo "###time###"; <time probe>
echo "###reboot###"; <reboot probe>
echo "###acct###"; <accounts probe>
'
```

Then split the output on `###<key>###` markers to fill the
comparison table.

**Privilege handling.** The sshd and firewall probes need
root. When the SSH user is not root, try `sudo -n` (never an
interactive sudo — BatchMode means no prompts). When neither
root nor passwordless sudo is available, the probe must emit
the sentinel `unknown(needs-root)` instead of a degraded
answer — an active ufw must never be reported as `none` just
because the probe lacked permission to read its state. See
`references/output-format.md` for how the sentinel is
rendered and why it is excluded from drift detection.

## 1. Unattended-upgrades (Debian/Ubuntu)

```bash
apt-config dump 2>/dev/null | grep \
  -e '^APT::Periodic::Update-Package-Lists ' \
  -e '^APT::Periodic::Unattended-Upgrade ' \
  -e '^Unattended-Upgrade::Origins-Pattern::' \
  -e '^Unattended-Upgrade::Mail ' \
  -e '^Unattended-Upgrade::MailReport ' \
  -e '^Unattended-Upgrade::Automatic-Reboot ' \
  -e '^Unattended-Upgrade::Automatic-Reboot-WithUsers ' \
  -e '^Unattended-Upgrade::Automatic-Reboot-Time ' \
  -e '^Unattended-Upgrade::Remove-Unused-Kernel-Packages ' \
  -e '^Unattended-Upgrade::Remove-Unused-Dependencies '
```

Row keys to extract for the table:

- `APT::Periodic::Update-Package-Lists`
- `APT::Periodic::Unattended-Upgrade`
- `Origins-Pattern` count (number of `::` entries)
- `Origins-Pattern` contains `${distro_codename}-security`
  pattern (yes/no)
- `Mail`
- `MailReport` (or legacy `MailOnlyOnError`)
- `Automatic-Reboot`
- `Automatic-Reboot-WithUsers`
- `Automatic-Reboot-Time` (present/absent — absent is the
  preferred fleet policy)
- `Remove-Unused-Kernel-Packages`

## 2. sshd effective config

`sshd -T` needs root (it reads host keys). Probe with the
privilege ladder — direct as root, `sudo -n` otherwise, and
the sentinel when neither works:

```bash
if [ "$(id -u)" = "0" ]; then
  SSHD="sshd"
elif sudo -n true 2>/dev/null; then
  SSHD="sudo -n sshd"
else
  SSHD=""
fi
if [ -z "$SSHD" ]; then
  echo "unknown(needs-root)"
else
  $SSHD -T 2>/dev/null | grep \
    -e '^permitrootlogin ' \
    -e '^passwordauthentication ' \
    -e '^pubkeyauthentication ' \
    -e '^kbdinteractiveauthentication ' \
    -e '^challengeresponseauthentication ' \
    -e '^x11forwarding ' \
    -e '^allowtcpforwarding ' \
    -e '^maxauthtries ' \
    -e '^logingracetime ' \
    -e '^usepam ' \
    -e '^port '
fi
```

Row keys: each line is `key value`. Compare column-by-
column. A host whose sshd column is `unknown(needs-root)`
is reported as such, never as "defaults".

Highlight as drift:

- Any host with `passwordauthentication yes` while others
  have `no`.
- Any host with `permitrootlogin yes` while others use
  `prohibit-password` or `forced-commands-only`.
- Mismatched `port` values across the fleet.

## 3. Firewall posture

Reading firewall state needs root (`ufw status` and
`firewall-cmd` both refuse for normal users). Detect the
*tool* via `command -v` (no root needed), but only report
its *state* when root or `sudo -n` is available — otherwise
emit the sentinel. Never let a permission error degrade to
`tool=none`: that fabricates "no firewall" on a host whose
firewall is simply unreadable.

```bash
if [ "$(id -u)" = "0" ]; then
  SUDO=""
elif sudo -n true 2>/dev/null; then
  SUDO="sudo -n"
else
  SUDO="-"
fi
# Prefer ufw on Debian/Ubuntu; firewall-cmd on RHEL family.
if command -v ufw >/dev/null 2>&1; then
  echo "tool=ufw"
  if [ "$SUDO" = "-" ]; then
    echo "state=unknown(needs-root)"
  else
    $SUDO ufw status verbose 2>&1
  fi
elif command -v firewall-cmd >/dev/null 2>&1; then
  echo "tool=firewalld"
  if [ "$SUDO" = "-" ]; then
    echo "state=unknown(needs-root)"
  else
    $SUDO firewall-cmd --list-all 2>&1
  fi
else
  echo "tool=none"
fi
```

(`$SUDO` is intentionally unquoted so an empty value
disappears; `-` marks "no privilege path".)

Row keys for the table:

- Tool in use (`ufw` / `firewalld` / `none`)
- State — `unknown(needs-root)` when the tool exists but
  its status is unreadable without root
- Default policy (deny incoming required)
- Number of open ports / services
- Whether 22/tcp is open (must be yes)

Highlight as drift:

- Different firewall tool across the fleet.
- Different default policy.
- Different exposure of admin ports (5432, 27017, 3306,
  9100 to 0.0.0.0).

## 4. MTA

```bash
# Detect installed MTA package + active unit.
for pkg in postfix sendmail msmtp-mta nullmailer dma \
           opensmtpd exim4; do
  dpkg -l "$pkg" 2>/dev/null \
    | awk -v p=$pkg "/^ii  /{print \"pkg=\" p; exit}"
done
ls -l /usr/sbin/sendmail 2>/dev/null | awk "{print \"sendmail=\" \$NF}"
for unit in postfix opensmtpd exim4; do
  state=$(systemctl is-active "$unit" 2>/dev/null)
  [ "$state" = "active" ] && echo "active=$unit"
done
hostname -f
```

Row keys:

- Installed MTA package
- Sendmail symlink target
- Active SMTP unit
- FQDN (sanity)

Highlight as drift:

- One host with no MTA while others have one.
- Different MTAs in use without a documented reason in
  the per-host `memory.md`.

## 5. Time sync

```bash
timedatectl show \
  --property=NTPSynchronized \
  --property=NTP \
  --property=TimeUSec \
  --property=Timezone 2>/dev/null
systemctl is-active systemd-timesyncd chronyd ntp \
  ntpd openntpd 2>&1 | head -5
```

Row keys:

- `NTPSynchronized` (yes required)
- Active timesync unit name
- Timezone (typically all `Europe/Berlin`)

Highlight as drift:

- `NTPSynchronized=no` on any host.
- Different timesync daemons across the fleet.
- Different timezones.

## 6. Auto-reboot behaviour (cross-check with UA)

```bash
test -f /var/run/reboot-required && echo "pending=yes" \
  || echo "pending=no"
uptime -s
```

Row keys:

- `/var/run/reboot-required` present? (kernel waiting for
  reboot)
- Boot time / uptime

Highlight as drift / warning:

- Any host with `pending=yes` but uptime > 7d — auto-reboot
  has not fired despite a pending kernel.
- Hosts with uptime > 90d — even without a pending reboot,
  worth a heads-up.

## Accounts and sudo model

The probes of `rules/accounts.md` sections 1–3 in compact
form; keep the two in step. The account source needs no
root; the sudo rules and the SSSD access rule do. The
section runs its own root / `sudo -n` check at its top.

```bash
if [ "$(id -u)" = "0" ]; then
  SUDO=""
elif sudo -n true 2>/dev/null; then
  SUDO="sudo -n"
else
  SUDO="-"
fi
for f in /etc/nsswitch.conf /usr/etc/nsswitch.conf; do
  [ -e "$f" ] || continue
  grep -E '^(passwd|sudoers):' "$f"
  break
done
if command -v systemctl >/dev/null 2>&1; then
  for d in sssd nslcd winbind oddjobd; do
    echo "$d=$(systemctl is-active "$d" 2>/dev/null)"
  done
else
  service -e 2>/dev/null | grep -E 'sssd|nslcd' \
    | sed 's/^/enabled=/'
fi
if command -v realm >/dev/null 2>&1; then
  realm list 2>/dev/null | grep -E \
    '^[^ ]|server-software:|login-policy:|permitted-groups:'
fi
command -v authselect >/dev/null 2>&1 && authselect current
# Local accounts (rules/accounts.md → 5), name:uid.
min=$(awk '$1 == "UID_MIN" {print $2}' /etc/login.defs 2>/dev/null)
echo "local: $(awk -F: -v min="${min:-1000}" \
  '$3 >= min && $3 < 65534 {printf "%s:%s ", $1, $3}' /etc/passwd)"
echo "mkhomedir=$(grep -RlE 'pam_(oddjob_)?mkhomedir' \
  /etc/pam.d/ /usr/lib/pam.d/ 2>/dev/null | tr '\n' ' ')"
if [ "$SUDO" = "-" ]; then
  echo "sudoers=unknown(needs-root)"
elif command -v visudo >/dev/null 2>&1; then
  F=$($SUDO visudo -c 2>&1 | sed -n 's|^\(/[^:]*\): .*|\1|p')
  echo "sudoers-files: $(echo $F)"
  [ -n "$F" ] && $SUDO grep -HvE '^[[:space:]]*(#|$)' $F
  # Members of each group a rule names: list, then primary.
  # Names may be quoted or have escaped spaces (AD groups).
  [ -n "$F" ] && $SUDO sed -nE \
    's/^[[:space:]]*%("[^"]*"|([^[:space:],\\]|\\.)+).*/\1/p' $F \
    | sed -e 's/\\\(.\)/\1/g' -e 's/"//g' | sort -u \
    | while IFS= read -r g; do
    getent group "$g" | { IFS=: read -r n x gid m
      echo "group $g: $m primary: $(awk -F: -v g="$gid" \
        '$4 == g {printf "%s,", $1}' /etc/passwd)"; }
  done
else
  echo "sudoers=none"
fi
[ "$SUDO" = "-" ] || $SUDO grep -rhE \
  '^[[:space:]]*(access_provider|simple_allow|ldap_access)' \
  /etc/sssd 2>/dev/null
```

(`$F` is unquoted on purpose: one word per file.)

Row keys:

- Account source: `files`, or the directory (`sss`, `ldap`,
  `winbind`) with its daemon state and realm.
- `login-policy` and `permitted-groups`.
- SSSD access rule: `access_provider` and its groups or
  filter (none: every directory user may log in).
- `sudoers:` line (absent means files only).
- mkhomedir: on / off.
- Rules with `ALL` as the command, per user or `%group`,
  with `NOPASSWD` marked.
- Rules with `NOPASSWD` on selected commands.
- Members of each `%group` in a rule.
- Local accounts (`name:uid`); which have keys is per
  host (`heinzel-security`), not in this call.
- `Defaults` that change who needs a password
  (`!authenticate`, `targetpw`, `rootpw`).
- Model from the `Accounts:` line in each host's
  `memory.md` (`(unset)` when missing).

Highlight as drift:

- Different account sources or models on hosts that should
  admit the same admins.
- A directory host whose daemon is not active, or that
  admits all directory users (realm or SSSD access rule)
  while the others restrict them.
- `NOPASSWD: ALL` on some hosts but not others, or granted
  to different groups.
- A local sudo rule for a named user on one directory host:
  a hand-made exception the directory does not control.
- mkhomedir on some directory hosts but not others.
- A local account on some hosts only, or one name with
  different UIDs on different hosts (files on shared
  storage then belong to someone else). With a team
  roster in `memory/network.md`
  (`rules/accounts.md` → Team accounts), compare each host with it:
  missing, extra, other UID.
- A different `sudoers.d` file on hosts with the same
  `Accounts:` model.
- A probe that contradicts the `Accounts:` line: memory is
  stale (report it, do not update memory).
