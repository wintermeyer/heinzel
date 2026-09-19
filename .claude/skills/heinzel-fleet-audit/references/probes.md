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
- Whether the SSH port is open (must be yes)

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
