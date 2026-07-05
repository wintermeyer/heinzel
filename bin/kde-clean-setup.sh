#!/usr/bin/env bash
#
# kde-clean-setup.sh — reproduce the heinzel KDE/Plasma optimizations
# on a fresh Kubuntu/Ubuntu KDE install.
#
# Covers:
#   A.1  clean CLI-SSH   — one OpenSSH agent, no GUI passphrase dialog
#   C    samba server    — purge unused server, keep smb4k/smbclient
#   F    coredumps       — cap MaxUse so AppImage/Electron crashes
#                          cannot bloat /var
#   base Baloo off       — disable the file indexer (often ON by default)
#
# Idempotent: safe to run repeatedly. Supports --dry-run.
# Rationale + per-host record:
#   memory/servers/Thinkpad-E16/kde-optimization.md
#   memory/ssh-keys.md   (ssh-agent / clean CLI-SSH section)
#
# Distro note: package steps assume apt (Kubuntu/Ubuntu). The systemd
# and Plasma-env steps are generic KDE. On Fedora/openSUSE adapt the
# package manager (dnf/zypper) yourself.
#
# Usage:
#   bin/kde-clean-setup.sh            # apply
#   bin/kde-clean-setup.sh --dry-run  # show what would happen
#
set -uo pipefail

DRY=0
case "${1:-}" in
  --dry-run|-n) DRY=1 ;;
  -h|--help)
    sed -n '2,30p' "$0" | sed 's/^#\?//'
    exit 0 ;;
  "") ;;
  *) echo "Unbekannte Option: $1 (siehe --help)"; exit 2 ;;
esac

say()  { printf '\n=== %s ===\n' "$*"; }
note() { printf '  %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }
# run CMD…  — execute, or just print in dry-run mode
run() {
  if [ "$DRY" = 1 ]; then printf '  [dry-run] %s\n' "$*"; else eval "$*"; fi
}

[ "$DRY" = 1 ] && note "DRY-RUN: es wird nichts verändert."

# --- A.1  clean CLI-SSH -----------------------------------------------
say "A.1  clean CLI-SSH (ein OpenSSH-Agent, kein GUI-Dialog)"
if have systemctl; then
  run "systemctl --user mask gcr-ssh-agent.socket gcr-ssh-agent.service || true"
  run "systemctl --user enable ssh-agent.socket || true"
fi
ENVD="$HOME/.config/plasma-workspace/env"
ENVF="$ENVD/zz-clean-cli-ssh.sh"
if [ -f "$ENVF" ] && [ "$DRY" = 0 ]; then
  note "Override existiert bereits: $ENVF"
else
  run "mkdir -p '$ENVD'"
  if [ "$DRY" = 1 ]; then
    note "[dry-run] schreibe $ENVF (SSH_ASKPASS_REQUIRE=never; unset SSH_ASKPASS)"
  else
    cat > "$ENVF" <<'EOF'
#!/bin/sh
# clean CLI-SSH: SSH-Passphrasen im Terminal statt GUI (ksshaskpass)
export SSH_ASKPASS_REQUIRE=never
unset SSH_ASKPASS
EOF
    chmod +x "$ENVF"
    note "geschrieben: $ENVF"
  fi
fi
note "Hinweis: wirksam ab nächstem Logout/Login."
note "ssh-config (persönlich): Git-Block VOR 'Host *' + 'AddKeysToAgent yes'"
note "  in 'Host *' — siehe kde-optimization.md, falls Host * BatchMode yes setzt."

# --- C  samba server purge (client bleibt) ----------------------------
say "C  Samba-Server entfernen (smb4k/smbclient behalten)"
if have apt-get; then
  if dpkg -l samba 2>/dev/null | grep -q '^ii'; then
    run "sudo apt-get purge -y samba"
  else
    note "Paket 'samba' (Server) nicht installiert — nichts zu tun."
  fi
else
  note "kein apt-get — Schritt übersprungen (Distro selbst anpassen)."
fi

# --- F  coredump cap --------------------------------------------------
say "F  Coredumps deckeln (MaxUse=500M) + vorhandene leeren"
run "sudo rm -f /var/lib/systemd/coredump/* || true"
run "sudo mkdir -p /etc/systemd/coredump.conf.d"
if [ "$DRY" = 1 ]; then
  note "[dry-run] schreibe /etc/systemd/coredump.conf.d/heinzel-maxuse.conf (MaxUse=500M)"
else
  printf '[Coredump]\nMaxUse=500M\n' \
    | sudo tee /etc/systemd/coredump.conf.d/heinzel-maxuse.conf >/dev/null \
    && note "Cap gesetzt: MaxUse=500M"
fi

# --- base  Baloo file indexer off -------------------------------------
say "Baseline  Baloo-Datei-Indexer deaktivieren"
if have balooctl6; then
  run "balooctl6 disable || true"
elif have balooctl; then
  run "balooctl disable || true"
else
  note "balooctl nicht gefunden — übersprungen."
fi

say "Fertig. Verifikation nach Re-Login:"
note 'echo \$SSH_AUTH_SOCK   # …/openssh_agent (nicht …/gcr/ssh)'
note 'systemctl --user is-enabled gcr-ssh-agent.socket   # masked'
note 'systemd-analyze cat-config systemd/coredump.conf | grep MaxUse'
note 'balooctl6 status   # deaktiviert'
