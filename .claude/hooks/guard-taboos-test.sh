#!/bin/sh
# guard-taboos-test.sh — dev-only fixture matrix for
# guard-taboos.sh. Run manually before committing guard
# changes:  sh .claude/hooks/guard-taboos-test.sh
# Not invoked by Claude Code at runtime.

CLAUDE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$CLAUDE_DIR/hooks/guard-taboos.sh"
PASS=0
FAIL=0

json_for() {
  # Wrap a raw command string as PreToolUse hook input.
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$1" \
      | jq -Rs '{tool_name:"Bash",tool_input:{command:.}}'
  else
    printf '%s' "$1" | python3 -c 'import json,sys; \
print(json.dumps({"tool_name":"Bash","tool_input":\
{"command":sys.stdin.read()}}))'
  fi
}

check() {
  EXPECT=$1
  CMDSTR=$2
  OUT=$(json_for "$CMDSTR" \
    | env -u HEINZEL_GUARD_DISABLE sh "$HOOK")
  if printf '%s' "$OUT" \
    | grep -q '"permissionDecision":"deny"'; then
    GOT=deny
  else
    GOT=pass
  fi
  if [ "$GOT" = "$EXPECT" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL [$EXPECT, got $GOT]: $CMDSTR"
  fi
}

# --- must block ------------------------------------------------
check deny 'halt'
check deny 'poweroff'
check deny 'systemctl poweroff'
check deny 'init 0'
check deny 'shutdown now'
check deny 'shutdown -h now'
check deny 'ssh root@h "shutdown -h now"'
check deny 'ssh -o BatchMode=yes root@h '\''mkfs.ext4 /dev/sda3'\'''
check deny 'mkfs.ext4 /dev/sda1'
check deny 'newfs /dev/ada0p3'
check deny 'wipefs -a /dev/sdb'
check deny 'fdisk /dev/sda'
check deny 'sfdisk /dev/sda < layout.txt'
check deny 'sgdisk -n 2:0:0 /dev/sda'
check deny 'sgdisk --zap-all /dev/sda'
check deny 'parted /dev/sda mklabel gpt'
check deny 'parted /dev/sda rm 2'
check deny 'gpart destroy -F ada0'
check deny 'gpart add -t freebsd-zfs ada0'
check deny 'dd if=image.raw of=/dev/sda bs=4M'
check deny 'ssh h "dd if=img of=/dev/vtbd0"'
check deny 'rm /etc/ssh/ssh_host_ed25519_key'
check deny 'rm -f ~/.ssh/id_ed25519'
check deny 'shred -u /root/.ssh/authorized_keys'
check deny "sed -i 's/^/#/' /etc/ssh/sshd_config"
check deny 'ssh h "echo PermitRootLogin yes >> /etc/ssh/sshd_config"'
check deny 'tee /etc/ssh/sshd_config < new.conf'
check deny 'vi /etc/ssh/sshd_config'
check deny 'HEINZEL_GUARD_DISABLE=1 mkfs.ext4 /dev/sda1'
check deny 'export HEINZEL_GUARD_DISABLE=1; fdisk /dev/sda'

# --- exemption must belong to the taboo invocation (issue #4) ---
# A -l / -r / -c anywhere in the string used to disarm the rule,
# so an ordinary read-only probe in front of a write command
# waved the write command through.
check deny 'ssh -l root host "fdisk /dev/sda"'
check deny 'ssh -l root host "gdisk /dev/sda"'
check deny 'ssh -c aes256-gcm@openssh.com root@host "shutdown -h now"'
check deny 'ls -l /dev && fdisk /dev/sda'
check deny 'grep -r ERROR /var/log/syslog; shutdown -h now'
check deny 'fdisk /dev/sda && ls -l /tmp'
check deny 'cp -l a b; sfdisk --delete /dev/sda'
check deny 'ssh -o BatchMode=yes root@h "lsblk -l && fdisk /dev/sdb"'
check deny 'ssh -o BatchMode=yes root@h "ls -l /dev/disk/by-id; fdisk /dev/sdb"'
check deny 'ssh -o BatchMode=yes root@h "gdisk -l /dev/sda; gdisk /dev/sdb"'
check deny 'ssh -o BatchMode=yes root@h "sfdisk -l /dev/sda && sfdisk /dev/sdb < pt"'
# No quote or separator to split on: the exemption is only
# recognized when it FOLLOWS the taboo command in its segment.
check deny 'ssh -l root host fdisk /dev/sda'
check deny 'ssh -luser host fdisk /dev/sda'
check deny 'ssh -c aes256-gcm@openssh.com root@host shutdown -h now'
check deny 'sudo -l root fdisk /dev/sda'

# --- same taboo, tool the rules did not name (issue #5) --------
# The taboos are effects, not a list of binaries. Every command
# below reaches a forbidden effect through a tool the original
# rules never mentioned.
check deny 'cfdisk /dev/sda'
check deny 'gpt destroy /dev/da0'
check deny 'gpt create -f /dev/disk2'
check deny 'diskutil eraseDisk JHFS+ Foo disk2'
check deny 'diskutil partitionDisk disk2 GPT JHFS+ Foo 100%'
check deny 'diskutil apfs deleteContainer disk2'
check deny 'diskutil secureErase 0 disk2'
check deny 'diskutil zeroDisk disk2'
# parted and sgdisk take several actions per invocation, so a
# read-only flag can always ride along with a write one. Their
# write sets are closed and enumerated in full instead.
check deny 'parted /dev/sda toggle 1 boot'
check deny 'parted /dev/sda name 1 data'
check deny 'parted /dev/sda move 1 100 200'
check deny 'parted /dev/sda mkpartfs primary ext2 1 100'
check deny 'sgdisk -U R /dev/sda'
check deny 'sgdisk -e /dev/sda'
check deny 'sgdisk -s /dev/sda'
check deny 'sgdisk -G /dev/sda'
check deny 'sgdisk --replicate=/dev/sdb /dev/sda'
check deny 'sgdisk -b backup.gpt -Z /dev/sda'
check deny 'growpart /dev/sda 1'

# --- disk wiped without touching the partition table -----------
check deny 'blkdiscard /dev/sda'
check deny 'blkdiscard --secure /dev/nvme0n1'
check deny 'nvme format /dev/nvme0n1'
check deny 'nvme sanitize /dev/nvme0n1'
check deny 'nvme delete-ns /dev/nvme0'
check deny 'nvme write-zeroes /dev/nvme0n1'
check deny 'hdparm --security-erase p /dev/sda'
check deny 'hdparm --make-bad-sector 1024 /dev/sda'
check deny 'badblocks -w /dev/sda'
check deny 'badblocks -sw /dev/sdb'
check deny 'shred /dev/sda'
check deny 'mke2fs -t ext4 /dev/sda1'
check deny 'newfs_msdos /dev/da0s1'
check deny 'cat disk.img > /dev/sda'
check deny 'tee /dev/sda < disk.img'
check deny 'dd if=disk.img > /dev/nvme0n1'
check deny 'ssh root@h "xzcat img.xz > /dev/vda"'

# --- power off under another name ------------------------------
check deny 'telinit 0'
check deny 'echo o > /proc/sysrq-trigger'

# --- SSH keys destroyed without rm/shred/unlink ----------------
check deny 'echo "" > /root/.ssh/authorized_keys'
check deny ': > /etc/ssh/ssh_host_ed25519_key'
check deny 'truncate -s 0 /root/.ssh/authorized_keys'
check deny 'mv /root/.ssh/authorized_keys /tmp/'
check deny 'chmod 000 /root/.ssh/authorized_keys'
check deny 'chown nobody /etc/ssh/ssh_host_rsa_key'
check deny 'ssh-keygen -q -N "" -f /etc/ssh/ssh_host_rsa_key'

# --- writes INTO a protected path (writes_to) ------------------
# A copy is judged by its destination: a key, ~/.ssh or a disk as
# the SOURCE is a read.
check deny 'echo x | tee /root/.ssh/authorized_keys'
check deny 'tee -a /home/alice/.ssh/authorized_keys < new.pub'
check deny 'cp /tmp/new /root/.ssh/authorized_keys'
check deny 'cp /tmp/new /root/.ssh/authorized_keys 2>/dev/null'
check deny 'cp /tmp/new /root/.ssh/authorized_keys 2>&1 | tee cp.log'
check deny 'cp -v /tmp/new "/root/.ssh/authorized_keys"'
check deny 'tee /tmp/copy /root/.ssh/authorized_keys < new.pub'
check deny 'rsync -e "ssh -i ~/.ssh/id_ed25519" keys h:/root/.ssh/authorized_keys'
check deny 'cp -f /tmp/id_ed25519 /root/.ssh/'
check deny 'cp -t /root/.ssh authorized_keys'
check deny 'rsync -a /backup/ssh/ /root/.ssh/'
check deny 'rsync --delete /tmp/empty/ /root/.ssh'
check deny 'scp keys root@h:/root/.ssh/authorized_keys'
check deny 'ssh root@h "cp /tmp/new /root/.ssh/authorized_keys && echo ok"'
check deny 'dd if=/dev/zero of=/etc/ssh/ssh_host_ed25519_key count=1'
check deny 'curl -fsS https://example.com/u.keys -o /root/.ssh/authorized_keys'
check deny 'wget -O ~/.ssh/authorized_keys https://example.com/u.keys'
check deny "sed -i '/old/d' /root/.ssh/authorized_keys"
check deny "sed -ni '1p' /root/.ssh/authorized_keys"
check deny 'vi /root/.ssh/authorized_keys'
check deny 'sort -u keys | sponge /root/.ssh/authorized_keys'
check deny 'setfacl -m u:bob:rw /root/.ssh/authorized_keys'
check deny 'find /home/alice/.ssh -name "id_*" -delete'
check deny '(cp /tmp/new /root/.ssh/authorized_keys)'
check deny 'echo $(cp /tmp/new /root/.ssh/authorized_keys)'
check deny 'cp /tmp/new /root/.ssh/authorized_keys # new key'
check deny 'cp -rt ~/.ssh keys'
check deny 'rsync --remove-source-files ~/.ssh/id_ed25519 /backup/'
check deny 'cp image.iso /dev/sdb'
check deny 'curl -fsS -o /dev/sdb https://example.com/img'
check deny 'tee /tmp/copy /dev/sdb < img'
check deny 'dd if=new.conf of=/etc/ssh/sshd_config'
check deny 'sort -u new.conf | sponge /etc/ssh/sshd_config'
check deny 'curl -o /etc/ssh/sshd_config.d/10-x.conf https://example.com/c'
check deny 'rsync new.conf h:/etc/ssh/sshd_config'
# Accepted false positive; see the list in the guard header.
check deny 'rsync -a site/ h:/var/www/ -e "ssh -i ~/.ssh/id_ed25519"'
check pass 'cp /root/.ssh/authorized_keys /root/backup/'
check pass 'cp /root/.ssh/id_ed25519 /root/.ssh/id_ed25519.bak'
check pass 'cp /tmp/new /tmp/x; cat /root/.ssh/authorized_keys'
check pass 'ssh -o BatchMode=yes root@h "cat /root/.ssh/authorized_keys"'
check pass 'cp /tmp/config /home/alice/.ssh/config'
check pass 'cp -a /root/.ssh /backup/root-ssh'
check pass 'scp -i ~/.ssh/id_ed25519 report.txt root@h:/tmp/'
check pass 'rsync -e "ssh -i ~/.ssh/id_ed25519" -a site/ h:/var/www/'
check pass 'ssh -o IdentityFile=~/.ssh/id_ed25519 root@h uptime'
check pass 'dd if=/root/.ssh/id_ed25519 of=/tmp/copy bs=1'
check pass 'ssh-keyscan h | tee -a ~/.ssh/known_hosts'
check pass 'curl -o /tmp/u.keys https://example.com/u.keys; wc -l /root/.ssh/authorized_keys'
check pass 'grep -i ed25519 /root/.ssh/authorized_keys | sed "s/ .*//"'
check pass 'ssh -i ~/.ssh/id_ed25519 root@h "sed -i s/a/b/ /etc/app.conf"'
check pass 'ssh -i ~/.ssh/id_ed25519 root@h "vim --version"'
check pass 'rsync -a --delete /root/.ssh/ /backup/root-ssh/'
check pass 'cp /dev/sda /root/disk.img'
check pass 'curl -o /tmp/sshd_config.new https://example.com/c'

# --- SSH certificates ------------------------------------------
# A certificate sits next to its key and differs only by the
# -cert.pub suffix. Reading one must pass; the private key beside
# it stays protected.
check pass 'ssh-keygen -L -f /etc/ssh/ssh_host_ed25519_key-cert.pub'
check pass 'ssh root@h "ssh-keygen -L -f /etc/ssh/ssh_host_ed25519_key-cert.pub"'
check pass 'ssh-keygen -L -f ~/.ssh/id_ed25519-cert.pub'
check pass 'ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub'
check pass 'cp /etc/ssh/ssh_host_ed25519_key-cert.pub /var/backups/heinzel/'
check deny 'ssh-keygen -f /etc/ssh/ssh_host_ed25519_key -N ""'
check deny 'ssh-keygen -f ~/.ssh/id_ed25519-work -N ""'
check deny 'rm /etc/ssh/ssh_host_ed25519_key-cert.pub'
# Files that decide which certificates may log in: reads pass.
check pass 'cat /etc/ssh/trusted_user_ca_keys'
check pass 'ssh-keygen -lf /etc/ssh/user_ca.pub'
check pass 'grep -H . /etc/ssh/auth_principals/root'
check pass 'ls -l /etc/ssh/auth_principals /etc/ssh/revoked_keys'
check pass 'ssh-keygen -Q -f /etc/ssh/revoked_keys /tmp/k.pub'
check pass 'stat -c %a /etc/ssh/ca.pub 2>/dev/null'
check pass 'cp /etc/ssh/trusted-user-ca-keys.pem /var/backups/heinzel/'
check pass 'cat /etc/ssh/ssh_known_hosts /etc/ssh/moduli'
check pass 'cp /tmp/new.conf /etc/ssh/ssh_config.d/local.conf'
# ... and every write is left to the operator.
check deny 'cp /tmp/ca.pub /etc/ssh/trusted_user_ca_keys'
check deny 'cat /tmp/ca.pub >> /etc/ssh/user_ca.pub'
check deny 'echo root > /etc/ssh/auth_principals/root'
check deny 'tee -a /etc/ssh/auth_principals/root < p.txt'
check deny 'sed -i /alice/d /etc/ssh/auth_principals/root'
check deny 'rm /etc/ssh/revoked_keys'
check deny 'chmod 600 /etc/ssh/ca.pub'
check deny 'ssh-keygen -k -u -f /etc/ssh/revoked_keys leaked.pub'
check deny 'curl -o /etc/ssh/trusted-user-ca-keys.pem https://ca.example.com/ssh/roots'
check deny 'ssh root@h "cp /tmp/p /home/alice/.ssh/authorized_principals"'
check deny "python3 -c \"open('/etc/ssh/ssh_user_key.pub','w')\""
# Outside /etc/ssh: the OpenSSH port and an appliance key store.
check pass 'ssh-keygen -L -f /usr/local/etc/ssh/ssh_host_ed25519_key-cert.pub'
check pass 'ssh-keygen -L -f /conf/sshd/ssh_host_ed25519_key-cert.pub'
check deny 'ssh-keygen -f /conf/sshd/ssh_host_ed25519_key -N ""'
check deny 'cp /tmp/ca.pub /usr/local/etc/ssh/trusted_user_ca_keys'
check deny 'tee /conf/sshd/user_ca.pub < ca.pub'

# --- SSH keys reached through their directory (issue #7) -------
# The protected paths were key FILENAMES, so any operation on the
# enclosing .ssh directory reached every key in it without naming
# one. chmod 600 ~/.ssh/authorized_keys was denied while the
# recursive chown that does strictly more was not.
check deny 'chown -R alice:alice /home/alice/.ssh'
check deny 'chmod -R 700 /root/.ssh'
check deny 'chmod 000 /root/.ssh'
check deny 'rm -rf /home/alice/.ssh'
check deny 'mv /root/.ssh /root/.ssh.bak'
check deny 'install -d -m 700 -o alice -g alice /home/alice/.ssh'
check deny 'ssh -o BatchMode=yes root@h "chown -R alice:alice /home/alice/.ssh"'
# The exact shape that exposed this: the spelled-out chmod is
# denied, so the recursive form must not be the way around it.
check deny 'chown -R alice:alice /home/alice/.ssh && chmod 700 /home/alice/.ssh'
# Same reach through an interpreter, which names no key either.
check deny "python3 -c \"import shutil; shutil.rmtree('/root/.ssh')\""
check deny "node -e \"require('fs').chmodSync('/home/alice/.ssh', 0)\""

# --- same effect through an interpreter (issue #6) -------------
# The path rules recognized a write by the way it was spelled
# (redirect, tee, sed -i, an editor, rm/mv/chmod). An interpreter
# spells none of those and writes through plain file I/O.
check deny "python3 -c \"open('/etc/ssh/sshd_config','a').write('PermitRootLogin yes')\""
check deny "python3.11 -c \"open('/etc/ssh/sshd_config','w')\""
check deny "node -e \"require('fs').appendFileSync('/etc/ssh/sshd_config','X')\""
check deny "perl -e 'open(F,\">\",\"/etc/ssh/sshd_config\")'"
check deny "ruby -e \"File.write('/etc/ssh/sshd_config','')\""
check deny "awk 'BEGIN{printf \"\" > f}' f=/etc/ssh/sshd_config"
check deny "python3 -c \"import os; os.remove('/root/.ssh/authorized_keys')\""
check deny "node -e \"require('fs').unlinkSync('/root/.ssh/authorized_keys')\""
check deny "python3 -c \"open('/etc/ssh/ssh_host_ed25519_key','w').write('')\""
check deny "ruby -e \"File.unlink('/root/.ssh/id_ed25519')\""
check deny "ssh -o BatchMode=yes root@h \"python3 -c \\\"open('/etc/ssh/sshd_config','a')\\\"\""
# Raw devices are the same hole with worse consequences, and the
# original report did not cover them.
check deny "python3 -c \"open('/dev/sda','wb').write(b'0'*4096)\""
check deny "perl -e 'open(D,\">\",\"/dev/nvme0n1\"); print D chr(0)'"
check deny "node -e \"require('fs').writeFileSync('/dev/vda','')\""

# --- SSH connection sharing (rules/ssh-connections.md) ---------
# heinzel's control socket must not read as key material, or
# every remote rm/mv/chmod sent with the standard options is
# denied (see the accepted false positives in the guard).
check pass 'ssh -o ControlMaster=auto -o ControlPath=~/.cache/heinzel/ssh-%C root@h "rm -f /var/tmp/old.log; chmod 644 /etc/motd"'

# --- must pass -------------------------------------------------
check pass 'fdisk -l'
check pass 'sfdisk -l /dev/sda'
check pass 'sfdisk -d /dev/sda'
check pass 'gdisk -l /dev/sda'
check pass 'sgdisk -p /dev/sda'
check pass 'parted -l'
check pass 'gpart show ada0'
check pass 'gpart status'
check pass 'lsblk -f'
check pass 'diskutil list'
check pass 'shutdown -r now'
check pass 'ssh root@h "shutdown -r now"'
check pass 'shutdown -c'
check pass 'mkswap /dev/sda2'
check pass 'rm /tmp/foo'
check pass 'systemctl restart nginx'
check pass 'cat /etc/ssh/sshd_config'
check pass 'grep PermitRootLogin /etc/ssh/sshd_config'
check pass 'sshd -T'
check pass 'df -h'
check pass 'echo halting services'
check pass 'dd if=/dev/sda of=/root/disk-backup.img'
check pass 'uname -a'
check pass 'echo see HEINZEL_GUARD_DISABLE in the docs'

# --- every code block the skills and rules ship passes ---------
# A taboo word used as data in a documented probe is denied like
# the command itself and cancels the whole parallel batch. The
# security skill once skipped inert login shells by a regex of
# their names; the deny pins why that shape was retired. A block
# meant to be denied says so after the language on its fence:
# `operator` (the user runs it, heinzel never does) or `guard-off`
# (heinzel runs it only after the user relaunched with the
# override, so its file must say how). The file name in each
# block path keeps names unique when find starts awk twice.
check deny "awk -F: '(\$7 ~ /(nologin|false|sync|shutdown|halt)\$/)' /etc/passwd"

BLOCKS=$(mktemp -d)
find "$CLAUDE_DIR/skills" "$CLAUDE_DIR/../rules" -name '*.md' \
  -exec awk -v dir="$BLOCKS" '
  /^[ \t]*```/ && !inb { inb = 1
                         if (/[ \t](operator|guard-off)[ \t]*$/) next
                         f = FILENAME; gsub(/\//, "_", f); n++
                         out = dir "/" f "." n; next }
  /^[ \t]*```[ \t]*$/  { if (out) close(out); out = ""; inb = 0; next }
  out                  { print > out }
' {} +
NBLOCKS=0
for blk in "$BLOCKS"/*; do
  [ -f "$blk" ] || continue
  NBLOCKS=$((NBLOCKS + 1))
  check pass "$(cat "$blk")"
done
rm -rf "$BLOCKS"
if [ "$NBLOCKS" -eq 0 ]; then
  FAIL=$((FAIL + 1))
  echo "FAIL: no code blocks found under skills/ or rules/"
fi

# os-replacement.md has guard-off blocks by design, so finding
# none means the search broke, not that all is well.
NGUARDOFF=0
while read -r md; do
  [ -n "$md" ] || continue
  NGUARDOFF=$((NGUARDOFF + 1))
  if grep -q 'HEINZEL_GUARD_DISABLE' "$md"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $md has guard-off blocks but never names" \
      "HEINZEL_GUARD_DISABLE"
  fi
done <<EOF
$(grep -rlE --include='*.md' \
  '^[[:space:]]*```.*[[:space:]]guard-off[[:space:]]*$' \
  "$CLAUDE_DIR/skills" "$CLAUDE_DIR/../rules")
EOF
if [ "$NGUARDOFF" -eq 0 ]; then
  FAIL=$((FAIL + 1))
  echo "FAIL: no guard-off blocks found under rules/"
fi

# --- the system-account probe fails closed ---------------------
# Printing only shells that end in sh passes the guard and misses
# every shell it does not know. The probe is read from the skill,
# and stripping its path makes awk read the fixture from stdin; a
# missing probe or one that stops ending in /etc/passwd fails.
PROBE=$(awk '/^## System Accounts with Login Shells/ { s = 1 }
  s && b && /^```$/ { exit }
  b { print }
  s && /^```bash$/ { b = 1 }' \
  "$CLAUDE_DIR/skills/heinzel-security/references/user-accounts.md")
WANT="bash empty ksh postgres py root "
GOT=$(printf '%s\n' \
  'root:x:0:0:root:/root:/bin/bash' \
  'daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin' \
  'sync:x:4:65534:sync:/bin:/bin/sync' \
  'games:x:5:60:games:/usr/games:/bin/false' \
  'shutdown:x:6:0:shutdown:/sbin:/sbin/shutdown' \
  'halt:x:7:0:halt:/sbin:/sbin/halt' \
  'postgres:x:110:118::/var/lib/postgresql:/bin/bash' \
  'bash:x:990:990::/tmp:/bin/bash' \
  'ksh:x:991:991::/tmp:/bin/ksh93' \
  'py:x:992:992::/tmp:/usr/bin/python3' \
  'empty:x:993:993::/tmp:' \
  'alice:x:1000:1000::/home/alice:/usr/bin/zsh' \
  | sh -c "${PROBE%/etc/passwd}" | cut -d: -f1 | LC_ALL=C sort \
  | tr '\n' ' ')
if [ "$GOT" = "$WANT" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "FAIL: system-account probe reported [$GOT], want [$WANT]"
fi

# --- read-only forms of the newly covered tools (issue #5) -----
check pass 'diskutil info disk0'
check pass 'diskutil apfs list'
check pass 'gpt show /dev/da0'
check pass 'parted /dev/sda print'
check pass 'parted /dev/sda unit MiB print'
check pass 'parted -m -l'
check pass 'sgdisk -p /dev/sda'
check pass 'sgdisk -i 1 /dev/sda'
check pass 'sgdisk -v /dev/sda'
check pass 'nvme list'
check pass 'nvme id-ctrl /dev/nvme0'
check pass 'nvme smart-log /dev/nvme0'
check pass 'badblocks -sv /dev/sda'
check pass 'hdparm -I /dev/sda'
check pass 'blockdev --getsize64 /dev/sda'
check pass 'shred -u /tmp/leftover.txt'
check pass 'wc -l /root/.ssh/authorized_keys'
check pass 'cp /etc/ssh/ssh_host_rsa_key.pub /tmp/'
check pass 'echo done > /dev/null'
check pass 'ssh-keygen -lf /etc/ssh/ssh_host_rsa_key.pub'
check pass 'growpart --dry-run /dev/sda 1'

# --- key probes deny each other when chained (rules/secrets.md) -
# Accepted false positive; see the list in the guard header.
check pass 'file /etc/ssh/ssh_host_ed25519_key'
check deny 'file /etc/ssh/ssh_host_ed25519_key; ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub'

# --- interpreters away from a protected target (issue #6) ------
# Only the combination is a taboo. An interpreter on its own,
# even writing files, is ordinary work and must stay usable.
check pass 'python3 --version'
check pass 'python3 -c "import json,sys; print(json.load(sys.stdin))"'
check pass "python3 -c \"open('/tmp/report.txt','w').write('x')\""
check pass 'node -e "console.log(process.version)"'
check pass 'python3 -m json.tool /etc/myapp/config.json'
check pass 'awk "/^worker_processes/ {print \$2}" /etc/nginx/nginx.conf'
check pass 'perl -pe "s/foo/bar/" /tmp/notes.txt'
check pass 'mix deps.get'
check pass 'ls -l /root/.ssh/'
check pass 'stat -c %a /root/.ssh/authorized_keys'

# --- .ssh as a directory: inspection stays allowed (issue #7) --
# Widening KEY to the directory must not cost the read-only
# probes the rule files themselves prescribe.
check pass 'ls -la /home/alice/.ssh'
check pass 'stat -c "%A %U:%G %n" /home/alice/.ssh'
check pass 'find /home/alice/.ssh -maxdepth 1 -type f'
check pass 'test -w /home/alice/.ssh'
check pass 'getfacl /home/alice/.ssh'
# .ssh must match as a path component, not as a prefix, and a
# destructive command away from it stays ordinary work.
check pass 'chmod 700 /home/alice/.sshrc'
check pass 'chown -R alice:alice /home/alice/Documents'
check pass 'rm -rf /home/alice/.cache'

# --- sshd outside /etc/ssh: ports, packages, appliances --------
# The OpenSSH port keeps config and host keys in
# /usr/local/etc/ssh (FreeBSD, OPNsense); OPNsense keeps its host
# keys in a key store of their own, /conf/sshd.
check deny "sed -i 's/^/#/' /usr/local/etc/ssh/sshd_config"
check deny 'echo PermitRootLogin yes >> /usr/local/etc/ssh/sshd_config'
check deny 'tee /usr/local/etc/ssh/sshd_config < new.conf'
check deny 'vi /usr/local/etc/ssh/sshd_config'
check deny 'cp new.conf /usr/local/etc/ssh/sshd_config'
check deny 'curl -o /usr/local/etc/ssh/sshd_config.d/10-x.conf https://example.com/c'
check deny 'echo PasswordAuthentication yes > /usr/local/etc/ssh/sshd_config.d/10-x.conf'
check deny 'rm /usr/local/etc/ssh/sshd_config.d/10-x.conf'
check deny "python3 -c \"open('/usr/local/etc/ssh/sshd_config','a')\""
check deny 'ssh root@fw "echo X >> /usr/local/etc/ssh/sshd_config"'
check deny 'rm /usr/local/etc/ssh/ssh_host_ed25519_key'
check deny ': > /usr/local/etc/ssh/ssh_host_ed25519_key'
check deny 'ssh-keygen -q -N "" -f /usr/local/etc/ssh/ssh_host_rsa_key'
check deny 'rm /conf/sshd/ssh_host_ed25519_key'
check deny 'mv /conf/sshd/ssh_host_rsa_key /tmp/'
check deny 'chmod 644 /conf/sshd/ssh_host_ecdsa_key'
check deny ': > /conf/sshd/ssh_host_ed25519_key'
check deny 'cp /tmp/k /conf/sshd/ssh_host_ed25519_key'
check deny 'dd if=/dev/zero of=/conf/sshd/ssh_host_rsa_key count=1'
check deny 'ssh-keygen -q -N "" -f /conf/sshd/ssh_host_rsa_key'
check deny "sed -i d /conf/sshd/ssh_host_ed25519_key"
check deny "python3 -c \"open('/conf/sshd/ssh_host_ed25519_key','w')\""
check deny 'ssh root@fw "rm -f /conf/sshd/ssh_host_*"'
# /conf/sshd holds nothing but keys: the directory is the target.
check deny 'rm -f /conf/sshd/*'
check deny 'rm -rf /conf/sshd'
check deny 'mv /conf/sshd /tmp/x'
check deny 'chmod -R 000 /conf/sshd'
check deny 'chown -R nobody /conf/sshd/'
check deny 'cp /tmp/k /conf/sshd/'
check deny 'rsync -a /backup/sshd/ /conf/sshd/'
# Prefixes are matched, not listed: Homebrew's etc/ssh too.
check deny 'echo X >> /opt/homebrew/etc/ssh/sshd_config'
check deny 'rm /opt/homebrew/etc/ssh/ssh_host_ed25519_key'
check deny 'echo X >> "/usr/local/etc/ssh/sshd_config"'
# pfSense keeps keys and config in /etc/ssh, but appends
# /etc/sshd_extra to the sshd_config it generates.
check deny 'echo PermitRootLogin yes >> /etc/sshd_extra'
check deny 'tee /etc/sshd_extra < extra.conf'
check deny "sed -i d /etc/sshd_extra"
check deny 'vi /etc/sshd_extra'
check deny 'rm /etc/sshd_extra'
check deny 'cp extra.conf /etc/sshd_extra'
check deny "python3 -c \"open('/etc/sshd_extra','a')\""
check pass 'cat /etc/sshd_extra'
check pass 'ls -l /etc/sshd_extra'
check pass 'cat /usr/local/etc/ssh/sshd_config'
check pass 'grep -r PermitRootLogin /usr/local/etc/ssh/sshd_config.d/'
check pass 'stat /usr/local/etc/ssh/sshd_config'
check pass 'ls -l /usr/local/etc/ssh/'
check pass 'ssh root@fw "sshd -T -f /usr/local/etc/ssh/sshd_config"'
check pass 'cat /usr/local/etc/ssh/ssh_host_ed25519_key.pub'
check pass 'ls -l /conf/sshd/'
check pass 'stat /conf/sshd/ssh_host_ed25519_key'
check pass 'cp /conf/sshd/ssh_host_ed25519_key.pub /tmp/'
check pass 'ssh-keygen -lf /conf/sshd/ssh_host_ed25519_key.pub'
# The rest of /conf is OPNsense's config store, not a key store.
check pass 'cp /conf/config.xml /root/config.xml.bak'
check pass 'rm /conf/backup/config-1700000000.xml'

# --- heredoc bodies: data vs code (issue #8) -------------------
# Prose legitimately contains taboo words. A heredoc body is only
# exempt when its CONSUMER cannot execute it. The deny cases below
# are the ones that make the exemption safe; if any of them ever
# flips to pass, the exemption has become a hole.
#
# The exact command that exposed this: heinzel's own changelog
# write, blocked over the word inside the prose.
check pass 'cat >> /Users/s/heinzel/memory/servers/h/changelog.log <<EOF
  Verify: clean shutdown checkpoint + database ready.
EOF'
check pass 'cat >> notes.md <<EOF
We ran fdisk /dev/sda and then mkfs.ext4 /dev/sda1 on the new box.
EOF'
check pass 'tee /tmp/report.txt <<EOF
poweroff and halt are taboo; so is dd if=x of=/dev/sda.
EOF'
check pass 'tee -a /tmp/report.txt <<EOF
blkdiscard /dev/nvme0n1 must never run here.
EOF'
# A quoted delimiter and <<- (tab-stripping) are the same case.
check pass "cat > /tmp/doc.md <<'MARK'
shutdown -h now is what we must never do
MARK"
check pass 'cat > /tmp/doc.md <<-END
	shutdown -h now stays documented here
	END'
# Content AFTER the terminator is still command text and is
# still scanned — the exemption covers the body only.
check pass 'cat >> /tmp/doc.md <<EOF
a note about shutdown -h now
EOF
echo written; ls -l /tmp/doc.md'

# The body RUNS: every one of these must stay blocked.
check deny 'ssh root@h "bash -s" <<EOF
shutdown -h now
EOF'
check deny 'ssh -o BatchMode=yes root@h bash -s <<EOF
mkfs.ext4 /dev/sda1
EOF'
check deny 'bash <<EOF
fdisk /dev/sda
EOF'
check deny 'sh -s <<EOF
blkdiscard /dev/sda
EOF'
check deny 'python3 <<EOF
open("/etc/ssh/sshd_config","a").write("X")
EOF'
check deny 'sudo tee /tmp/x <<EOF
halt
EOF'
# A taboo appended AFTER the heredoc terminator is real code.
check deny 'cat >> /tmp/doc.md <<EOF
harmless prose
EOF
shutdown -h now'
check deny 'cat >> /tmp/doc.md <<EOF
harmless prose
EOF
fdisk /dev/sda'
# The sink itself must not be a device or a file that later runs.
check deny 'cat > /dev/sda <<EOF
anything
EOF'
check deny 'cat > /etc/cron.d/heinzel-job <<EOF
0 3 * * * root shutdown -h now
EOF'
check deny 'cat > /etc/systemd/system/x.service <<EOF
ExecStart=/sbin/poweroff
EOF'
check deny 'cat > ~/.config/systemd/user/x.service <<EOF
ExecStart=/sbin/poweroff
EOF'
# "Later runs" is wider than cron and systemd: a script file, an
# executable directory, a shell start-up file and a launchd job
# all reach the effect on a delay, so their bodies stay scanned.
check deny 'cat > /usr/local/bin/maint.sh <<EOF
shutdown -h now
EOF'
check deny 'cat > ~/bin/wipe <<EOF
fdisk /dev/sda
EOF'
check deny 'tee /usr/local/sbin/nightly <<EOF
blkdiscard /dev/sdb
EOF'
check deny 'cat > /tmp/build.py <<EOF
os.system("shutdown -h now")
EOF'
check deny 'cat >> ~/.bashrc <<EOF
shutdown -h now
EOF'
check deny 'cat >> ~/.zprofile <<EOF
poweroff
EOF'
check deny 'cat >> ~/.profile <<EOF
halt
EOF'
check deny 'cat > ~/Library/LaunchAgents/x.plist <<EOF
<string>/sbin/shutdown -h now</string>
EOF'
# ...but the match is on the path, not on a substring of a word:
# a documentation file whose name merely contains "bin" or "sh"
# is still an ordinary file, and its prose is still exempt.
check pass 'cat >> /tmp/combine-notes.md <<EOF
The shutdown checkpoint ran before fdisk /dev/sda was needed.
EOF'
check pass 'cat >> /tmp/shipping.log <<EOF
poweroff was never issued on this host.
EOF'
# No terminator: the body cannot be delimited, so nothing is
# skipped and the taboo inside is scanned (fail closed).
check deny 'cat >> /tmp/doc.md <<EOF
shutdown -h now'
# Two heredocs on one line: the single-body assumption does not
# hold, so scan everything.
check deny 'cat <<EOF1 >/tmp/a; cat <<EOF2 >/tmp/b
shutdown -h now
EOF1
x
EOF2'
# A second command smuggled onto the sink line.
check deny 'cat >> /tmp/doc.md <<EOF; shutdown -h now
prose
EOF'
check deny 'cat >> /tmp/$(shutdown -h now) <<EOF
prose
EOF'
# Not a data sink at all, even though it looks close.
check deny 'cat >> /tmp/doc.md < <(shutdown -h now)'
# The interpreter rule still sees an interpreter + protected path
# when the heredoc is NOT the exempt shape.
check deny 'perl <<EOF
unlink("/root/.ssh/authorized_keys")
EOF'

# Stripping must fail CLOSED when awk cannot run at all: the body
# then stays in the scanned text, so a body that RUNS is caught
# and a documentation body is merely blocked as before.
SHIM2=$(mktemp -d)
printf '#!/bin/sh\nexit 2\n' > "$SHIM2/awk"
chmod +x "$SHIM2/awk"
OUT=$(json_for 'cat >> /tmp/doc.md <<EOF
shutdown -h now
EOF' | env -u HEINZEL_GUARD_DISABLE PATH="$SHIM2:$PATH" sh "$HOOK")
if printf '%s' "$OUT" \
  | grep -q '"permissionDecision":"deny"'; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "FAIL: broken awk failed OPEN (heredoc body was skipped)"
fi
rm -rf "$SHIM2"

# --- fallback path: malformed (non-JSON) stdin -----------------
OUT=$(printf '%s' 'mkfs.ext4 /dev/sda1' \
  | env -u HEINZEL_GUARD_DISABLE sh "$HOOK")
if printf '%s' "$OUT" \
  | grep -q '"permissionDecision":"deny"'; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "FAIL: raw-input fallback did not deny mkfs"
fi

# --- operator override via inherited environment ---------------
OUT=$(json_for 'mkfs.ext4 /dev/sda1' \
  | HEINZEL_GUARD_DISABLE=1 sh "$HOOK")
if [ -z "$OUT" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "FAIL: HEINZEL_GUARD_DISABLE=1 env did not disable guard"
fi

# --- degraded awk must fail CLOSED -----------------------------
# hit_without() decides the read-only exemptions via awk. If awk
# is missing or cannot evaluate POSIX classes, the exemption
# cannot be proven, and an unprovable exemption must block, not
# pass. Simulated with an awk shim that only fails.
SHIM=$(mktemp -d)
printf '#!/bin/sh\nexit 2\n' > "$SHIM/awk"
chmod +x "$SHIM/awk"
OUT=$(json_for 'fdisk -l /dev/sda' \
  | env -u HEINZEL_GUARD_DISABLE PATH="$SHIM:$PATH" sh "$HOOK")
if printf '%s' "$OUT" \
  | grep -q '"permissionDecision":"deny"'; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "FAIL: broken awk failed OPEN (read-only fdisk was allowed)"
fi
rm -rf "$SHIM"

# --- no negated hit() may remain -------------------------------
# A rule of the form  hit X && ! hit Y  evaluates Y against the
# whole command string, so any unrelated flag disarms it (issue
# #4). Exemptions belong in hit_without(), which scopes them to
# the invocation. Without this check the shape creeps back in.
if grep -q '! *hit ' "$HOOK"; then
  FAIL=$((FAIL + 1))
  echo "FAIL: guard still uses a negated whole-string hit;" \
    "use hit_without() so the exemption stays scoped"
else
  PASS=$((PASS + 1))
fi

# --- hook registration: no relative script paths ---------------
# Hooks run in the session's cwd, not the project root. A
# relative path breaks after any `cd` and the guard fails
# open (issue #2). Every hook command must resolve its
# script via $CLAUDE_PROJECT_DIR.
SETTINGS="$CLAUDE_DIR/settings.json"
if grep -o '"command": *"[^"]*\.sh' "$SETTINGS" \
  | grep -v 'CLAUDE_PROJECT_DIR' >/dev/null; then
  FAIL=$((FAIL + 1))
  echo "FAIL: settings.json registers a hook script without" \
    '$CLAUDE_PROJECT_DIR (relative path fails open after cd)'
else
  PASS=$((PASS + 1))
fi

echo "guard-taboos tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
