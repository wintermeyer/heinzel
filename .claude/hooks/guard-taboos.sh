#!/bin/sh
# guard-taboos.sh — PreToolUse hook (matcher: Bash).
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
#     secure-erase, badblocks -w, shred, dd/redirect/tee
#     onto a disk device)
#   - destroying SSH keys (host keys, authorized_keys,
#     id_*) by any means: rm/shred/truncate/mv/chmod/
#     chown, a truncating redirect, or ssh-keygen -f
#   - writes to /etc/ssh/sshd_config(.d/)
#   - any of the last three reached through a language
#     runtime (python/perl/ruby/node/awk ...), whose file
#     I/O looks nothing like a shell write
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
# was not a write to any of them.
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
# more often now. The way out is the documented one: rephrase,
# or write such text to a file with a non-Bash tool.
#
# Known, accepted false positives (the patterns are deliberately
# coarse — this guard protects production disks, not grep
# pipelines): e.g. `grep poweroff /var/log/syslog` or
# `systemctl status shutdown.target` are blocked. Rephrase the
# probe (`grep 'power[o]ff'`) instead of fighting the guard.
# `cp /etc/ssh/sshd_config /tmp/` is blocked although it only
# reads the file — copy out via `cat /etc/ssh/sshd_config >
# /tmp/copy` instead.
#
# Being blocked is EXPECTED behavior. Explain it to the user.
# Never rephrase, re-quote, or otherwise obfuscate a command to
# evade this guard.
#
# Heinzel-repo development note: commit messages passed as
# heredocs flow through the Bash command string, so writing
# ABOUT taboo commands in a message triggers the guard. Write
# the message to a file with a non-Bash tool and use
# `git commit -F <file>` — that executes nothing on any server.
#
# Override for legitimate flows (e.g. rules/os-replacement.md
# runs mkfs/sgdisk by design): the OPERATOR sets
# HEINZEL_GUARD_DISABLE=1 in the environment BEFORE launching
# the session. An inline assignment inside a proposed command
# does not count and is itself blocked, so the model cannot
# disarm the guard.

# Operator-level override: inherited environment only.
if [ "${HEINZEL_GUARD_DISABLE:-}" = "1" ]; then
  exit 0
fi

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
DEV='/dev/(sd|vd|xvd|hd|nvme|mmcblk|nbd|loop|da|ada|nda|r?disk[0-9])'

# Any SSH key file. KEYPRIV additionally excludes a trailing
# .pub, so reading or copying a public key stays allowed while
# the private half does not.
KEY='(/etc/ssh/ssh_host_|authorized_keys|\.ssh/id_)'
KEYPRIV='(/etc/ssh/ssh_host_[[:alnum:]_-]*key|\.ssh/id_[[:alnum:]_-]+|authorized_keys)([^.[:alnum:]]|$)'

# A general-purpose language runtime. See the interpreter section
# at the bottom for why this list, and not a list of the ways
# those runtimes spell a write.
INTERP='(^|[^[:alnum:]_.-])(python[0-9.]*|perl|ruby|node|nodejs|deno|bun|php[0-9.]*|lua[0-9.]*|tclsh|osascript|Rscript|julia|elixir|escript|erl|[gmn]?awk)([^[:alnum:]_.-]|$)'

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
        if (substr(line, RSTART) !~ exempt) { bare = 1; exit }
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

# The model must not disarm the guard from inside a command.
# Matches the assignment form only — merely mentioning the
# variable name (docs, grep) is fine. Note: heredocs flow
# through the command string too, so writing the literal
# assignment into a file or commit message also triggers
# this; phrase such text without the equals sign.
if hit 'HEINZEL_GUARD_DISABLE='; then
  deny "inline HEINZEL_GUARD_DISABLE assignment is not \
allowed - the operator must export it before launching the \
session"
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
# A redirect or tee onto a disk device does what dd of= does.
# /dev/null, /dev/stderr and /dev/disk/by-id are unaffected.
if hit ">[[:space:]]*[\"']?$DEV" \
  || hit "(^|[^[:alnum:]_.-])tee([[:space:]]+-a)?[[:space:]]+[\"']?$DEV"
then
  deny "redirecting onto a raw disk device overwrites its \
content and partition table"
fi

# --- SSH keys and sshd_config ---------------------------------
# Deleting is only one way to lose a key. Renaming it away,
# truncating it to zero, or making it unreadable to sshd have
# the same effect, and the sshd_config rule below already
# reflected that while this one did not.
if hit '(^|[^[:alnum:]_-])(rm|shred|unlink|truncate|mv|chmod|chown|install|ln)([^[:alnum:]_-]|$)' \
  && hit "$KEY"; then
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
  deny "ssh-keygen pointed at an existing key overwrites it"
fi
if hit '/etc/ssh/sshd_config'; then
  if hit '>>?[[:space:]]*["'\'']?/etc/ssh/sshd_config' \
    || hit 'tee[[:space:]]+(-a[[:space:]]+)?["'\'']?/etc/ssh/sshd_config' \
    || { hit '(^|[^[:alnum:]_-])(sed|perl)([^[:alnum:]_-]|$)' \
         && hit '(^|[[:space:]])-i'; } \
    || hit '(^|[^[:alnum:]_-])(vi|vim|nvim|nano|emacs|ed)([^[:alnum:]_-]|$)' \
    || hit '(^|[^[:alnum:]_-])(rm|truncate|chmod|chown|mv|cp)([^[:alnum:]_-]|$)'
  then
    deny "modifying /etc/ssh/sshd_config is never allowed \
(reading it is fine: cat, grep, sshd -T)"
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
  if hit '/etc/ssh/sshd_config'; then
    deny "an interpreter with sshd_config on its command line \
can rewrite it, and a pattern matcher cannot tell that from a \
read - read it with cat, grep or sshd -T instead"
  fi
  if hit "$DEV"; then
    deny "an interpreter with a raw disk device on its command \
line can overwrite the device, which destroys everything the \
partition table points at"
  fi
fi

# No taboo matched: no decision, normal permission flow applies.
exit 0
