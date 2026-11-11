#!/bin/sh
# guard-taboos.sh — PreToolUse hook (matcher: Bash, and
# Edit|Write|NotebookEdit with the argument "file").
#
# Mechanically enforces heinzel's absolute taboos from
# CLAUDE.md → Critical Safety Rules, below the model layer:
#
#   - halt / poweroff / shutdown without -r / init 0 /
#     telinit 0 / sysrq-trigger
#   - mkfs / mke2fs / newfs* / wipefs (write forms)
#   - partition-table writers (fdisk/cfdisk/sfdisk/gdisk/
#     sgdisk/parted/gpart/gpt/diskutil write forms)
#   - raw-device wipers that leave the partition table
#     alone (blkdiscard, nvme format/sanitize, hdparm
#     secure-erase, badblocks -w, shred, dd, a redirect,
#     tee, cp or a download onto a disk device)
#   - destroying SSH keys (host keys, authorized_keys, id_*,
#     or the directory holding them: ~/.ssh, an appliance
#     key store such as /conf/sshd) by any means: rm/shred/
#     truncate/mv/chmod/chown/install/ln/setfacl/patch, find
#     -delete, a redirect, ssh-keygen -f, or a write into
#     one (tee, cp/rsync/scp, dd, sed -i, an editor, curl -o
#     and other output flags)
#   - writes to sshd_config(.d/) under any .../etc/ssh, or
#     to a file an appliance merges into it (/etc/sshd_extra)
#   - boot loaders and firmware variables (Heinzel Pro's
#     work since 3.0): efibootmgr write forms, grub-install,
#     update-grub, grub-mkconfig -o, bootctl install/update/
#     remove/set-*, bless write forms, efivar -w, a write or
#     delete under /sys/firmware/efi/efivars/
#   - accounts and sudo (Heinzel Pro's work since 3.0):
#     deleting an account or a group, visudo, vipw/vigr, any
#     write to sudoers(.d/), to doas.conf or to the account
#     files (/etc/passwd, shadow, group, master.passwd)
#   - writing, moving or deleting the server lock
#     /etc/heinzel.conf, which only the machine's owner sets
#     (rules/access-control.md)
#   - any of those paths reached through a language
#     runtime (python/perl/ruby/node/awk ...), whose file
#     I/O looks nothing like a shell write; awk is exempt
#     for the account files, which the security skill reads
#     with it
#   - a redirect onto a $( ) lookup, or an arrow onto any
#     expansion, whose target nobody sees before it runs
#     (issue #51)
#   - a file-edit tool pointed at sshd_config, a key file,
#     sudoers, an account file, an efivar, the server lock or
#     a raw disk device (see the file-mode section)
#
# What it deliberately does NOT scan: the body of a heredoc that
# is written to an ordinary file by cat or tee (issue #8). That
# is documentation, not code. Every other heredoc — above all
# `ssh host bash -s <<EOF`, whose body runs remotely — is scanned
# in full.
#
# The taboos are EFFECTS, not a list of binaries. When a new
# tool reaches one of the effects above, it belongs in here,
# and the test matrix gets a line for it. Issue #5 came from
# the reverse: the rules named tools, so cfdisk, diskutil
# eraseDisk, gpt destroy, blkdiscard and a truncating
# redirect over authorized_keys all walked through. Issue #6
# was the same mistake one level in: the rules protecting a
# PATH named the ways a shell spells a write, so
# python3 -c "open('/etc/ssh/sshd_config','a').write(...)"
# was not a write to any of them. Issue #7 was the same
# mistake one level UP the path: the protected paths were key
# FILENAMES, so chown -R alice:alice /home/alice/.ssh
# re-permissioned every key in the directory without naming
# one, while the spelled-out chmod on authorized_keys was
# denied.
#
# The hook scans the ENTIRE command string, so taboos hidden
# inside wrappers like  ssh root@host "mkfs.ext4 /dev/sda1"
# are caught regardless of quoting. A PreToolUse deny blocks
# in every permission mode, including bypassPermissions.
#
# Rules that exempt a read-only form (fdisk -l, sfdisk -d,
# shutdown -r) evaluate that exemption per invocation, not
# against the whole string: it must sit in the same segment as
# the taboo command and follow it. This is stricter than a plain
# whole-string scan, so a taboo word inside quoted prose --
# documentation, commit messages, ticket notes -- is matched
# more often.
#
# Issue #8 narrowed the biggest source of that noise: a heredoc
# body written to a file by cat or tee is data, not code, and is
# no longer scanned. See the heredoc section below for the exact
# conditions and for why the consumer, never the body, decides.
# Writing heinzel's own changelog no longer trips the guard.
#
# Known, accepted false positives that REMAIN (the patterns are
# deliberately coarse — this guard protects production disks, not
# grep pipelines):
#   - A taboo word as a quoted ARGUMENT: `grep poweroff
#     /var/log/syslog`, `systemctl status shutdown.target`.
#     segments() splits on quotes so that ssh host "shutdown -h
#     now" is caught, and after that split an argument and an ssh
#     payload have the same shape. Separating them needs a
#     per-command list of which arguments are data, which is
#     open-ended and would reopen issue #4. Rephrase the probe
#     (`grep 'power[o]ff'`) instead.
#   - `cp /etc/ssh/sshd_config /tmp/` is blocked although it only
#     reads the file — copy out via `cat /etc/ssh/sshd_config >
#     /tmp/copy` instead.
#   - The sshd paths match as substrings, with no boundary on
#     either side: sshd_config.bak, /etc/sshd_extra.bak and a
#     copy staged under another root (mnt/etc/ssh/sshd_config)
#     count as the real file. The left side stays open on
#     purpose, so /usr/local/etc/ssh and a copy under a mount
#     point are covered. Keep backups outside the guarded
#     path, e.g. /root/backup/sshd_config. The same holds for
#     sudoers and the account files: cp /etc/sudoers /root/ is
#     denied, cat /etc/sudoers > /root/sudoers.bak is not.
#   - ssh-keygen with a private key path ANYWHERE in the command:
#     `file /etc/ssh/ssh_host_ed25519_key; ssh-keygen -lf
#     ...key.pub` is denied although each part passes alone.
#     Matching per invocation would miss K=<key>; ssh-keygen -f
#     $K, and what -l does next to ssh-keygen's write modes is
#     unverified, so there is no -l exemption either. Run the
#     fingerprint in a call of its own (rules/secrets.md).
#   - An ssh ControlPath under .ssh/ makes any rm, mv or chmod in
#     the same command look like a key operation. heinzel keeps
#     its sockets in ~/.cache/heinzel for that reason
#     (rules/ssh-connections.md).
#   - rsync with -e "ssh -i ~/.ssh/id_..." AFTER its operands
#     reads as a copy onto that key, because writes_to takes the
#     last word as the destination. Put -e before the operands.
#
# Being blocked is EXPECTED behavior. Explain it to the user.
# Never rephrase, re-quote, or otherwise obfuscate a command to
# evade this guard.
#
# Heinzel-repo development note: a commit message piped straight
# into `git commit -m`/`-F -` still flows through the command
# string, and git is not a data sink this hook recognizes, so
# writing ABOUT taboo commands there can still trigger it. Write
# the message to a file with a non-Bash tool and use
# `git commit -F <file>` — that executes nothing on any server.
#
# There is no off switch. Up to 2.x the operator could export
# HEINZEL_GUARD_DISABLE=1 for an OS replacement; since 3.0 that
# work is Heinzel Pro's (CLAUDE.md -> What Heinzel does not do),
# and the variable changes nothing. An inline assignment of it
# inside a proposed command is still denied: a model that tries
# to disarm the guard is the thing to stop.

INPUT=$(cat)

# Extract the Bash tool's command string. Without jq (or on
# malformed input) fall back to scanning the raw stdin text —
# that can only over-block, never under-block.
CMD=""
if command -v jq >/dev/null 2>&1; then
  CMD=$(printf '%s' "$INPUT" \
    | jq -r '.tool_input.command // empty' 2>/dev/null) || CMD=""
fi
[ -n "$CMD" ] || CMD="$INPUT"

# --- Heredoc bodies that are DATA, not code -------------------
# Documentation is the one thing that legitimately contains taboo
# words: a changelog entry describing a shutdown checkpoint, a
# rule file about fdisk, a commit message. Scanned as a command
# string, that prose is indistinguishable from an invocation, and
# the guard blocked heinzel's own changelog write over the word
# "shutdown" inside a heredoc.
#
# A heredoc body is only safe to skip when the command consuming
# it CANNOT execute it. That is decided by the consumer, never by
# the body, because these two look almost identical:
#
#   cat >> notes.md <<EOF          <- the body is text
#   ssh host bash -s <<EOF         <- the body RUNS, remotely
#
# So the body is dropped only when the first line is one lone
# pure data sink -- cat or tee writing to an ordinary file -- and
# every other condition fails CLOSED back to scanning everything:
# more than one heredoc, an unrecognized consumer, a missing
# terminator, a /dev/ target, or any awk failure. Whatever sits
# OUTSIDE the body (the first line itself, and everything after
# the terminator) is always still scanned, so
#   cat >> f <<EOF ... EOF; shutdown -h now
# is caught on the trailing command exactly as before.
#
# Deliberate boundary: a data sink whose target is itself
# executed later is excluded from the exemption, because writing
# a taboo INTO such a file reaches the effect on a delay. That
# set is named by EFFECT -- "something runs this file later" --
# and enumerated as scheduler and init locations, anything under
# /etc, launchd, the executable directories, script files by
# extension, and the shell start-up files. Over-matching there
# costs nothing: it only means the body is scanned as ordinary
# command text, which is what every non-exempt command gets.
# The wider boundary stays the documented one -- this hook is a
# backstop against the everyday mistake, not a sandbox. A body
# built at runtime, or fetched, defeats any string matcher.
#
# Writes AT a protected path need no rule here: the sink line
# itself is never dropped, so cat >> ~/.ssh/authorized_keys is
# still judged by the normal SSH-key rules below.
#
# NOT fixed by this, on purpose: a taboo word quoted as an
# ARGUMENT, e.g. grep shutdown /var/log/syslog. segments() splits
# on quotes so that ssh host "shutdown -h now" is caught, and
# after that split the grep argument and the ssh payload are the
# same shape. Telling them apart needs a per-command list of
# which arguments are data, which is open-ended and would reopen
# issue #4. Rephrase the probe (grep 'shut[d]own') instead.
CMD_NOHEREDOC=$(printf '%s\n' "$CMD" | awk '
  BEGIN { q = sprintf("%c", 39) }
  NR == 1 {
    first = $0
    # A raw device target is never an ordinary file.
    if (first ~ /\/dev\//) { bad = 1; exit }
    # Targets that something later EXECUTES are not inert either.
    # Schedulers, init and unit locations, anything under /etc:
    if (first ~ /cron|systemd|init\.d|rc\.d|profile\.d|\/etc\//) {
      bad = 1; exit
    }
    # launchd jobs (macOS):
    if (first ~ /launchd|LaunchAgents|LaunchDaemons|\.plist/) {
      bad = 1; exit
    }
    # the executable directories -- /bin /sbin /usr/bin ~/bin ...:
    if (first ~ /\/s?bin\//) { bad = 1; exit }
    # a script file by extension:
    if (first ~ /\.(sh|bash|zsh|ksh|command|py|pl|rb)([ \t<]|$)/) {
      bad = 1; exit
    }
    # a shell start-up file, sourced on the next login:
    if (first ~ /\.(bashrc|bash_profile|bash_login|zshrc|zshenv|zprofile|zlogin|kshrc|cshrc|profile|login)([ \t<]|$)/) {
      bad = 1; exit
    }
    # Exactly one heredoc, so there is exactly one body to find.
    tmp = first; cnt = 0
    while (match(tmp, /<</)) { cnt++; tmp = substr(tmp, RSTART + 2) }
    if (cnt != 1) { bad = 1; exit }
    # The whole first line must be the data sink and nothing else:
    # no ; & | backtick $( ) that could smuggle a second command.
    # The target may arrive either way round -- cat writes through
    # a redirect (cat > f), tee takes it as a plain argument
    # (tee f) -- so both separators are allowed. The path token
    # itself still excludes every character that could start
    # another command, and < > stay out of it so the heredoc
    # operator can never be swallowed as a filename.
    p = "[\"" q "]?[^ \t;|&`$()<>\"" q "]+[\"" q "]?"
    shape = "^[ \t]*(cat|tee)([ \t]+-a)?(([ \t]*>>?[ \t]*|[ \t]+)" p ")?[ \t]*<<-?[ \t]*[\"" q "]?[A-Za-z_][A-Za-z0-9_]*[\"" q "]?[ \t]*$"
    if (first !~ shape) { bad = 1; exit }
    d = first
    sub(/^.*<<-?[ \t]*/, "", d)
    gsub(/["]/, "", d); gsub(q, "", d); sub(/[ \t]*$/, "", d)
    if (d !~ /^[A-Za-z_][A-Za-z0-9_]*$/) { bad = 1; exit }
    delim = d
    print first
    next
  }
  # Drop the body. Ending it on a whitespace-stripped match too is
  # deliberate: erring early only scans MORE text, never less.
  !ended {
    t = $0; sub(/^[ \t]+/, "", t)
    if ($0 == delim || t == delim) ended = 1
    next
  }
  { print }
  END { if (bad || !ended) exit 1 }
' 2>/dev/null)
GUARD_STRIP_STATUS=$?
# Only a clean parse of a recognized data sink may shrink the
# scanned text. Anything else keeps the full command string.
if [ "$GUARD_STRIP_STATUS" -eq 0 ] && [ -n "$CMD_NOHEREDOC" ]; then
  CMD="$CMD_NOHEREDOC"
fi

# The command string, plus one line per invocation it contains.
# Separators are ; & | quotes and newlines. Quotes count on
# purpose: to the shell, ssh -l root host "fdisk /dev/sda" is
# ONE invocation, but it carries a second command inside, and
# only splitting there puts fdisk in a segment that no longer
# holds ssh's -l. The FULL string stays in the list, so this can
# only ever block more, never less.
segments() {
  printf '%s\n' "$CMD"
  printf '%s' "$CMD" | tr ';&|"'"'"'\n' '\n'
}

hit() {
  segments | grep -Eq "$1"
}

# Case-insensitive variant. diskutil accepts its verbs in any
# case, so eraseDisk and erasedisk are the same command.
hit_i() {
  segments | grep -Eiq "$1"
}

# A raw disk device, as opposed to /dev/null, /dev/stderr,
# /dev/shm or /dev/disk/by-id (all of which are ordinary and
# must stay usable).
DEV='/dev/(r?sd|vd|xvd|hd|r?wd|nvme|mmcblk|nbd|loop|da|ada|nda|r?disk[0-9])'

# Any SSH key file, OR the directory that holds them. The
# directory belongs in here because re-permissioning or removing
# it reaches every key through the parent without ever naming a
# key: chown -R alice:alice /home/alice/.ssh hands the whole set
# to another owner, chmod 000 /root/.ssh hides it from sshd, and
# rm -rf ~/.ssh deletes it. The old pattern listed key FILENAMES
# only, so all three walked through while the spelled-out
# chmod 600 ~/.ssh/authorized_keys was denied. Same mistake as
# issues #5 and #6, one level up the path: the rule named the
# spelling of the target instead of the effect on it.
#
# Boundary, deliberately left open: a command that destroys an
# enclosing directory without naming .ssh at all (rm -rf /home/
# alice, a whole-filesystem operation) reaches the same effect
# and is NOT caught here. Closing it would mean treating every
# home directory as a key store. This is a backstop against the
# everyday mistake, not a sandbox.
#
# KEYPRIV additionally excludes a trailing .pub, so reading or
# copying a public key stays allowed while the private half does
# not. It stays filename-only on purpose: it guards a truncating
# redirect and ssh-keygen -f, neither of which is meaningful
# against a directory. KEYFILE is the same set without the
# trailing boundary, for writes_to below.
#
# Host keys and sshd_config do not always live in /etc/ssh:
# the OpenSSH port or package puts them in /usr/local/etc/ssh
# (FreeBSD; on OPNsense only sshd_config, see KEYDIR) or
# /opt/homebrew/etc/ssh. No pattern here
# is anchored on the left, so /etc/ssh matches every such prefix,
# and the rules must keep it that way instead of listing
# prefixes.
#
# KEYDIR adds an appliance key store (OPNsense: /conf/sshd) to
# .ssh; the rest of /conf is config and stays ordinary work.
# /etc/ssh itself is NOT a key store: it also holds ssh_config
# and moduli, so rm -rf /etc/ssh or chmod -R on it is left open,
# on the same terms as the home directory above.
HOSTKEY='(/etc/ssh|/conf/sshd)/ssh_host_'
KEYDIR='(\.ssh|/conf/sshd)'
KEY="($HOSTKEY|authorized_keys|$KEYDIR"'(/|[^[:alnum:]_.-]|$))'
KEYFILE="($HOSTKEY"'[[:alnum:]_-]*key|\.ssh/id_[[:alnum:]_-]+|authorized_keys)'
KEYPRIV="$KEYFILE"'([^.[:alnum:]]|$)'

# sshd's config: sshd_config, its drop-in directory, and a file
# an appliance merges into it when it regenerates the config
# (pfSense appends /etc/sshd_extra). The .d suffix is optional,
# so a plain hit on SSHD also finds the bare file. Then the
# editors that rewrite a file in place.
SSHD='/etc/(ssh/sshd_config(\.d(/[[:alnum:]_.-]*)?)?|sshd_extra)'
EDITOR='(vi|vim|nvim|nano|emacs|ed)'

# Heinzel Pro's work since 3.0, backed here where a write locks
# people out or cannot be undone (CLAUDE.md -> What Heinzel does
# not do). sudoers and its drop-ins, unanchored on the left like
# SSHD so /usr/local/etc/sudoers (FreeBSD) matches; the account
# files, where a direct write bypasses every check useradd and
# passwd make; and the firmware variables, where a deleted entry
# has bricked boards. All three stay readable.
#
# /etc/doas.conf is OpenBSD's sudoers: one file, no drop-ins, and
# a write to it grants or revokes root the same way.
SUDOERS='/etc/(sudoers(\.d(/[[:alnum:]_.-]*)?)?|doas\.conf)'
ACCOUNTS='/etc/(passwd|shadow|gshadow|group|master\.passwd|s?pwd\.db)'
EFIVARS='/sys/firmware/efi/efivars'

# The server lock. The machine's owner writes it to keep heinzel
# hands-off; a heinzel that could flip it to true or delete it
# would make it worthless. Matched by its file name alone, in any
# case: the full path misses /ETC/HEINZEL.CONF on macOS, /etc//
# and /etc/./, and a relative heinzel.conf after cd /etc. A write
# to any file of that name is denied with it. Not closable: a
# glob (/etc/heinzel.c*) or a name built at run time still gets
# through, so the written rule stays the first line of defence.
# Reading it stays allowed.
LOCKFILE='[Hh][Ee][Ii][Nn][Zz][Ee][Ll]\.[Cc][Oo][Nn][Ff]'

# A general-purpose language runtime. See the interpreter section
# at the bottom for why this list, and not a list of the ways
# those runtimes spell a write.
INTERP='(^|[^[:alnum:]_.-])(python[0-9.]*|perl|ruby|node|nodejs|deno|bun|php[0-9.]*|lua[0-9.]*|tclsh|osascript|Rscript|julia|elixir|escript|erl|[gmn]?awk)([^[:alnum:]_.-]|$)'
# The same set without awk, for the account files: the security
# skill reads /etc/passwd and /etc/shadow with awk -F:, and awk
# writes a file only through an explicit > that the redirect
# rules see anyway.
INTERP_NOAWK='(^|[^[:alnum:]_.-])(python[0-9.]*|perl|ruby|node|nodejs|deno|bun|php[0-9.]*|lua[0-9.]*|tclsh|osascript|Rscript|julia|elixir|escript|erl)([^[:alnum:]_.-]|$)'

# True when command $1 occurs somewhere WITHOUT its read-only
# exemption $2 applying to that occurrence. Two conditions make
# an exemption count: it must sit in the same segment as the
# command, and it must FOLLOW it. Otherwise a flag belonging to
# a wrapper disarms the taboo, which is what issue #4 reported:
# ssh -l root host "fdisk /dev/sda" and lsblk -l && fdisk /dev/sdb
# were both waved through because a bare -l existed anywhere.
hit_without() {
  segments | grep -Eq "$1" || return 1
  # The command IS present. From here on the only question is
  # whether the exemption belongs to it, so every failure path
  # below must deny. If this awk cannot evaluate POSIX classes,
  # we cannot prove the exemption applies: block.
  printf 'x' | awk '{ exit(($0 ~ /[[:alnum:]]/) ? 0 : 1) }' \
    2>/dev/null || return 0
  segments | awk -v cmd="$1" -v exempt="$2" '
    {
      line = $0
      while (match(line, cmd)) {
        if (RLENGTH <= 0) break
        # A shell comment is not part of the invocation: without
        # this cut, fdisk /dev/sda # -l counted as a listing.
        # Cutting at a # that sits inside quotes only removes a
        # possible exemption, so it errs towards blocking.
        rest = substr(line, RSTART)
        sub(/[ \t]#.*$/, "", rest)
        if (rest !~ exempt) { bare = 1; exit }
        line = substr(line, RSTART + RLENGTH)
      }
    }
    END { exit(bare ? 0 : 1) }' 2>/dev/null
  GUARD_AWK_STATUS=$?
  # Only a clean "every occurrence is exempt" (exit 1) allows.
  # Any other status is an awk failure, and that must not pass.
  [ "$GUARD_AWK_STATUS" -eq 1 ] && return 1
  return 0
}

deny() {
  # JSON decision on stdout; blocks in all permission modes.
  # Reasons must stay plain ASCII without quotes/backslashes.
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse",'
  printf '"permissionDecision":"deny",'
  printf '"permissionDecisionReason":"heinzel guard: %s ' "$1"
  printf '(CLAUDE.md - Critical Safety Rules). Blocked in all '
  printf 'permission modes. Explain this to the user; do not '
  printf 'rephrase the command to evade the guard."}}\n'
  exit 0
}

# --- File-edit tools (file mode) ------------------------------
# Edit, Write and NotebookEdit write a file with no command line
# at all, so none of the rules below ever sees them: in local
# mode Write could replace /etc/ssh/sshd_config or authorized_keys
# unchallenged. settings.json registers those tools with the
# argument "file", and the guard then judges the TARGET path
# alone. The text being written is data and is not scanned, which
# is what lets a memory file name every protected path
# (rules/server-memory.md).
#
# Same set as the Bash rules: sshd's config, a key file, a raw
# disk device. ~/.ssh/config and known_hosts stay editable, as
# they are for tee and a redirect.
#
# The device pattern is anchored, unlike DEV: unanchored it would
# deny every file under a directory called dev (~/dev/sdk/x.md).
# The quote anchors it in the degraded scan below, where the path
# is still inside its JSON string.
#
# A path has more than one spelling, and the kernel resolves all
# of them before the write: //, /./ and x/../ anywhere in it, and
# on a filesystem that ignores case (macOS) any capitalization.
# So the target is matched without regard to case, and both as
# given and with those three forms folded away. Every path key in
# the input is judged, not the first one found.
#
# Case folding is not ASCII-only, and APFS folds in full: the
# long s and the Kelvin sign open s and k, a sharp s opens ss,
# and the ligatures U+FB00 to U+FB06 open ff, fi, fl, ffi, ffl
# and st (measured on APFS: [ -e ] on an fi ligature finds
# config). The thirteen mapped below are every entry of
# CaseFolding.txt, Unicode 18, that folds onto ASCII letters
# alone, counted with a script and not from memory. The set is
# NOT closed: U+1DF95 joined it late, so a newer Unicode needs a
# recount. Every protected name is plain ASCII, so the target is
# also matched with them spelled out, and with every other
# non-ASCII byte removed, because HFS+ skips zero-width characters
# when it compares names.
#
# A relative target is resolved against the session's cwd, which
# the hook input carries: the bare name sshd_config is the
# protected file in /etc/ssh and an ordinary one anywhere else.
#
# When jq cannot name the target, the whole input is scanned
# instead. That also blocks a note ABOUT a protected path, and it
# must: an unproven target is a protected one. JSON can spell a
# slash or any character as a backslash escape, which only a JSON
# parser undoes, so such an escape is denied there as well, and
# so is a relative target, which cannot be resolved.
#
# Boundary, left open: a symlink to a protected file under another
# name, and any other tool that writes files (an MCP server). The
# set of writers cannot be closed from here.
if [ "${1:-}" = "file" ]; then
  TARGET=""
  if command -v jq >/dev/null 2>&1; then
    TARGET=$(printf '%s' "$INPUT" | jq -r --arg pwd "$PWD" '
      ((.cwd // $pwd) | tostring) as $c
      | .tool_input | (.file_path, .notebook_path)
      | select(. != null) | tostring
      | if startswith("/") then . else $c + "/" + . end' \
      2>/dev/null) || TARGET=""
  fi
  if [ -z "$TARGET" ]; then
    TARGET="$INPUT"
    if printf '%s\n' "$TARGET" | LC_ALL=C grep -Eq \
      '\\(/|u[0-9a-fA-F]{4})|"(file|notebook)_path"[[:space:]]*:[[:space:]]*"[^/]'
    then
      deny "the target of this file edit could not be read: jq is \
missing or failed, and the path is relative or may be hidden \
behind a JSON escape"
    fi
  fi
  # U+FB00..FB06 share the prefix EF AC and differ in the last
  # byte; the three-letter ligatures go first only for clarity.
  LIG=$(printf '\357\254')
  MAPPED=$(printf '%s\n' "$TARGET" | LC_ALL=C sed \
    -e "s/$(printf '\305\277')/s/g" \
    -e "s/$(printf '\342\204\252')/k/g" \
    -e "s/$(printf '\303\237')/ss/g" \
    -e "s/$(printf '\341\272\236')/ss/g" \
    -e "s/$(printf '\360\235\276\225')/ss/g" \
    -e "s/$(printf '\304\260')/i/g" \
    -e "s/$LIG$(printf '\203')/ffi/g" \
    -e "s/$LIG$(printf '\204')/ffl/g" \
    -e "s/$LIG$(printf '\200')/ff/g" \
    -e "s/$LIG$(printf '\201')/fi/g" \
    -e "s/$LIG$(printf '\202')/fl/g" \
    -e "s/$LIG$(printf '\205')/st/g" \
    -e "s/$LIG$(printf '\206')/st/g" 2>/dev/null) || MAPPED=""
  ASCII=$(printf '%s\n' "$MAPPED" \
    | LC_ALL=C tr -d '\200-\377' 2>/dev/null) || ASCII=""
  FOLDED=$(printf '%s\n%s\n' "$MAPPED" "$ASCII" \
    | LC_ALL=C sed -E -e 's#/+#/#g' \
      -e ':a' -e 's#/\./#/#g' -e 'ta' \
      -e ':b' -e 's#/[^/]+/\.\./#/#' -e 'tb' 2>/dev/null) || FOLDED=""
  if [ -z "$MAPPED" ] || [ -z "$ASCII" ] || [ -z "$FOLDED" ]; then
    deny "the target path of this file edit could not be \
normalised, so it cannot be shown to be an ordinary file"
  fi
  FILEDEV="(^|\"|/\\.\\.?)/+${DEV#/}"
  target_hit() {
    printf '%s\n%s\n%s\n%s\n' "$TARGET" "$MAPPED" "$ASCII" "$FOLDED" \
      | LC_ALL=C grep -Eiq "$1"
  }
  if target_hit "$SSHD"; then
    deny "modifying sshd_config or a file merged into it is \
never allowed, with a file-edit tool as little as with a command"
  fi
  if target_hit "$KEYFILE"; then
    deny "writing into an SSH key file replaces the keys there, \
with a file-edit tool as much as with a command"
  fi
  if target_hit "$FILEDEV"; then
    deny "writing onto a raw disk device overwrites its content \
and partition table"
  fi
  if target_hit "$SUDOERS"; then
    deny "writing sudoers, a sudoers.d file or doas.conf grants or revokes \
root rights; sudo work is a Heinzel Pro feature"
  fi
  if target_hit "$ACCOUNTS"; then
    deny "writing an account file directly bypasses every check \
useradd and passwd make; account work is a Heinzel Pro feature"
  fi
  if target_hit "$EFIVARS"; then
    deny "writing a firmware variable can brick the board; boot \
work is a Heinzel Pro feature"
  fi
  if target_hit "$LOCKFILE"; then
    deny "/etc/heinzel.conf is the server lock; only the \
machine's owner changes it, never heinzel"
  fi
  exit 0
fi

# The model must not disarm the guard from inside a command.
# Matches the assignment form only — merely mentioning the
# variable name (docs, grep) is fine. Note: heredocs flow
# through the command string too, so writing the literal
# assignment into a file or commit message also triggers
# this; phrase such text without the equals sign.
if hit 'HEINZEL_GUARD_DISABLE='; then
  deny "the guard has no off switch since Heinzel 3.0; what it \
blocks is Heinzel Pro's work"
fi

# --- Attack tools (rules/ethics.md) ---------------------------
# heinzel is not an attack tool. This denies the password and
# key crackers, the network attack suites and the login brute-
# forcers by name, both run and installed. Like every other
# block here it names a KNOWN set, not the effect -- a renamed
# or hand-built cracker walks past it, and the ethics rule in
# the model layer is the real boundary. This is the mechanical
# backstop against the obvious case, in every permission mode.
#
# Scoped to the program token with a boundary on either side.
# Like the taboo words elsewhere, a cracker name quoted as an
# ARGUMENT is matched too: `apt-cache show hashcat` is denied
# although it only reads. The names are distinctive, so this
# collides with ordinary work far less than `shutdown` does;
# rephrase such a probe (the pkg-search case is rare). `john`
# is the one name that is also a username, so it is matched
# only with its own flags or an .rule/.pot/wordlist operand,
# never bare.
ATTACK='hashcat|hydra|medusa|ncrack|patator|crowbar|thc-hydra'
ATTACK="$ATTACK"'|aircrack-ng|airmon-ng|aireplay-ng|reaver|bully'
ATTACK="$ATTACK"'|ophcrack|rainbowcrack|hashpump'
ATTACK="$ATTACK"'|metasploit|msfconsole|msfvenom|sqlmap'
ATTACK="$ATTACK"'|responder|crackmapexec|netexec|nxc|hashcat-utils'
if hit "(^|[^[:alnum:]_.-])($ATTACK)([^[:alnum:]_.-]|\$)"; then
  deny "this is a password/key cracker or an attack tool; \
heinzel does not recover passwords or attack systems, on any \
host (rules/ethics.md)"
fi
# john the ripper: only when it looks like the tool, not the name
if hit '(^|[^[:alnum:]_.-])john([[:space:]]+-|[[:space:]]+[^ ]*\.(pot|rec|rule|lst|txt|conf)|[[:space:]]+--)'; then
  deny "john the ripper recovers passwords; heinzel does not do \
this on any host (rules/ethics.md)"
fi
# Installing any of them is blocked too, whatever the manager.
if hit '(apt-get|apt|aptitude|dnf|yum|zypper|pkg|brew|snap|pip3?|pipx|cargo|go)[[:space:]]+(-[^ ]+[[:space:]]+)*(install|add|-S|in)([[:space:]]|$)' \
  && hit "(^|[^[:alnum:]_.-])($ATTACK|john|john-the-ripper|johntheripper)([^[:alnum:]_.-]|\$)"; then
  deny "installing a password cracker or attack tool; heinzel \
does not do this on any host (rules/ethics.md)"
fi

# --- Power off ------------------------------------------------
if hit '(^|[^[:alnum:]_-])(halt|poweroff)([^[:alnum:]_-]|$)'; then
  deny "halt/poweroff never runs without explicit user request"
fi
if hit '(^|[^[:alnum:]_.-])(tel)?init[[:space:]]+0([^0-9]|$)'; then
  deny "init 0 powers off the server"
fi
# echo o > /proc/sysrq-trigger cuts the power instantly, and b
# resets without syncing. Nothing reads this file, so any
# mention of it is a write.
if hit 'sysrq-trigger'; then
  deny "sysrq-trigger powers off or resets the server without \
shutting anything down cleanly"
fi
if hit_without '(^|[^[:alnum:]_-])shutdown([^[:alnum:]_-]|$)' \
  '(^|[[:space:]])-(r|c)([[:space:]]|$)'; then
  deny "shutdown without -r powers off the server (reboots \
use shutdown -r; -c cancels)"
fi

# --- Filesystem creation --------------------------------------
if hit '(^|[^[:alnum:]_.-])mkfs(\.[[:alnum:]]+)?([^[:alnum:]_.-]|$)'
then
  deny "mkfs destroys the filesystem on its target"
fi
# newfs_msdos and friends: the suffix must be part of the match,
# otherwise the trailing word boundary rejects the underscore.
if hit '(^|[^[:alnum:]_.-])newfs([._][[:alnum:]]+)*([^[:alnum:]_.-]|$)'
then
  deny "newfs destroys the filesystem on its target"
fi
if hit '(^|[^[:alnum:]_.-])(mke2fs|mkntfs|mkdosfs|mkexfatfs|mkudffs|mkfs2?)([^[:alnum:]_.-]|$)'
then
  deny "this filesystem creator destroys the data on its target"
fi
if hit '(^|[^[:alnum:]_.-])wipefs([^[:alnum:]_.-]|$)' \
  && hit '(^|[[:space:]])(-a|--all|-o|--offset)'; then
  deny "wipefs in write mode erases filesystem signatures"
fi

# --- Partition table writers ----------------------------------
# Read-only inspection stays allowed: fdisk -l, sfdisk -l/-d,
# gdisk -l, sgdisk -p, parted -l/print, gpart show/status/list,
# lsblk, diskutil list.
if hit_without '(^|[^[:alnum:]_.-])fdisk([^[:alnum:]_.-]|$)' \
  '(^|[[:space:]])-l'; then
  deny "fdisk without -l opens the partition table for writing"
fi
# On OpenBSD -l takes a block count (fdisk -iy -l 20000 sd0) and
# lists nothing, so -l followed by a number is no exemption. The
# number must end the word: fdisk -l 2>/dev/null is a listing.
# The number may be quoted or come from a variable, which nobody
# sees before it runs: both count. And the OpenBSD write flags
# (-A -e -g -i -R) exist on no Linux fdisk, so a flag group with
# one of them is a write whatever else the line holds.
FDISK='(^|[^[:alnum:]_.-])fdisk([[:space:]]+[^[:space:];|&]+)*[[:space:]]+["'\''\\$]*-'
#
# So -l is a listing only when a path, another flag or nothing
# follows it. Any other word (a number, bare or wrapped, a
# variable, a backtick, +2048, a disk name without /dev/) may be
# the block count. A number right before > is a redirect
# (2>/dev/null) and stays allowed. And a redirect target that
# starts with a dash (> -l) is a file name, not a flag.
if hit "$FDISK"'[[:alnum:]"'\''\\]*l["'\''\\]*[[:space:]]+["'\''\\[:space:]]*[^-/[:space:];|&<>)"'\''\\0-9]' \
  || hit "$FDISK"'[[:alnum:]"'\''\\]*l["'\''\\]*[[:space:]]*["'\''\\[:space:]]*[0-9]+([^0-9>&]|$)' \
  || hit "$FDISK"'[[:alnum:]"'\''\\]*[AegiR]' \
  || hit '(^|[^[:alnum:]_.-])fdisk([[:space:]]+[^[:space:];|&]+)*[[:space:]]*[<>]+[[:space:]]*["'\''\\]*-'
then
  deny "fdisk -l with a block count is the OpenBSD geometry \
option, not a listing, and -A -e -g -i -R write the table"
fi
# The BSD label editors (OpenBSD and NetBSD disklabel, FreeBSD
# bsdlabel). The label is the partition table there. Their write
# flags differ per system, so the READ set is the closed one: a
# flag group with any letter outside A c d h p r t v counts as a
# write, and that fails closed for -n and -T as well. The flags
# must sit in the same invocation, after the command: no ; | &
# between them, so grep -E behind a pipe does not count. A word
# that starts with a quote, a backslash or a $ could be any
# flag once the shell has unwrapped it, so it counts as a write
# too, and so does a quote in the middle of a flag group.
if hit '(^|[^[:alnum:]_.-])(disklabel|bsdlabel)([[:space:]]+[^[:space:];|&]+)*[[:space:]]+(-[Acdhprtv]*[^Acdhprtv[:space:]]|[^[:alnum:][:space:];|&/._>-])'
then
  deny "disklabel in a write form modifies the partition table \
(disklabel <disk> and disklabel -h <disk> read it)"
fi
# cfdisk has no read-only mode at all: it is the curses editor.
if hit '(^|[^[:alnum:]_.-])cfdisk([^[:alnum:]_.-]|$)'; then
  deny "cfdisk is an interactive partition editor with no \
read-only mode"
fi
if hit_without '(^|[^[:alnum:]_.-])sfdisk([^[:alnum:]_.-]|$)' \
  '(^|[[:space:]])(-l|--list|-d|--dump|-V|--verify)'; then
  deny "sfdisk in write mode modifies the partition table"
fi
if hit_without '(^|[^[:alnum:]_.-])c?gdisk([^[:alnum:]_.-]|$)' \
  '(^|[[:space:]])-l'; then
  deny "gdisk without -l opens the partition table for writing"
fi
# sgdisk and parted both take SEVERAL actions per invocation, so
# "allow when a read-only flag is present" cannot work: the read
# flag rides along with the write one (sgdisk -b backup.gpt -Z
# /dev/sda). Their write sets are closed and documented, so they
# are enumerated in full instead. Short flags below are the
# complete write set from sgdisk(8); the read-only ones (a D E f
# F i L O p P V v) are absent on purpose, and so is -b, which
# writes a backup FILE and not the disk.
if hit '(^|[^[:alnum:]_.-])sgdisk([^[:alnum:]_.-]|$)' \
  && hit '(^|[[:space:]])(-[BcCdegGhIjklmnNorRstTuUzZ]|--(byte-swap-name|change-name|recompute-chs|delete|move-second-header|mbrtogpt|randomize-guids|hybrid|align-end|move-main-table|move-backup-table|load-backup|gpttombr|new|largest-new|clear|transpose|replicate|sort|typecode|transform-bsd|partition-guid|disk-guid|zap|zap-all))'
then
  deny "sgdisk write options modify the partition table"
fi
if hit '(^|[^[:alnum:]_.-])parted([^[:alnum:]_.-]|$)' \
  && hit '((mklabel|mktable|mkpartfs|mkpart|rescue|resize)([[:space:]]|$)|(rm|set|toggle|name|move|resizepart)[[:space:]]+[0-9]|disk_(set|toggle)[[:space:]])'
then
  deny "parted write commands modify the partition table"
fi
# growpart rewrites the partition entry to enlarge it. Its dry
# run is the only read-only form, and the exemption is scoped
# the same way as every other one here.
if hit_without '(^|[^[:alnum:]_.-])growpart([^[:alnum:]_.-]|$)' \
  '(^|[[:space:]])(-N|--dry-run)([[:space:]]|$)'; then
  deny "growpart rewrites the partition table to resize a \
partition"
fi
# FreeBSD and macOS GUID partition table editor. show is the
# read-only verb and stays allowed.
if hit '(^|[^[:alnum:]_.-])gpt[[:space:]]+(create|destroy|add|remove|modify|migrate|recover|resize|restore|boot|label|set|unset)([^[:alnum:]_-]|$)'
then
  deny "gpt write verbs modify the partition table"
fi
# macOS: the tool people actually partition with. Verbs are
# case-insensitive, hence hit_i.
if hit_i '(^|[^[:alnum:]_.-])diskutil([^[:alnum:]_.-]|$)' \
  && hit_i '(erasedisk|erasevolume|eraseoptical|zerodisk|randomdisk|secureerase|partitiondisk|splitpartition|mergepartitions|resizevolume|reformat|deletecontainer|deletevolume|erasecontainer|destroycontainer|resizecontainer|appleraid[[:space:]]+(delete|create))'
then
  deny "diskutil erase and partition verbs destroy data or the \
partition map"
fi
if hit 'gpart[[:space:]]+(create|add|delete|destroy|modify|resize|bootcode|recover|set|undo|commit)'
then
  deny "gpart write verbs modify the partition table"
fi
if hit '(^|[^[:alnum:]_-])dd([^[:alnum:]_-]|$)' \
  && hit 'of=["'\'']?/dev/'; then
  deny "dd onto a raw device overwrites disk content and \
partition table"
fi

# --- Raw-device wipers ----------------------------------------
# These leave the partition table intact and destroy everything
# it points at, which is the same effect by another route.
if hit '(^|[^[:alnum:]_.-])blkdiscard([^[:alnum:]_.-]|$)'; then
  deny "blkdiscard discards every block on the device"
fi
if hit '(^|[^[:alnum:]_.-])nvme[[:space:]]+(format|sanitize|write|delete-ns|create-ns|attach-ns|detach-ns|security-send|copy|dsm|zns)'
then
  deny "this nvme subcommand overwrites or destroys namespace \
data"
fi
if hit '(^|[^[:alnum:]_.-])hdparm([^[:alnum:]_.-]|$)' \
  && hit '(--security-(erase|erase-enhanced|set-pass|unlock|disable)|--trim-sector-ranges|--make-bad-sector|--write-sector|--dco-(restore|setmax)|--repair-sector)'
then
  deny "this hdparm option erases the drive or writes raw \
sectors"
fi
# badblocks -w is the destructive read-write test. -n and -sv
# are non-destructive and stay allowed.
if hit '(^|[^[:alnum:]_.-])badblocks([^[:alnum:]_.-]|$)' \
  && hit '(^|[[:space:]])-[[:alnum:]]*w'; then
  deny "badblocks -w overwrites the device while testing it"
fi
if hit '(^|[^[:alnum:]_.-])shred([^[:alnum:]_.-]|$)' \
  && hit "$DEV"; then
  deny "shred on a disk device overwrites the whole device"
fi

# True when the command writes INTO a path matching $1 (a regex
# without a trailing boundary) through a tool that names its
# target: tee or sponge, dd of=, an output flag (curl -o, wget -O,
# sort -o, openssl -out), or the destination of cp, rsync or scp.
# The same shapes reach a disk device, sshd_config and a key.
#
# A copy is judged by its DESTINATION, the last operand of its
# invocation, because the common legitimate forms name the
# protected path as the source: scp -i ~/.ssh/id_ed25519, a backup
# of authorized_keys, cp /dev/sda disk.img. Trailing options,
# redirects, a closing parenthesis or backtick and a comment are
# skipped while looking for that operand; cp -t names it up front.
# An = right before an output path is excluded on purpose:
# ssh -o IdentityFile=~/.ssh/id_ed25519 only reads the key.
#
# The set of writers cannot be closed (an archive unpacked into
# place, a git checkout, any tool with an output flag of its own),
# so this stays a backstop, not a sandbox.
#
# END includes < and >: a redirect glued to the path
# (tee /etc/ssh/sshd_config<<EOF) still ends it.
END="([\"'[:space:];|&)\`<>]|\$)"
ENDARG="[\"']?([[:space:]]+(-[^[:space:]]*|[0-9]*[<>]+&?([[:space:]]*[^[:space:]]+)?))*[[:space:])\`]*(#.*)?\$"
writes_to() {
  hit "(^|[^[:alnum:]_.-])(tee|sponge)[[:space:]]([^;|&<>]*[[:space:]])?[^[:space:];|&]*$1$END" \
    || hit "(^|[[:space:]])of=[^[:space:]]*$1$END" \
    || hit "(^|[[:space:]])(-[oO]|-out|--output(-document)?)([[:space:]]+|=)?[^[:space:]=]*$1$END" \
    || hit "(^|[^[:alnum:]_.-])(cp|rsync|scp)[[:space:]]([^;&|]*[[:space:]])?[^[:space:]]*$1$ENDARG" \
    || hit "(^|[^[:alnum:]_.-])cp[[:space:]]([^;&|]*[[:space:]])?(-[[:alpha:]]*t[[:space:]]*|--target-directory[=[:space:]])[^[:space:]]*$1$END"
}

# A redirect, tee, cp or download onto a disk device does what
# dd of= does. /dev/null, /dev/stderr and /dev/disk/by-id are
# unaffected.
if hit ">[[:space:]]*[\"']?$DEV" \
  || { hit "$DEV" && writes_to "${DEV}[[:alnum:]]*"; }
then
  deny "writing onto a raw disk device overwrites its content \
and partition table"
fi

# --- SSH keys and sshd_config ---------------------------------
# Deleting is only one way to lose a key. Renaming it away,
# truncating it to zero, or making it unreadable to sshd have
# the same effect, and the sshd_config rule below already
# reflected that while this one did not.
# KEY is checked once and first: most commands name no key, and
# every key rule below needs one.
# CLOBBER: tools that delete, move, re-permission or rewrite a
# file named on their command line. Both rules below use it; the
# sshd_config rule adds cp, since a copy onto it replaces it.
CLOBBER='rm|shred|unlink|truncate|mv|chmod|chown|install|ln|setfacl|patch'
HAS_KEY=0
hit "$KEY" && HAS_KEY=1
if [ "$HAS_KEY" -eq 1 ] \
  && { hit "(^|[^[:alnum:]_-])($CLOBBER)([^[:alnum:]_-]|\$)" \
       || hit '(^|[[:space:]])(-delete|--remove-s(ource|ent)-files)([[:space:]]|$)'; }
then
  deny "deleting, moving or re-permissioning SSH keys is never \
allowed"
fi
# A truncating redirect needs no command at all: : > key.
if hit ">[[:space:]]*[\"']?[^[:space:];|&]*$KEYPRIV"; then
  deny "redirecting onto an SSH key file truncates it"
fi
# ssh-keygen -f onto an existing private key overwrites it.
# Reading a .pub (for a fingerprint) stays allowed.
if hit '(^|[^[:alnum:]_-])ssh-keygen([^[:alnum:]_-]|$)' \
  && hit "$KEYPRIV"; then
  deny "ssh-keygen pointed at an existing key overwrites it - a \
fingerprint of a .pub runs in a call of its own, with no private \
key path in it"
fi
if hit "$SSHD"; then
  if hit '>>?[[:space:]]*["'\'']?[^[:space:];|&]*'"$SSHD" \
    || { hit '(^|[^[:alnum:]_-])(sed|perl)([^[:alnum:]_-]|$)' \
         && hit '(^|[[:space:]])-i'; } \
    || hit "(^|[^[:alnum:]_-])$EDITOR([^[:alnum:]_-]|\$)" \
    || hit "(^|[^[:alnum:]_-])($CLOBBER|cp)([^[:alnum:]_-]|\$)" \
    || writes_to "$SSHD"
  then
    deny "modifying sshd_config or a file merged into it is \
never allowed (reading it is fine: cat, grep, sshd -T)"
  fi
fi

# --- Writes INTO an SSH key -----------------------------------
# Writing into a key file replaces it as surely as deleting it.
if [ "$HAS_KEY" -eq 1 ]; then
  if writes_to "($KEYFILE|$KEYDIR/?)"; then
    deny "writing into an SSH key file or a key directory \
replaces the keys there"
  fi
  # An in-place edit needs the key AFTER the tool in the same
  # invocation: in ssh -i ~/.ssh/id_ed25519 host "sed -i ..." the
  # key belongs to ssh, and the edit runs elsewhere.
  if hit "(^|[^[:alnum:]_.-])sed[[:space:]]([^;&|]*[[:space:]])?(-[[:alpha:]]*i|--in-place)[^;&|]*$KEYPRIV" \
    || hit "(^|[^[:alnum:]_-])${EDITOR}[[:space:]][^;&|]*$KEYPRIV"
  then
    deny "editing an SSH key file in place can delete keys from it"
  fi
fi

# --- Boot loaders and firmware variables (Heinzel Pro) --------
# A boot entry, the boot order or the loader itself is the way
# back into a host that has no console. heinzel reads them
# (efibootmgr -v, bootctl status, bless --info) and never writes
# them since 3.0: that is Heinzel Pro's work (CLAUDE.md -> What
# Heinzel does not do). Writers, by effect: efibootmgr in any
# form that creates, deletes, reorders, activates or times an
# entry (the read forms are bare, -v and -V); grub-install and
# update-grub, which rewrite the loader or its config, and
# grub-mkconfig only with -o (without it, it prints); the
# bootctl verbs that install, update, remove or set; bless in
# any form but --info and --getBoot; efivar -w; and a write,
# delete or re-permission under the efivars mount, where a
# removed variable has bricked boards.
if hit '(^|[^[:alnum:]_.-])efibootmgr([^[:alnum:]_.-]|$)' \
  && hit '(^|[[:space:]])(-[bBcCaAoOnNtTDwy@]|--(bootnum|delete-bootnum|create|create-only|active|inactive|bootorder|delete-bootorder|bootnext|delete-bootnext|timeout|delete-timeout|remove-dups|write-signature|sysprep|delete|append-binary-args|label|loader|disk|part))([[:space:]]|=|$)'
then
  deny "efibootmgr in a write form changes the boot entries or \
the boot order (efibootmgr -v reads them); boot work is a \
Heinzel Pro feature"
fi
if hit_without '(^|[^[:alnum:]_.-])grub2?-install([^[:alnum:]_.-]|$)' \
  '(^|[[:space:]])(-V|--version|--help)([[:space:]]|$)'; then
  deny "grub-install rewrites the boot loader; boot work is a \
Heinzel Pro feature"
fi
if hit '(^|[^[:alnum:]_.-])update-grub2?([^[:alnum:]_.-]|$)' \
  || { hit '(^|[^[:alnum:]_.-])grub2?-mkconfig([^[:alnum:]_.-]|$)' \
       && hit '(^|[[:space:]])(-o|--output)([[:space:]]|=)'; }
then
  deny "update-grub and grub-mkconfig -o rewrite the boot loader \
config (grub-mkconfig without -o only prints it); boot work is \
a Heinzel Pro feature"
fi
if hit '(^|[^[:alnum:]_.-])bootctl([^[:alnum:]_.-]|$)' \
  && hit '(^|[[:space:]])(install|update|remove|cleanup|unlink|set-default|set-oneshot|set-timeout|set-timeout-oneshot|random-seed|reboot-to-firmware)([[:space:]]|$)'
then
  deny "this bootctl verb installs, removes or reconfigures the \
boot loader (bootctl status and list read it); boot work is a \
Heinzel Pro feature"
fi
if hit_without '(^|[^[:alnum:]_.-])bless([^[:alnum:]_.-]|$)' \
  '(^|[[:space:]])(--info|--getBoot|--version|--help)([[:space:]]|$)'; then
  deny "bless in a write form changes what the Mac boots \
(bless --info and --getBoot read it); boot work is a Heinzel \
Pro feature"
fi
# OpenBSD and NetBSD write their boot blocks with installboot;
# -n is the dry run on both. It counts only in the option list
# right behind the command, so a -n further down the line (an
# argument, another word) exempts nothing. Only the flags
# without an argument (c n p v) may stand before or beside it:
# -r takes one, so in -r -n the -n is the root directory.
if hit_without '(^|[^[:alnum:]_.-])installboot([^[:alnum:]_.-]|$)' \
  '^[^[:alnum:]]?installboot([[:space:]]+-[cnpv]+)*[[:space:]]+-[cpv]*n[cnpv]*([[:space:]"'\'']|$)'; then
  deny "installboot rewrites the boot blocks (installboot -n is \
the dry run); boot work is a Heinzel Pro feature"
fi
if hit '(^|[^[:alnum:]_.-])efivar([^[:alnum:]_.-]|$)' \
  && hit '(^|[[:space:]])(-w|--write|-a|--append)([[:space:]]|$)'; then
  deny "efivar -w writes a firmware variable; boot work is a \
Heinzel Pro feature"
fi
if hit "$EFIVARS"; then
  if hit ">>?[[:space:]]*[\"']?[^[:space:];|&]*$EFIVARS" \
    || hit "(^|[^[:alnum:]_-])($CLOBBER|cp|dd|chattr)([^[:alnum:]_-]|\$)" \
    || hit '(^|[[:space:]])-delete([[:space:]]|$)' \
    || writes_to "$EFIVARS"
  then
    deny "writing to or deleting under the efivars mount changes \
firmware variables and can brick the board (cat and ls read \
them); boot work is a Heinzel Pro feature"
  fi
fi

# --- Accounts and sudo (Heinzel Pro) --------------------------
# Creating or widening access is Heinzel Pro's work since 3.0;
# heinzel reads and reports it (CLAUDE.md -> What Heinzel does
# not do). The hook backs only the part that locks someone out
# or cannot be undone: deleting an account or a group, and any
# write to sudoers or to the account files themselves, where one
# bad line is "sudo: parse error" for everybody. Creating an
# account (useradd, pw useradd) and resetting a password stay
# with the prompt: nothing breaks, and a reset is heinzel's own
# everyday work (rules/ethics.md).
if hit '(^|[^[:alnum:]_.-])(userdel|deluser|luserdel|rmuser|groupdel|delgroup|lgroupdel)([^[:alnum:]_.-]|$)' \
  || hit '(^|[^[:alnum:]_.-])(user|group)[[:space:]]+del([^[:alnum:]_-]|$)' \
  || hit '(^|[^[:alnum:]_.-])pw[[:space:]]+(userdel|groupdel|user[[:space:]]+del|group[[:space:]]+del)([^[:alnum:]_-]|$)' \
  || hit '(^|[^[:alnum:]_.-])sysadminctl[[:space:]].*-deleteUser([^[:alnum:]_-]|$)' \
  || hit '(^|[^[:alnum:]_.-])dscl[[:space:]].*-delete[[:space:]]+/(Users|Groups)/'
then
  deny "deleting an account or a group locks people out and \
cannot be undone; account work is a Heinzel Pro feature"
fi
# visudo edits sudoers; visudo -c only checks a file.
if hit_without '(^|[^[:alnum:]_.-])visudo([^[:alnum:]_.-]|$)' \
  '(^|[[:space:]])-c([[:space:]]|$)'; then
  deny "visudo edits sudoers, and one bad line locks everybody \
out of sudo (visudo -c only checks); sudo work is a Heinzel Pro \
feature"
fi
if hit '(^|[^[:alnum:]_.-])(vipw|vigr)([^[:alnum:]_.-]|$)'; then
  deny "vipw and vigr edit the account files in place; account \
work is a Heinzel Pro feature"
fi
if hit "$SUDOERS"; then
  if hit '>>?[[:space:]]*["'\'']?[^[:space:];|&]*'"$SUDOERS" \
    || { hit '(^|[^[:alnum:]_-])(sed|perl)([^[:alnum:]_-]|$)' \
         && hit '(^|[[:space:]])-i'; } \
    || hit "(^|[^[:alnum:]_-])$EDITOR([^[:alnum:]_-]|\$)" \
    || hit "(^|[^[:alnum:]_-])($CLOBBER|cp)([^[:alnum:]_-]|\$)" \
    || writes_to "$SUDOERS"
  then
    deny "writing sudoers, a sudoers.d file or doas.conf grants or revokes \
root rights (cat and visudo -c read it); sudo work is a Heinzel \
Pro feature"
  fi
fi
if hit "$ACCOUNTS"; then
  if hit '>>?[[:space:]]*["'\'']?[^[:space:];|&]*'"$ACCOUNTS" \
    || { hit '(^|[^[:alnum:]_-])(sed|perl)([^[:alnum:]_-]|$)' \
         && hit '(^|[[:space:]])-i'; } \
    || hit "(^|[^[:alnum:]_-])$EDITOR([^[:alnum:]_-]|\$)" \
    || hit "(^|[^[:alnum:]_-])($CLOBBER|cp)([^[:alnum:]_-]|\$)" \
    || writes_to "$ACCOUNTS"
  then
    deny "writing an account file directly bypasses every check \
useradd and passwd make (getent, grep and awk read them); \
account work is a Heinzel Pro feature"
  fi
fi

# --- The server lock ------------------------------------------
# Same write set as sudoers above (a redirect, sed -i, an editor,
# a delete, move or re-permission, a copy or tee onto it), plus
# find -delete, which deletes by a name it never spells as a path. Moving
# or deleting it lifts the lock as surely as writing true.
if hit "$LOCKFILE"; then
  if hit '>>?[[:space:]]*["'\'']?[^[:space:];|&]*'"$LOCKFILE" \
    || { hit '(^|[^[:alnum:]_-])(sed|perl)([^[:alnum:]_-]|$)' \
         && hit '(^|[[:space:]])-i'; } \
    || hit "(^|[^[:alnum:]_-])$EDITOR([^[:alnum:]_-]|\$)" \
    || hit "(^|[^[:alnum:]_-])($CLOBBER|cp)([^[:alnum:]_-]|\$)" \
    || hit '(^|[[:space:]])-delete([[:space:]]|$)' \
    || writes_to "$LOCKFILE"
  then
    deny "/etc/heinzel.conf is the server lock; only the \
machine's owner changes it, never heinzel (cat and grep read it)"
  fi
fi

# --- Effects reached through an interpreter -------------------
# Every rule above recognizes a write by the way it is spelled: a
# redirect, tee, sed -i, an editor, rm/mv/chmod/truncate. A
# language runtime spells none of those and reaches the same
# effects through plain file I/O:
#
#   python3 -c "open('/etc/ssh/sshd_config','a').write(...)"
#   node -e "require('fs').unlinkSync('...authorized_keys')"
#   python3 -c "open('/dev/sda','wb').write(...)"
#
# Its command line is opaque to a pattern matcher -- read and
# write look alike from outside -- so the read-only exemption
# cannot be proven, and an unprovable exemption must not apply.
# A runtime carrying a protected path or a raw device is
# therefore a write. Issue #6.
#
# This enumerates RUNTIMES, not write syntaxes, on purpose. The
# set of ways to write a file grows with every language feature
# and can never be closed; the set of interpreters heinzel might
# meet on a server is small and moves slowly. It still is a list,
# so this rule is a backstop against the everyday mistake, not a
# sandbox: an interpreter that builds its target string at
# runtime, or downloads it, defeats any string matcher. Real
# isolation is the operator's job, not this hook's.
#
# Interpreters that shell out (os.system, %x, child_process) need
# no rule of their own: every check above scans the whole command
# string, so the taboo word inside is caught where it stands.
#
# Accepted false positive: any command that merely mentions an
# interpreter alongside one of these targets is blocked too, even
# when it only reads -- awk '/^Port/' /etc/ssh/sshd_config, or a
# cat of the file chained to an unrelated python call. Read with
# cat, grep, jq, stat or sshd -T instead, which is what the rule
# files use anyway.
if hit "$INTERP"; then
  if hit "$KEY"; then
    deny "an interpreter with an SSH key path on its command \
line can overwrite or delete the key, and a pattern matcher \
cannot tell that from a read - read keys with cat, stat or \
ssh-keygen -lf instead"
  fi
  if hit "$SSHD"; then
    deny "an interpreter with sshd_config on its command line \
can rewrite it, and a pattern matcher cannot tell that from a \
read - read it with cat, grep or sshd -T instead"
  fi
  if hit "$DEV"; then
    deny "an interpreter with a raw disk device on its command \
line can overwrite the device, which destroys everything the \
partition table points at"
  fi
  if hit "$SUDOERS"; then
    deny "an interpreter with sudoers on its command line can \
rewrite it, and a pattern matcher cannot tell that from a read \
- read it with cat or visudo -c instead"
  fi
  if hit "$EFIVARS"; then
    deny "an interpreter with the efivars mount on its command \
line can write a firmware variable - read them with cat or ls \
instead"
  fi
  if hit "$LOCKFILE"; then
    deny "an interpreter with /etc/heinzel.conf on its command \
line can lift the server lock - read it with cat or grep instead"
  fi
fi
if hit "$INTERP_NOAWK" && hit "$ACCOUNTS"; then
  deny "an interpreter with an account file on its command line \
can rewrite it, and a pattern matcher cannot tell that from a \
read - read it with getent, grep or awk instead"
fi

# --- A redirect onto a computed target (issue #51) ------------
# In unquoted echo text, -> is a dash plus a redirect, and the
# next word names the file it truncates: -> $(readlink -f $E)
# replaced /usr/bin/nvim with prose. Denied: any redirect onto a
# $( ) lookup, and an arrow onto any expansion. A plain > "$VAR"
# stays allowed, scripts write that way. Accepted false positive:
# the same text in quotes, which one ssh or bash -c level further
# in are gone; the guard cannot count quote depth.
# Most commands hold no $ after a >, so case skips the forks.
case "$CMD" in
  *'>'*'$'*)
    if printf '%s\n' "$CMD" \
      | grep -Eq '(>[|]?[[:space:]]*["'\'']?\\?\$\(|->[[:space:]]*["'\'']?\\?\$)'
    then
      deny "a redirect onto a computed target overwrites whatever \
file it names - an arrow in echo text is a redirect too, so \
checks print data, not prose"
    fi
    ;;
esac

# No taboo matched: no decision, normal permission flow applies.
exit 0
