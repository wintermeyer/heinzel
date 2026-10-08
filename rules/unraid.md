# Unraid OS

Unraid is Slackware-based (`ID=unraid-os`,
`ID_LIKE=slackware` in `/etc/os-release`) and has no
package manager, no systemd, and a root filesystem in
RAM. The notes below are **observed behaviour** from
one server on Unraid 7.3.2 and 7.3.3 (September and
October 2026), not official documentation. Verify
before relying on them on another Unraid version or
plugin version.

## System Layout

- **Everything outside `/boot` and the array is in
  RAM** and rebuilt at every boot: `/etc`, `/usr`,
  `/root`, `/var`, `/tmp`. A change made there over
  SSH is gone after the next reboot.
- **`/boot`** is the USB flash drive (vfat, mounted
  with `fmask=0177`, `dmask=0077`): the only
  persistent place outside the array. Every file is
  0600, which is fine for SSH private keys. Settings
  live under `/boot/config/`, plugin data under
  `/boot/config/plugins/<plugin>/`.
- **Persistent startup commands** go into
  `/boot/config/go`. It runs once at boot.
- **Services** are SysV-style scripts in
  `/etc/rc.d/` (`rc.docker`, `rc.libvirt`, `rc.nginx`,
  …). Status: `/etc/rc.d/rc.docker status`.
- **Array status:** `/usr/local/sbin/mdcmd status`
  (`mdState`, `mdResync`, `sbSyncErrs`). `mdResync=0`
  means no parity check or rebuild is running;
  `mdResyncAction` only names the preset action.
  Per-disk state: `/var/local/emhttp/disks.ini`.

## Journal Replacement (Activity Check, Changelog)

There is no journal. `logger -t heinzel` writes to
`/var/log/syslog`, and `/var/log` is a 128 MB tmpfs:
**every heinzel line is lost at the next reboot.**

- Keep logging with `logger -t heinzel` — it is what
  other admins on the box see.
- Activity check: `grep -h heinzel /var/log/syslog*`.
  An empty result after a recent reboot means
  nothing; say so instead of reporting "no activity".
- The local changelog
  (`memory/servers/<hostname>/changelog.log`) is the
  only durable record. Write it for every change.

## Updates

- **OS:** Tools → Update OS in the WebGUI (signed
  download, keeps the previous release in
  `/boot/previous/` for "Restore"). Needs a reboot.
  Plugins that ship kernel modules (NVIDIA driver,
  sensor drivers) download a build for the new
  kernel at boot; check that one exists for the new
  kernel before updating.
- **Plugins** are the package manager. Unraid itself
  checks only weekly (`plugincheck`, cron Monday
  00:10). Check on demand without installing
  anything:

      /usr/local/sbin/plugin checkall

  This downloads the latest `.plg` files to
  `/tmp/plugins/`. Compare them with the installed
  ones in `/var/log/plugins/` using Unraid's own
  version function, so entity-based version strings
  resolve:

      H=/usr/local/emhttp/plugins/dynamix.plugin.manager
      v() {
        php -r 'require $argv[1]; echo plugin("version", $argv[2]);' \
          "$H/include/PluginHelpers.php" "$1"
      }
      for l in /var/log/plugins/*.plg; do
        n=$(basename "$l")
        [ "$n" = unRAIDServer.plg ] && continue
        echo "$n $(v "$l") $(v "/tmp/plugins/$n")"
      done

  `unRAIDServer.plg` is the OS itself; skip it here.
  Report outdated plugins, let the user update them
  in the WebGUI. `plugin remove <name>.plg` uninstalls
  a plugin and moves its `.plg` to
  `/boot/config/plugins-removed/`.
- **NVIDIA driver plugin:** it downloads new drivers
  by itself to
  `/boot/config/plugins/nvidia-driver/packages/<kernel>/`.
  They load only at boot. A version there that
  differs from `nvidia-smi` means a reboot is
  pending.

## Firewall

Unraid ships no host firewall: `iptables` INPUT
policy is ACCEPT, plus the libvirt chains. Treat
this as the expected state, flag it, and discuss it
with the user before adding anything — see
`CLAUDE.md` → Firewall & network.

## Docker

### Which containers start after a reboot

The Unraid autostart list
(`/var/lib/docker/unraid-autostart`, the "Autostart"
switch in the Docker tab), not the restart policy.
`/etc/rc.d/rc.docker` stops every container labelled
`net.unraid.docker.managed` with `docker stop` at
shutdown. Docker counts that as a manual stop, so
`restart: unless-stopped` does not bring the
container back. At start, `rc.docker` starts only
the containers on the autostart list, in its order.
Containers without the label (plain `docker compose`
stacks) are killed with the daemon instead and come
back through their restart policy.

So for a Compose stack that carries the label, put
the container on the autostart list, or it stays
down after the next reboot.

### Restarting Docker over SSH

Never run `rc.docker restart` from an SSH session as
is. sshd's PAM stack runs `pam_elogind`, so the
session has `XDG_RUNTIME_DIR=/run/user/0`. dockerd
and containerd inherit it, and containerd's go-runc
writes every exec spec to
`$XDG_RUNTIME_DIR/runc-process*`
(`os.CreateTemp(os.Getenv("XDG_RUNTIME_DIR"), …)` in
go-runc's `runc.go`). elogind removes `/run/user/0`
when root's last session ends. From then on every
`docker exec` and every health check fails with
(one line in the log):

    OCI runtime exec failed: open
    /run/user/0/runc-process<N>: no such file or directory

The containers keep running, but all health checks
report unhealthy. Restart Docker like this instead,
or from Settings → Docker in the WebGUI:

    env -u XDG_RUNTIME_DIR /etc/rc.d/rc.docker restart

Check afterwards; this must print nothing:

    tr '\0' '\n' < /proc/$(pgrep -x dockerd)/environ | grep XDG_RUNTIME_DIR

## User Scripts Plugin — Schedules That Never Fire

A schedule can look configured in the GUI and still
never run.

### Named frequencies (hourly/daily/weekly/monthly)

- They run at fixed times, not at the time the GUI
  shows: the stock Slackware crontab fires
  `run-parts` at hourly :47, daily 04:40, weekly
  Sunday 04:30, monthly on the 1st 04:20. Shims in
  `/etc/cron.{hourly,daily,weekly,monthly}/` call
  `startSchedule.php <freq>`.
- `startSchedule.php` reads a **tmpfs copy**,
  `/tmp/user.scripts/schedule.json`. It is refreshed
  from `/boot/config/plugins/user.scripts/schedule.json`
  only when the tmp copy is missing. After editing
  the boot copy over SSH, copy it to the tmp path,
  or the change waits for the next reboot.

### Custom cron expressions

The GUI does three things, and all three are needed:

1. `frequency: "custom"` plus the `custom` cron
   string in both copies of `schedule.json`.
2. A line in
   `/boot/config/plugins/user.scripts/customSchedule.cron`.
3. `/usr/local/sbin/update_cron`.

Editing `schedule.json` alone shows the schedule in
the GUI while nothing runs.

### `update_cron`

It concatenates every `*.cron` file under
`/boot/config/plugins/dynamix/` and under each
installed plugin's `/boot/config/plugins/<plugin>/`
and **replaces** `/etc/cron.d/root` with the result.
A hand edit to `/etc/cron.d/root` is lost at the
next call (GUI save, array start). Change schedules
only through a plugin's own `*.cron` file.

### Did a script run?

    ls -la /tmp/user.scripts/finished/<script name>
    tail /tmp/user.scripts/tmpScripts/<script name>/log.txt

Both are tmpfs and reset at reboot. A log the script
writes itself to the array survives.

## Unassigned Devices Plugin — Same tmpfs Trap

The plugin reads and writes
`/tmp/unassigned.devices/config/unassigned.devices.cfg`,
created from the boot copy
`/boot/config/plugins/unassigned.devices/unassigned.devices.cfg`
at plugin start. An out-of-GUI edit to the boot copy
alone (for example `automount="yes"` in a device
section) is ignored until reboot. Edit both copies,
or copy the boot copy over the tmp copy.

## Housekeeping on Unraid

The Linux baseline mostly does not apply (no
package manager, no systemd units, no journal). Use
instead:

- Array and disks: `mdcmd status`,
  `/var/local/emhttp/disks.ini`, `smartctl -H` per
  disk (USB bridges may need `-d sat`).
- Plugin updates and pending NVIDIA driver: see
  Updates above.
- Docker: health of all containers, and the
  `XDG_RUNTIME_DIR` check above.
- Time: `ntpq -pn`.
