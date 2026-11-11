# macOS

Rules for macOS (Apple Silicon and Intel).

## Package Manager

- Use [Homebrew](https://brew.sh/) (`brew`).
- **Never run `brew` with `sudo`** — Homebrew is
  designed to run as a normal user and will refuse
  or break if invoked with `sudo`.
- Set `HOMEBREW_NO_AUTO_UPDATE=1` before `brew install`
  or `brew upgrade` to prevent Homebrew from running a
  potentially slow auto-update mid-command.
- Homebrew prefix differs by architecture:
  - Apple Silicon (arm64): `/opt/homebrew/`
  - Intel (x86_64): `/usr/local/`
  - Detect at runtime: `brew --prefix`
- Update Homebrew itself: `brew update`
- Upgrade all packages: `brew upgrade`
- Dry-run before upgrading: `brew upgrade --dry-run`
- Install a formula: `brew install <formula>`
- Install a GUI app (cask): `brew install --cask <app>`
- List installed: `brew list`
- Check for issues: `brew doctor`

## Version Detection

- macOS version: `sw_vers -productVersion`
  (e.g. `XX.Y.Z`)
- macOS build: `sw_vers -buildVersion`
- Product name: `sw_vers -productName` (e.g. `macOS`)
- Architecture: `uname -m` (`arm64` or `x86_64`)
- There is no `/etc/os-release` on macOS.
- Hardware: `sysctl` for CPU and RAM (see Notes),
  `df -h`.
- Lifecycle: Apple typically supports the current
  and the two prior major versions.

## Firewall

- **Application Firewall** (built-in):
  - Check status:
    `/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate`
  - Enable:
    `sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on`
  - List app rules:
    `/usr/libexec/ApplicationFirewall/socketfilterfw --listapps`
  - Block-all state:
    `/usr/libexec/ApplicationFirewall/socketfilterfw --getblockall`
  - Stealth mode:
    `/usr/libexec/ApplicationFirewall/socketfilterfw --getstealthmode`
  - These two are the closest macOS equivalents to a
    "default deny incoming" policy: block-all rejects
    all incoming connections, stealth mode stops the
    Mac from answering probes (e.g. ping).
- **`pf`** (packet filter) exists but is rarely needed
  on typical Macs. Only use `pf` if the user has
  specific port-level filtering requirements.
- A disabled firewall on macOS is common and less
  alarming than on a Linux server — Macs are usually
  behind a NAT router. Flag it to the user but do not
  treat it as urgent.

## Automatic Security Updates

- List available updates: `softwareupdate --list`
- Install all updates:
  `sudo softwareupdate --install --all`
- **Warning:** `--install --all` can pull OS updates
  that need a restart. Always run `--list` first,
  install OS updates only with explicit user
  approval, and never use `--restart`/`-R` without
  asking (CLAUDE.md: ask before reboots). Some
  updates remain incomplete until the Mac reboots.
- Check auto-update preferences:
  ```
  defaults read \
    /Library/Preferences/com.apple.SoftwareUpdate \
    AutomaticCheckEnabled
  defaults read \
    /Library/Preferences/com.apple.SoftwareUpdate \
    CriticalUpdateInstall
  ```
- `CriticalUpdateInstall` should be `1` (enabled).
  If it's `0` or missing, recommend enabling it:
  ```
  sudo defaults write \
    /Library/Preferences/com.apple.SoftwareUpdate \
    CriticalUpdateInstall -bool true
  ```

## Service Manager

- macOS uses `launchd` / `launchctl`, not systemd.
- Plist locations:
  - System daemons: `/Library/LaunchDaemons/`
  - System agents: `/Library/LaunchAgents/`
  - User agents: `~/Library/LaunchAgents/`
- For Homebrew-installed services, prefer
  `brew services`:
  - List: `brew services list`
  - Start: `brew services start <service>`
  - Stop: `brew services stop <service>`
  - Restart: `brew services restart <service>`
  - Reload vs restart: see `rules/service-reload.md`
    for the auto-proceed policy and
    `memory/service-policy.md` opt-out / opt-in
    lists.
- **`brew upgrade` does not restart a running
  service.** The new version lands in the Cellar
  while the old process keeps running out of the
  directory brew just deleted. Check the version the
  service itself reports, not the binary on `PATH`,
  and follow up with `brew services restart
  <service>`.
- For non-Homebrew services:
  - Load: `sudo launchctl load <plist>`
  - Unload: `sudo launchctl unload <plist>`
  - List running: `launchctl list`

## Service Classes

Installed members (`rules/service-class-check.md`,
phase 1), best-effort:

```bash
members=(httpd nginx caddy lighttpd
         postgresql mariadb mysql
         postfix exim opensmtpd msmtp
         chrony unbound bind dnsmasq
         podman containerd)
brew list --formula \
  | grep -Fxf <(printf '%s\n' "${members[@]}")
```

macOS installs are user-scoped rather than
system-wide, so this phase is advisory on macOS.
Still run it; still warn.

Install dry run (phase 2):

```bash
brew deps --include-build <pkg>
```

## Listening Ports

```bash
lsof -iTCP:<port> -sTCP:LISTEN -P -n
```

Shows command, PID, and user. Use `sudo` to see
processes owned by other users.

## Journal

```
/usr/bin/log show --last 7d \
  --predicate 'process == "logger"' --info 2>&1 \
  | grep heinzel
```

Two details that are not optional here:

- **Call `/usr/bin/log` by absolute path.** `log` is a
  common shell alias or function (git log wrappers,
  oh-my-zsh plugins). A shadowed `log` fails with
  something like `(eval):log:1: too many arguments`,
  which looks nothing like a missing-entries result.
- **Never redirect stderr to `/dev/null`.** With
  `2>/dev/null` a shadowed or failing `log` produces
  empty output, and "no activity" is exactly what
  empty output means in `rules/activity-check.md` —
  so a broken check reads as a clean host. Keep
  `2>&1` and treat any line that is not a log entry
  as a failed check, not silence.

`senderImagePath CONTAINS "logger"` also works but
matches more broadly; `process == "logger"` is the
narrower predicate.

## Rollback Timer

- Arm: the generic `nohup` variant in
  `rules/rollback-timer.md`.
- Disarm:
  `pkill -F /var/run/heinzel-rollback-<ts>.pid`
- Did it run: the Journal command above, with
  `--last 10m`.

## SIP and Gatekeeper

- **System Integrity Protection (SIP):**
  - Check status: `csrutil status`
  - SIP protects `/System/`, `/usr/` (except
    `/usr/local/`), `/bin/`, `/sbin/`.
  - **Never suggest disabling SIP** without an
    explicit user request and a clear explanation of
    the risks. Disabling SIP requires booting into
    Recovery Mode.
- **Gatekeeper:**
  - Check status: `spctl --status`
  - Controls which apps can run based on code signing.
  - Do not disable without user request.

## Directory Conventions

- Homebrew prefix: detect with `brew --prefix`
  (`/opt/homebrew/` on Apple Silicon,
  `/usr/local/` on Intel)
- System-wide config: `/Library/`
- Per-user config: `~/Library/`
- System logs: `/var/log/` and unified log
  (`log show`)
- Application support: `~/Library/Application Support/`
- Homebrew configs:
  `$(brew --prefix)/etc/` (e.g. nginx config)

## Notes

- **Remote Login (SSH)** must be enabled for remote
  administration:
  - Check: `sudo systemsetup -getremotelogin`
  - Enable: `sudo systemsetup -setremotelogin on`
- macOS alternatives for Linux commands:
  - `free` does not exist — use:
    `sysctl -n hw.memsize` (bytes, divide by
    1073741824 for GB)
  - `lscpu` does not exist — use:
    `sysctl -n machdep.cpu.brand_string` (model),
    `sysctl -n hw.ncpu` (core count)
  - `journalctl` does not exist — use `log show`
    (see Changelog section in CLAUDE.md)
  - `df -h` works the same.
- `logger` works on macOS and writes to the unified
  log. Reading back requires `log show` (see
  CLAUDE.md Changelog section).
- `mise` works unchanged on macOS — same as Linux.

## Common Pitfalls

- **No `systemctl`** — use `launchctl` or
  `brew services` instead.
- **Never `sudo brew`** — Homebrew explicitly warns
  against this and it can break file permissions in
  the Homebrew prefix.
- **Homebrew path varies by architecture** — always
  use `brew --prefix` rather than hardcoding
  `/usr/local/` or `/opt/homebrew/`.
- **SIP restrictions** — cannot modify protected
  system directories (`/System/`, `/usr/`, `/bin/`,
  `/sbin/`). This is by design.
- **`sudo` requires the admin group** — a standard
  macOS user without admin privileges cannot use
  `sudo`.
- **`free` and `journalctl` do not exist** — use the
  macOS alternatives listed in the Notes section.
- **`/etc/os-release` does not exist** — use
  `sw_vers` for version detection.
- **Disk Utility vs. command-line** — `diskutil`
  can modify the partition map, and `bless` what
  the Mac boots. Both are Heinzel Pro's work
  (`CLAUDE.md` → What Heinzel does not do); the
  guard denies them. `diskutil list`,
  `diskutil info` and `bless --info` are always
  allowed.
