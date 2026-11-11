# Rollback Timer

Technique B of `rules/way-back.md`.

Some changes, when they go wrong, take away the
only way to fix them: heinzel's SSH connection. A
new IP address with a typo, a firewall rule in the
wrong order, a route that sends the replies
elsewhere. A backup does not help then, because
restoring it needs a login.

So before such a change heinzel arms a timer on the
host that restores the old state on its own. Only a
successful fresh login after the change disarms it.
If nobody disarms it (the login fails, the session
dies, heinzel crashes), the host rolls itself back.

## When it applies

Every change that can cut off a new SSH login to
the host:

- IP addresses, routes, interfaces, VLANs, bonds,
  bridges (netplan, `/etc/network/interfaces`,
  NetworkManager, systemd-networkd, `rc.conf`,
  `networksetup`);
- firewall rules and policies (ufw, firewalld,
  nftables, iptables, pf), including enabling or
  disabling the firewall;
- a VPN or tunnel the SSH path runs through
  (WireGuard, OpenVPN);
- network sysctls (`net.ipv4.*`, `net.ipv6.*`);
- PAM (`/etc/pam.d/`), which decides every login.

Not for changes that leave the way in open (a web
server, a database): there the config test and the
backup in `rules/backups.md` are the plan B.

In local mode the timer is optional: the operator
sits at the machine. Arm it anyway when the machine
is reached remotely by others or has no keyboard.

A one-shot rollback timer armed in a running
session is a safety net, not a run with nobody at
the keyboard (`CLAUDE.md` → What Heinzel does not
do). It is always allowed.

## The window

Default: **120 seconds** from applying the change.
A server can set its own in
`memory/servers/<hostname>/memory.md`:

    - Rollback window: 300

Never below 60: the fresh login alone takes up to
`ConnectTimeout`, and a turn of the agent often
takes longer. A window that is too short rolls back
a change that worked.

Tell the user the window before applying, in one
line: `Rollback in 120 s unless a new login works.`

## Recipe

`<ts>` is one timestamp for the whole change
(`date +%Y%m%d-%H%M%S`). Write paths literally; the
guard hook denies a redirect onto a computed target.

The commands that arm, disarm and read back the
timer differ per OS. They are in the **Rollback
Timer** section of the host's OS file
(`rules/linux.md` for every systemd Linux, else
`rules/freebsd.md`, `rules/netbsd.md`,
`rules/openbsd.md`, `rules/macos.md`). Read it
before step 1. A host without such a section uses
the generic variant in step 4.

1. **No other window open.** Check with the OS
   file's command, or
   `ls /var/run/heinzel-rollback-*.pid` for the
   generic variant (a file may be left over from a
   finished window: `kill -0 <pid>` says whether it
   still runs). A pending timer means another
   change is still in its window: wait for it or
   ask the user.

2. **Back up** every file the change touches, as in
   `rules/backups.md`. For a live firewall also save
   the running ruleset (`nft list ruleset`,
   `iptables-save`, `pfctl -sr`) into
   `/var/backups/heinzel/`.

3. **Write the rollback script** to
   `/var/backups/heinzel/rollback-<ts>.sh`,
   `chmod 700`. It restores the **previous state**,
   not "everything off": the old file and its
   activation, the old ruleset, the old address. It
   ends with one journal line:

       #!/bin/sh
       cp -p /var/backups/heinzel/50-cloud-init.yaml.<ts> \
         /etc/netplan/50-cloud-init.yaml
       netplan apply
       logger -t heinzel "rollback-<ts> ran: network config restored"

   Disabling the firewall is the rollback only when
   it was disabled before the change.

4. **Arm the timer.** It must not belong to the SSH
   session. Use the OS file's command. The generic
   variant, for every host whose OS file names none
   of its own:

       nohup sh -c 'echo $$ > /var/run/heinzel-rollback-<ts>.pid; \
         sleep 120; sh /var/backups/heinzel/rollback-<ts>.sh' \
         >/dev/null 2>&1 &

   No timer, no change: join steps 4 and 5 with
   `&&` in one command. The change then never runs
   without a timer, and no approval or turn of the
   agent eats into the window between them.

5. **Apply detached** where the change itself can
   drop the session, so a dying SSH connection does
   not kill the apply halfway:

       systemd-run --unit=heinzel-apply-<ts> --wait netplan apply

   Where a tool separates runtime from boot config,
   change the runtime only and persist after step 7:
   firewalld without `--permanent` (the rollback
   script is then `firewall-cmd --reload`), `ip`
   commands before the config file.

6. **Confirm with a fresh login**, using the
   fresh-login options from `CLAUDE.md`, to the
   address the host is reachable on now:

       ssh -o BatchMode=yes -o ConnectTimeout=5 \
         -o ControlMaster=no -o ControlPath=none \
         -o HostKeyAlias=<hostname> root@<new-address> true

   `HostKeyAlias` checks the key heinzel already
   knows; a new address is not in `known_hosts` and
   `BatchMode` refuses it otherwise. The old session
   proves nothing: the control socket and connection
   tracking (`ESTABLISHED`, pf's `keep state`) keep
   it alive after new logins are already blocked.

7. **Disarm only after that login worked**, and
   through it, with the OS file's command. Generic
   variant:

       kill "$(cat /var/run/heinzel-rollback-<ts>.pid)"

   Heinzel Pro sends every command naming
   `heinzel-rollback-` over a new login of its own,
   so there the disarm is its own confirmation. After
   an address change call its `follow_address` tool
   first; it moves the server once the new address
   shows the pinned host key.
   Check the timer is gone, then persist the runtime
   change (firewalld: repeat the command with
   `--permanent`) and update server memory with the
   new address.

## When the login fails

Do not race the timer and do not fix the change
through the old session. Wait the window plus 30
seconds, log in on the old address and read the
journal (OS file → Rollback Timer, "Did it run")
for the `rollback-<ts> ran` line. Report in one line what was rolled back, then
find the cause before trying again.

No line and no login: the host is unreachable after
the rollback. Follow `rules/ssh-unreachable.md` and
say plainly that the rollback did not bring it back.

## Tools that wait for a keystroke

`netplan try` and `iptables-apply` roll back on
their own, but confirm only from a keyboard on the
terminal they run in. heinzel runs without a
terminal (`BatchMode`) and confirms from a second
login, so they would always roll back. Use the
recipe above instead.

## What stays

A reboot inside the window boots the new config
from disk without the timer. Never reboot inside
it. For a file-based change (netplan, `rc.conf`)
say once that this residual risk exists.

The rollback scripts stay in `/var/backups/heinzel/`
and age out with the backups after 30 days. Record
the window, the outcome and the script path in the
local changelog under `Rollback:`
(`rules/changelog.md`).
