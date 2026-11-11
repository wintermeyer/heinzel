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

# --- attack tools (rules/ethics.md) ----------------------------
check deny 'hashcat -m 1800 hashes.txt rockyou.txt'
check deny 'hydra -l root -P list.txt ssh://10.0.0.5'
check deny 'ssh root@h "hashcat -m 500 /etc/shadow wl.txt"'
check deny 'aircrack-ng -w wl.txt capture.cap'
check deny 'sqlmap -u https://example.com --dump'
check deny 'msfconsole -q'
check deny 'nxc smb 10.0.0.0/24'
check deny 'john --wordlist=rockyou.txt shadow.txt'
check deny 'john shadow.hashes.pot'
check deny 'apt-get install -y hashcat'
check deny 'apt install john'
check deny 'dnf install -y hydra'
check deny 'brew install aircrack-ng'
check deny 'pkg install -y john-the-ripper'
check deny 'pip3 install sqlmap'
# must still pass: john as a username
check pass 'useradd john'
check pass 'id john'
check pass 'grep john /etc/passwd'
check pass 'systemctl status john.service'
# accepted false positive: a cracker name as a query argument,
# same coarse match as `grep poweroff` (see guard header)
check deny 'apt-cache show hashcat'
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

# --- the command prefix (issue #77) -----------------------------
# heinzel writes cp/mv/rm as `command cp` to skip an rm -i alias.
# The prefix must not hide a taboo from the guard.
check deny 'command rm -rf ~/.ssh'
check deny 'command mv /etc/ssh/sshd_config /tmp/'
check deny 'command cp /tmp/x /etc/sudoers'
check deny 'command dd if=/dev/zero of=/dev/sda'
check deny 'command fdisk /dev/sda'
check deny 'ssh root@h "command rm /etc/ssh/ssh_host_ed25519_key"'
check pass 'command cp -p /etc/nginx/nginx.conf /var/backups/heinzel/'
check pass 'command rm /var/tmp/old.log'

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

# --- boot loaders and firmware variables (Heinzel Pro, 3.0) ----
# Every effect once as itself, once inside ssh host "...", once
# through a language runtime, and its read-only form passes.
check deny 'efibootmgr -c -d /dev/sda -p 1 -L Debian -l \EFI\debian\grubx64.efi'
check deny 'efibootmgr --create --disk /dev/sda --part 1 --label x --loader \x'
check deny 'efibootmgr -o 0003,0001'
check deny 'efibootmgr -n 0003'
check deny 'efibootmgr -B -b 0002'
check deny 'efibootmgr -b 0002 -A'
check deny 'efibootmgr -t 5'
check deny 'ssh root@h "efibootmgr -o 0001,0003"'
check deny 'efibootmgr -v; efibootmgr -n 0003'
check deny 'grub-install /dev/sda'
check deny 'grub-install --target=x86_64-efi --efi-directory=/boot/efi'
check deny 'grub2-install /dev/vda'
check deny 'ssh root@h "grub-install /dev/sda"'
check deny 'update-grub'
check deny 'update-grub2'
check deny 'grub-mkconfig -o /boot/grub/grub.cfg'
check deny 'grub2-mkconfig --output=/boot/grub2/grub.cfg'
check deny 'ssh root@h "grub2-mkconfig -o /boot/grub2/grub.cfg"'
check deny 'bootctl install'
check deny 'bootctl update'
check deny 'bootctl remove'
check deny 'bootctl set-default debian.conf'
check deny 'bootctl set-oneshot freebsd.conf'
check deny 'ssh root@h "bootctl install"'
check deny 'bless --mount /Volumes/Macintosh\ HD --setBoot'
check deny 'bless --folder /Volumes/X/System/Library/CoreServices --setBoot'
check deny 'sudo bless --device /dev/disk3s1 --nextonly'
check deny 'efivar -w -n 8be4df61-93ca-11d2-aa0d-00e098032b8c-Boot0001 -f entry.bin'
check deny 'efivar --write --name x --fromfile y'
check deny 'echo 1 > /sys/firmware/efi/efivars/Boot0001-8be4df61-93ca-11d2-aa0d-00e098032b8c'
check deny 'rm /sys/firmware/efi/efivars/dump-type0-1-0-1234'
check deny 'rm -rf /sys/firmware/efi/efivars/'
check deny 'chattr -i /sys/firmware/efi/efivars/Boot0001-x'
check deny 'ssh root@h "rm /sys/firmware/efi/efivars/x"'
check deny 'python3 -c "open(\"/sys/firmware/efi/efivars/x\",\"wb\").write(b\"\")"'
check deny 'ssh root@h "python3 -c \"open(\\\"/sys/firmware/efi/efivars/x\\\",\\\"wb\\\")\""'
check pass 'efibootmgr'
check pass 'efibootmgr -v'
check pass 'ssh root@h "efibootmgr -v"'
check pass 'bootctl status'
check pass 'bootctl list'
check pass 'bootctl is-installed'
check pass 'grub-mkconfig'
check pass 'grub-install --version'
check pass 'bless --info /Volumes/Macintosh\ HD'
check pass 'bless --getBoot'
check pass 'efivar -l'
check pass 'efivar -p -n 8be4df61-93ca-11d2-aa0d-00e098032b8c-BootOrder'
check pass 'ls /sys/firmware/efi/efivars'
check pass 'cat /sys/firmware/efi/efivars/BootOrder-8be4df61-93ca-11d2-aa0d-00e098032b8c | xxd'
check pass 'cat /boot/loader.conf'
check pass 'grep -r GRUB_CMDLINE /etc/default/grub'

# --- accounts and sudo (Heinzel Pro, 3.0) ----------------------
# Deleting an account or a group, and any write to sudoers or an
# account file, is denied. Creating an account and resetting a
# password stay with the prompt and pass here.
check deny 'userdel -r deploy'
check deny 'userdel deploy'
check deny 'deluser --remove-home alice'
check deny 'groupdel staff'
check deny 'delgroup staff'
check deny 'ssh root@h "userdel -r bob"'
check deny 'pw userdel deploy -r'
check deny 'pw user del -n deploy'
check deny 'pw groupdel staff'
check deny 'sysadminctl -deleteUser alice'
check deny 'dscl . -delete /Users/alice'
check deny 'visudo'
check deny 'visudo -f /etc/sudoers.d/deploy'
check deny 'ssh root@h "visudo -f /etc/sudoers.d/deploy"'
check deny 'vipw'
check deny 'vigr -s'
check deny 'echo "deploy ALL=(root) NOPASSWD: /usr/bin/systemctl restart x" >> /etc/sudoers.d/deploy'
check deny 'echo "deploy ALL=(root) NOPASSWD: ALL" > /etc/sudoers.d/deploy'
check deny 'tee /etc/sudoers.d/deploy < deploy.sudoers'
check deny 'tee -a /etc/sudoers < line'
check deny "sed -i 's/^#//' /etc/sudoers"
check deny 'vi /etc/sudoers'
check deny 'nano /etc/sudoers.d/deploy'
check deny 'cp sudoers.new /etc/sudoers'
check deny 'install -m 440 deploy /etc/sudoers.d/deploy'
check deny 'rm /etc/sudoers.d/deploy'
check deny 'chmod 666 /etc/sudoers'
check deny 'cp /usr/local/etc/sudoers.new /usr/local/etc/sudoers'
check deny 'ssh root@h "echo x >> /etc/sudoers.d/deploy"'
check deny 'python3 -c "open(\"/etc/sudoers.d/x\",\"w\").write(\"a ALL=(ALL) NOPASSWD: ALL\")"'
check deny 'perl -e "open(F, q{>>/etc/sudoers}); print F q{x}"'
check deny 'echo "root::0:0:root:/root:/bin/sh" >> /etc/passwd'
check deny 'echo x > /etc/shadow'
check deny 'ssh h "echo deploy:x:1001:1001::/home/deploy:/bin/sh >> /etc/passwd"'
check deny "sed -i 's/^alice:/alice-old:/' /etc/group"
check deny 'vi /etc/master.passwd'
check deny 'cp passwd.new /etc/passwd'
check deny 'rm /etc/shadow'
check deny 'chmod 644 /etc/shadow'
check deny 'tee /etc/gshadow < x'
check deny 'python3 -c "open(\"/etc/shadow\",\"a\").write(\"x\")"'
check deny 'node -e "require(\"fs\").appendFileSync(\"/etc/passwd\",\"x\")"'
check deny 'ssh root@h "perl -pi -e s/x/y/ /etc/passwd"'
check pass 'useradd --system --shell /bin/sh --create-home deploy'
check pass 'adduser --system --home /home/deploy deploy'
check pass 'pw useradd deploy -d /home/deploy -s /bin/sh -m'
check pass 'usermod -s /bin/bash deploy'
check pass 'passwd alice'
check pass 'passwd -S deploy'
check pass 'chpasswd < creds'
check pass 'visudo -c'
check pass 'visudo -c -f /etc/sudoers.d/deploy'
check pass 'cat /etc/sudoers'
check pass 'grep -r deploy /etc/sudoers.d/'
check pass 'ls -l /etc/sudoers.d/'
check pass 'stat /etc/sudoers'
check pass 'cat /etc/sudoers > /root/sudoers.bak'
check pass "awk -F: '(\$3 == 0) {print \$1}' /etc/passwd"
check pass "awk -F: '(\$2 == \"\") {print \$1}' /etc/shadow"
check pass 'getent passwd deploy | cut -d: -f7'
check pass 'grep deploy /etc/shadow'
check pass 'grep deploy /etc/passwd'
check pass 'ls -l /etc/shadow'
check pass 'id deploy'
check pass 'pw usershow deploy'
check pass 'dscl . -read /Users/alice'
check pass 'sysadminctl -secureTokenStatus alice'
check pass 'groups alice'
check pass 'ssh root@h "cat /etc/sudoers.d/deploy"'

# The server lock (/etc/heinzel.conf, rules/access-control.md).
# The machine's owner sets it; heinzel reads it and never lifts
# it, by any of the ways a file gets written, moved or deleted.
check deny 'echo "allow_changes = true" > /etc/heinzel.conf'
check deny 'echo x >> /etc/heinzel.conf'
check deny "sed -i 's/false/true/' /etc/heinzel.conf"
check deny 'rm /etc/heinzel.conf'
check deny 'rm -f /private/etc/heinzel.conf'
check deny 'mv /etc/heinzel.conf /etc/heinzel.conf.off'
check deny 'chmod 000 /etc/heinzel.conf'
check deny 'truncate -s 0 /etc/heinzel.conf'
check deny 'cp heinzel.conf /etc/heinzel.conf'
check deny 'tee /etc/heinzel.conf < x'
check deny 'vi /etc/heinzel.conf'
check deny 'ssh root@h "rm /etc/heinzel.conf"'
check deny 'ssh root@h "sed -i s/false/true/ /etc/heinzel.conf"'
check deny 'python3 -c "import os; os.remove(\"/etc/heinzel.conf\")"'
# Other spellings of the same file: a case-insensitive filesystem
# (macOS), // and /./, a relative path after cd, find -delete.
check deny 'rm /ETC/HEINZEL.CONF'
check deny 'rm /etc//heinzel.conf'
check deny 'rm /etc/./heinzel.conf'
check deny 'cd /etc && rm heinzel.conf'
check deny 'cd /etc; echo allow_changes=true > heinzel.conf'
check deny 'find /etc -name heinzel.conf -delete'
check deny 'ln -sf /dev/null /etc/heinzel.conf'
check pass 'cat /etc/heinzel.conf'
check pass 'ssh root@h "cat /etc/heinzel.conf"'
check pass 'ssh root@h "if [ -e /etc/heinzel.conf ]; then cat /etc/heinzel.conf || echo HEINZEL_CONF_UNREADABLE; else echo HEINZEL_CONF_ABSENT; fi"'
check pass 'grep -i allow_changes /etc/heinzel.conf'
check pass 'ls -l /etc/heinzel.conf'

# --- every code block the skills and rules ship passes ---------
# A taboo word used as data in a documented probe is denied like
# the command itself and cancels the whole parallel batch. The
# security skill once skipped inert login shells by a regex of
# their names; the deny pins why that shape was retired. A block
# meant to be denied says so after the language on its fence:
# `operator` (the user runs it, heinzel never does). The old
# `guard-off` fence (heinzel ran it after the operator disarmed
# the guard) left with the OS-replacement rules in 3.0; it is
# still skipped so a stray one never passes as shipped code. The
# file name in each block path keeps names unique when find
# starts awk twice.
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

# Since 3.0 no shipped rule may need the guard disarmed: a
# guard-off fence is a leftover of the OS-replacement rules that
# moved to Heinzel Pro.
if grep -rlE --include='*.md' \
  '^[[:space:]]*```.*[[:space:]]guard-off[[:space:]]*$' \
  "$CLAUDE_DIR/skills" "$CLAUDE_DIR/../rules" >/dev/null; then
  FAIL=$((FAIL + 1))
  echo "FAIL: a rule or skill still ships a guard-off block"
else
  PASS=$((PASS + 1))
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

# --- a redirect glued to the protected path --------------------
# END includes < and >: these replaced the file while the spaced
# forms were denied.
check deny 'tee /etc/ssh/sshd_config<<EOF'
check deny 'echo X | tee -a /etc/ssh/sshd_config>/dev/null'
check deny 'tee -a /etc/ssh/sshd_config</tmp/new'
check deny 'tee /etc/ssh/sshd_config.d/x.conf>/dev/null'
check deny 'ssh root@h "tee /etc/ssh/sshd_config.d/99.conf</tmp/x"'
check deny 'tee ~/.ssh/authorized_keys</tmp/k'
check deny 'echo k | tee -a ~/.ssh/authorized_keys>/dev/null'
check deny 'tee /etc/ssh/ssh_host_ed25519_key</tmp/k'
check pass 'tee /tmp/report.txt</tmp/in'

# --- CLOBBER: one list of destructive tools for keys and sshd --
check deny 'install -m 600 /tmp/new /etc/ssh/sshd_config'
check deny 'install -m 600 /tmp/new /usr/local/etc/ssh/sshd_config'
check deny 'ln -sf /tmp/x /etc/ssh/sshd_config'
check deny 'patch /etc/ssh/sshd_config < /tmp/d'
check deny 'shred -u /etc/ssh/sshd_config'
check deny 'patch ~/.ssh/authorized_keys < /tmp/d'
check pass 'ls -ln /etc/ssh/sshd_config'

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

# --- no operator override (3.0) --------------------------------
# HEINZEL_GUARD_DISABLE=1 in the environment used to disarm the
# guard for an OS replacement. That work is Heinzel Pro's now,
# and the guard has no off switch: the variable changes nothing.
OUT=$(json_for 'mkfs.ext4 /dev/sda1' \
  | HEINZEL_GUARD_DISABLE=1 sh "$HOOK")
if printf '%s' "$OUT" \
  | grep -q '"permissionDecision":"deny"'; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "FAIL: HEINZEL_GUARD_DISABLE=1 in the environment disabled" \
    "the guard; it has no off switch since 3.0"
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

# --- a redirect onto a computed target (issue #51) -------------
check deny 'ssh root@h '\''bash -ic "echo sensible-editor would run: \$SELECTED_EDITOR -> \$(readlink -f \$SELECTED_EDITOR)"'\'''
check deny 'echo editor -> $(readlink -f /usr/bin/editor)'
check deny 'echo editor -> $SELECTED_EDITOR'
check deny 'ssh h "echo editor ->\${EDITOR}"'
check deny 'echo x > "$(command -v nvim)"'
check deny 'echo x >|$(which vim)'
check deny 'ssh h "echo x 1> \$(command -v vim)"'
check pass 'out=$(ls /etc 2>&1); echo "$out"'
check pass 'echo "$(date) done" > log.txt'
check pass 'cat - > "$OUT"'
check pass 'tar -cf - . > "$T/backup.tar"'
check pass 'echo editor -> vim'
check pass 'diff <(sort a) <(sort b)'
check pass 'ls | tee >(wc -l) > list.txt'
# Accepted false positive: quoted here, but one ssh or bash -c
# level further in the same quotes are gone, and the guard cannot
# count quote depth.
check deny 'echo "editor -> $(readlink -f /usr/bin/editor)"'

# --- rollback timer (rules/rollback-timer.md) ------------------
# Every step of the recipe must pass, and a rollback script is
# scanned like any other script: a taboo inside it still denies.
check pass 'ssh root@h "cp -p /etc/netplan/50-cloud-init.yaml /var/backups/heinzel/50-cloud-init.yaml.20261018-0930"'
check pass 'ssh root@h "cat > /var/backups/heinzel/rollback-20261018-0930.sh" <<'\''EOF'\''
#!/bin/sh
cp -p /var/backups/heinzel/50-cloud-init.yaml.20261018-0930 /etc/netplan/50-cloud-init.yaml
netplan apply
logger -t heinzel "rollback-20261018-0930 ran"
EOF'
check pass 'ssh root@h "chmod 700 /var/backups/heinzel/rollback-20261018-0930.sh"'
check pass 'ssh root@h "systemctl list-timers --all heinzel-rollback-*"'
check pass 'ssh root@h "systemd-run --unit=heinzel-rollback-20261018-0930 --on-active=120 /var/backups/heinzel/rollback-20261018-0930.sh"'
check pass 'ssh root@h "systemd-run --unit=heinzel-apply-20261018-0930 --wait netplan apply"'
check pass 'ssh -o BatchMode=yes -o ConnectTimeout=5 -o ControlMaster=no -o ControlPath=none -o HostKeyAlias=h root@192.0.2.10 true'
check pass 'ssh root@h "systemctl stop heinzel-rollback-20261018-0930.timer"'
check pass 'ssh root@h "nft list ruleset > /var/backups/heinzel/ruleset-20261018-0930.nft"'
check pass 'ssh root@h "firewall-cmd --reload"'
check pass 'ssh root@h "daemon -f -p /var/run/heinzel-rollback-20261018-0930.pid sh -c '\''sleep 120; sh /var/backups/heinzel/rollback-20261018-0930.sh'\''"'
check pass 'ssh root@h "pkill -F /var/run/heinzel-rollback-20261018-0930.pid"'
check pass 'ssh root@h "nohup sh -c '\''echo \$\$ > /var/run/heinzel-rollback-20261018-0930.pid; sleep 120; sh /var/backups/heinzel/rollback-20261018-0930.sh'\'' >/dev/null 2>&1 &"'
check deny 'ssh root@h "cat > /var/backups/heinzel/rollback-20261018-0930.sh" <<'\''EOF'\''
#!/bin/sh
cp -p /var/backups/heinzel/sshd_config.20261018-0930 /etc/ssh/sshd_config
EOF'

# --- file-edit tools (Edit, Write, NotebookEdit) ---------------
# These tools write a file without any command line, so no rule
# above ever sees them. In file mode the guard judges the TARGET
# path alone. The text being written is data: a memory file may
# name every taboo there is.
file_json() {
  # $1 tool name, $2 path key, $3 path, $4 text being written.
  jq -n --arg t "$1" --arg k "$2" --arg p "$3" --arg c "$4" \
    '{tool_name:$t,tool_input:{($k):$p,content:$c,new_string:$c}}'
}

check_file() {
  EXPECT=$1
  OUT=$(file_json "$2" "$3" "$4" "$5" \
    | env -u HEINZEL_GUARD_DISABLE sh "$HOOK" file)
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
    echo "FAIL [$EXPECT, got $GOT]: $2 $4"
  fi
}

if command -v jq >/dev/null 2>&1; then
  check_file deny Write file_path /etc/ssh/sshd_config 'Port 22'
  check_file deny Edit file_path /etc/ssh/sshd_config.d/10-x.conf x
  check_file deny Edit file_path /usr/local/etc/ssh/sshd_config x
  check_file deny Write file_path /etc/sshd_extra x
  check_file deny Edit file_path /root/.ssh/authorized_keys x
  check_file deny Write file_path /home/alice/.ssh/id_ed25519 x
  check_file deny Write file_path /home/alice/.ssh/id_ed25519.pub x
  check_file deny Write file_path /etc/ssh/ssh_host_ed25519_key x
  check_file deny Write file_path /conf/sshd/ssh_host_rsa_key x
  check_file deny Write file_path /dev/sda x
  check_file deny Write file_path /tmp/../dev/nvme0n1 x
  check_file deny NotebookEdit notebook_path \
    /root/.ssh/authorized_keys x
  # Heinzel Pro's files since 3.0: sudoers, the account files,
  # a firmware variable.
  check_file deny Write file_path /etc/sudoers x
  check_file deny Edit file_path /etc/sudoers.d/deploy x
  check_file deny Write file_path /usr/local/etc/sudoers x
  check_file deny Write file_path /etc/passwd x
  check_file deny Edit file_path /etc/shadow x
  check_file deny Write file_path /etc/group x
  check_file deny Write file_path /etc/master.passwd x
  check_file deny Write file_path /sys/firmware/efi/efivars/Boot0001-x x
  check_file deny Write file_path /etc/heinzel.conf x
  check_file deny Edit file_path /private/etc/heinzel.conf x
  check_file pass Write file_path /etc/sudo.conf x
  check_file pass Write file_path /etc/default/grub x
  check_file pass Write file_path /boot/loader.conf x
  # Another spelling of the same file. A filesystem that ignores
  # case (macOS) opens it under any capitalization, and the kernel
  # resolves //, /./ and x/../ before any pattern sees them.
  check_file deny Write file_path /etc/ssh/SSHD_CONFIG x
  check_file deny Write file_path /Users/a/.SSH/Authorized_Keys x
  check_file deny Write file_path /Users/a/.ssh/ID_ed25519 x
  check_file deny Write file_path /etc/ssh/./sshd_config x
  check_file deny Write file_path /etc//ssh/sshd_config x
  check_file deny Write file_path /etc/ssh/x/../sshd_config x
  check_file deny Write file_path /etc/ssh/x/y/../../sshd_config x
  check_file deny Write file_path /etc/ssh/sshd_config.d/./a.conf x
  check_file deny Write file_path /home/a/.ssh/./id_ed25519 x
  check_file deny Write file_path /home/a/.ssh//id_ed25519 x
  check_file deny Write file_path /home/a/.ssh/x/../id_ed25519 x
  check_file deny Write file_path /etc/ssh/./ssh_host_rsa_key x
  check_file deny Write file_path /dev/./sda x
  check_file deny Write file_path /dev//sda x
  check_file deny Write file_path /dev/x/../sda x
  # Case folding is not ASCII-only: APFS folds the long s onto s
  # and the Kelvin sign onto k, and HFS+ ignores a zero-width
  # joiner altogether. Bytes are built here so that no editor
  # normalizes them away.
  LONGS=$(printf '\305\277')
  KELVIN=$(printf '\342\204\252')
  ZWJ=$(printf '\342\200\215')
  UUML=$(printf '\303\274')
  check_file deny Write file_path "/etc/ssh/${LONGS}shd_config" x
  check_file deny Write file_path \
    "/Users/a/.ssh/authorized_${KELVIN}eys" x
  check_file deny Write file_path "/etc/ssh/sshd_${ZWJ}config" x
  check_file deny Write file_path \
    "/etc/ssh/.${ZWJ}/${LONGS}shd_config" x
  # APFS folds FULLY: a ligature or a sharp s opens the file whose
  # name spells it out (measured on macOS, [ -e ] on an fi ligature
  # finds config).
  FI=$(printf '\357\254\201')
  ST=$(printf '\357\254\206')
  SZ=$(printf '\303\237')
  CAPSZ=$(printf '\341\272\236')
  FFL=$(printf '\357\254\204')
  check_file deny Write file_path "/etc/ssh/sshd_con${FI}g" x
  check_file deny Write file_path "/etc/${SZ}h/${SZ}hd_config" x
  check_file deny Write file_path "/etc/${CAPSZ}h/sshd_config" x
  check_file deny Write file_path \
    "/etc/ssh/ssh_ho${ST}_ed25519_key" x
  check_file deny Write file_path "/Users/a/.${SZ}h/id_ed25519" x
  # The two remaining entries of the table: U+1DF95 and the
  # dotted capital I.
  check_file deny Write file_path \
    "/etc/$(printf '\360\235\276\225')h/sshd_config" x
  check_file deny Write file_path \
    "/etc/ssh/sshd_conf$(printf '\304\260')g" x
  check_file pass Write file_path "/home/alice/Stra${SZ}e.md" x
  check_file pass Write file_path "/home/alice/wa${FFL}e.md" x
  check_file pass Write file_path \
    "/home/alice/Notizen/${UUML}bersicht.md" x
  # A relative target is resolved against the session's cwd, so it
  # is judged there: the bare name sshd_config is a protected file
  # in /etc/ssh and an ordinary one anywhere else.
  rel_file() {
    EXPECT=$1
    OUT=$(jq -n --arg c "$2" --arg p "$3" \
      '{cwd:$c,tool_name:"Write",tool_input:{file_path:$p}}' \
      | env -u HEINZEL_GUARD_DISABLE sh "$HOOK" file)
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
      echo "FAIL [$EXPECT, got $GOT]: relative $3 in $2"
    fi
  }
  rel_file deny /etc/ssh sshd_config
  rel_file deny /etc sshd_extra
  rel_file deny /etc/ssh ssh_host_ed25519_key
  rel_file deny /home/alice/.ssh id_ed25519
  rel_file deny /home/alice .ssh/id_ed25519
  rel_file deny /etc/nginx ../ssh/sshd_config
  rel_file deny /dev sda
  rel_file pass /home/alice/heinzel memory/servers/h/memory.md
  rel_file pass /home/alice/heinzel sshd_config
  # No cwd in the input: the hook's own working directory counts.
  RELDIR=$(mktemp -d)
  mkdir "$RELDIR/.ssh"
  OUT=$(jq -n '{tool_input:{file_path:"id_ed25519"}}' \
    | (cd "$RELDIR/.ssh" \
      && env -u HEINZEL_GUARD_DISABLE sh "$HOOK" file))
  if printf '%s' "$OUT" \
    | grep -q '"permissionDecision":"deny"'; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: relative key name passed without a cwd field"
  fi
  rm -rf "$RELDIR"
  # Both path keys at once: every one of them is judged, so a
  # harmless one cannot stand in front of a protected one.
  OUT=$(jq -n '{tool_name:"NotebookEdit",tool_input:{file_path:
    "/tmp/a.ipynb",notebook_path:"/etc/ssh/sshd_config"}}' \
    | env -u HEINZEL_GUARD_DISABLE sh "$HOOK" file)
  if printf '%s' "$OUT" \
    | grep -q '"permissionDecision":"deny"'; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: a second path key hid a protected target"
  fi
  # The use case from PR #62: memory that NAMES the protected
  # paths and a few taboo commands is ordinary text.
  check_file pass Edit file_path \
    /home/alice/heinzel/memory/servers/h/memory.md \
    'sshd: /etc/ssh/sshd_config, keys in /root/.ssh/authorized_keys'
  check_file pass Write file_path \
    /home/alice/heinzel/memory/servers/h/changelog.log \
    'shutdown -h now was refused; mkfs.ext4 /dev/sda1 was not run'
  # Same boundary as the Bash rules: the client config and
  # known_hosts are not keys, ssh_config is not sshd_config.
  check_file pass Edit file_path /home/alice/.ssh/config x
  check_file pass Edit file_path /etc/ssh/ssh_config x
  # A directory merely called dev is not the device tree.
  check_file pass Write file_path /home/alice/dev/sdk/notes.md x
  check_file pass Write file_path /home/alice/dev/data/x.md x
  check_file pass Write file_path /dev/null x

  # Degraded: when jq cannot name the target, the whole input is
  # scanned for a protected path. A note about one is then blocked
  # too, a write to one must never pass.
  SHIM3=$(mktemp -d)
  printf '#!/bin/sh\nexit 2\n' > "$SHIM3/jq"
  chmod +x "$SHIM3/jq"
  degraded_file() {
    EXPECT=$1
    OUT=$(printf '%s' "$2" \
      | env -u HEINZEL_GUARD_DISABLE PATH="$SHIM3:$PATH" \
        sh "$HOOK" file)
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
      echo "FAIL [$EXPECT, got $GOT] without jq: $2"
    fi
  }
  degraded_file deny \
    "$(file_json Write file_path /etc/ssh/sshd_config x)"
  degraded_file deny \
    "$(file_json Write file_path /root/.ssh/authorized_keys x)"
  degraded_file deny "$(file_json Write file_path /dev/sda x)"
  degraded_file deny "$(file_json Edit file_path /tmp/memory.md \
    'sshd: /etc/ssh/sshd_config')"
  # JSON may spell a slash or any character as an escape. Only a
  # JSON parser can undo that, so without one it is unprovable.
  degraded_file deny \
    '{"tool_input":{"file_path":"\/etc\/ssh\/sshd_config"}}'
  # The backslash is built at run time: an editor that decodes
  # escapes on save would turn the fixture into the plain path.
  BSL=$(printf '\134')
  degraded_file deny \
    '{"tool_input":{"file_path":"/tmp/sshd_conf'"$BSL"'u0069g"}}'
  degraded_file deny \
    "$(file_json Write file_path /etc/ssh/./SSHD_config x)"
  # A relative target cannot be resolved without a JSON parser.
  degraded_file deny '{"tool_input":{"file_path":"sshd_config"}}'
  degraded_file deny \
    "$(file_json NotebookEdit notebook_path id_ed25519 x)"
  degraded_file deny \
    "$(file_json Write file_path "/etc/ssh/${LONGS}shd_config" x)"
  degraded_file pass "$(file_json Edit file_path /tmp/memory.md \
    'Last connected: 2026-02-25')"
  degraded_file pass \
    "$(file_json Write file_path /home/alice/dev/sdk/n.md x)"
  rm -rf "$SHIM3"
else
  echo "SKIP: file-edit tool checks need jq to build fixtures"
fi

# Every file-edit tool must be registered, and in file mode:
# without the argument the guard would scan the written text as
# a command line.
for TOOL in Edit Write NotebookEdit; do
  if grep -A8 "\"matcher\": *\"[A-Za-z|]*${TOOL}[A-Za-z|]*\"" \
      "$CLAUDE_DIR/settings.json" \
    | grep -q 'guard-taboos\.sh\\" file"'; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: settings.json does not run the guard in file" \
      "mode for $TOOL"
  fi
done

# --- OpenBSD (and the other BSDs' label tools) ------------------
# The same effects through OpenBSD's own tools: disklabel is its
# partition editor, installboot its boot loader writer, doas.conf
# its sudoers, rmuser and "user del" its account deletion, and
# /dev/rsd0c and /dev/wd0c its raw disks. fdisk -l takes a block
# count there, so -l followed by a number is no listing.
check deny 'disklabel -E sd0'
check deny 'disklabel -e sd0'
check deny 'disklabel -w sd0 default'
check deny 'disklabel -Aw sd0'
check deny 'disklabel -R sd0 /root/label.txt'
check deny 'disklabel -n -E sd0'
check deny 'disklabel -T /root/template -w -A sd0'
check deny 'disklabel "-E" sd0'
check deny 'ssh root@h "disklabel -E sd0"'
check deny 'doas disklabel -E sd0'
check deny 'disklabel -i wd0'
check deny 'disklabel -I -w sd0'
check deny 'bsdlabel -w ada0s1'
check deny 'installboot sd0'
check deny 'installboot -v sd0'
check deny 'installboot -p sd0'
check deny 'ssh root@h "installboot -c sd0"'
check deny 'fdisk -iy -l 20000 sd0'
check deny 'fdisk -l 2048 -gy sd0'
check deny 'fdisk -e sd0'
check deny 'echo "permit nopass :wheel" >> /etc/doas.conf'
check deny 'cp /etc/examples/doas.conf /etc/doas.conf'
check deny 'vi /etc/doas.conf'
check deny 'tee /etc/doas.conf < doas.new'
check deny "sed -i 's/^#//' /etc/doas.conf"
check deny 'rm /etc/doas.conf'
check deny 'chmod 644 /etc/doas.conf'
check deny 'ssh root@h "echo permit :wheel > /etc/doas.conf"'
check deny 'perl -e "open(F, q{>>/etc/doas.conf}); print F q{x}"'
check deny 'rmuser alice'
check deny 'ssh root@h "rmuser -y alice"'
check deny 'user del -r alice'
check deny 'group del staff'
check deny 'cat image.raw > /dev/rsd0c'
check deny 'echo x > /dev/wd0c'
check deny 'tee /dev/rwd0c < image.raw'
check pass 'disklabel sd0'
check pass 'disklabel -h sd0'
check pass 'disklabel -p g sd0'
check pass 'disklabel -hv sd0 > /root/label-sd0.txt'
check pass 'ssh root@h "disklabel -h sd0"'
check pass 'disklabel -h sd0 | grep -E "^ +[a-p]:"'
check pass 'installboot -nv sd0'
check pass 'fdisk -l 2>/dev/null'
check pass 'cat /etc/doas.conf'
check pass 'ls -l /etc/doas.conf'
check pass 'doas -C /etc/doas.conf'
check pass 'cat /etc/examples/doas.conf'
check pass 'doas -n true'
check pass 'doas rcctl restart httpd'
check pass 'user info alice'
check pass 'syspatch -c'
check pass 'sysctl hw.disknames'
check pass 'pfctl -nf /etc/pf.conf'
check pass 'rcctl ls on'

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
if grep '"command":.*\.sh' "$SETTINGS" \
  | grep -v 'CLAUDE_PROJECT_DIR' >/dev/null; then
  FAIL=$((FAIL + 1))
  echo "FAIL: settings.json registers a hook script without" \
    '$CLAUDE_PROJECT_DIR (relative path fails open after cd)'
else
  PASS=$((PASS + 1))
fi

echo "guard-taboos tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
