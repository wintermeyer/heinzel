# Reading SSH Configuration

Before judging any sshd or ssh setting, find out which
files the program really reads and what the effective
value is. Never assume `sshd_config` and
`sshd_config.d/*.conf` are all there is: `Include` can
pull in any file (on macOS `/etc/ssh/crypto.conf`),
the FreeBSD package and appliances use
`/usr/local/etc/ssh`, and a daemon started with `-f`
reads another file entirely.

**Output case:** since OpenSSH 10.4, `sshd -T` and
`sshd -G` print directive names in mixed case
(`PermitRootLogin`, before `permitrootlogin`). Always
filter their output with `grep -i`, and compare keys
without regard to case.

## sshd (server)

`sshd -G` prints the effective configuration without
loading host keys, so it often runs without root
(OpenSSH 9.3 and newer; some distros keep
`sshd_config` at `0600`). `-dd` adds every file read
(`load_server_config: filename …`). Older OpenSSH has
only `sshd -T`, which needs root. A `-f` on the
running daemon's command line is carried over:

```bash
PATH=$PATH:/usr/sbin:/usr/local/sbin
FOPT=$(ps ax -o args= \
  | sed -n 's/^[^ ]*sshd[: ]\(.* \)\{0,1\}-f \([^ ]*\).*/-f \2/p' \
  | head -n 1)
OUT=$(sshd $FOPT -dd -G 2>&1 || sshd $FOPT -dd -T 2>&1)
F=$(printf '%s\n' "$OUT" | sed -n 's/.*load_server_config: filename //p' \
  | tr -d '\r' | sort -u)
echo "sshd reads:" $F
```

`OUT` then holds the effective values (lines
`<keyword> <value>`) and `F` the files; later probes in
the same call filter `OUT` with `grep -i` instead of
running sshd again. The debug lines end in `\r`, hence
the `tr`.

No `sshd reads:` list (OpenSSH before 9.3 without
root, or files unreadable): read the main file in
`/etc/ssh` or `/usr/local/etc/ssh` and every file its
`Include` lines name. A `Match` block
(`grep -Hi '^[[:space:]]*match' $F`) changes values per
user or address; evaluate it with
`sshd -T -C user=<u>,host=<name>,addr=<ip>` (older
OpenSSH needs all three).

## ssh (client)

`ssh -G <target>` prints the effective client
configuration for that target and exits — it opens no
connection. `-v` adds every file read
(`Reading configuration data …`), the calling
account's `~/.ssh/config` included; `-F <system file>`
shows the system part alone. `Host` and `Match` blocks
differ per target, so use a target the account really
connects to.

Where it runs:

- **The workstation**, as the account heinzel runs
  under — no SSH needed.
- **A server**, for root and every account that
  connects out (backups, rsync, deploys, jump hosts).
  Such accounts have a `.ssh` directory
  (`ls -d /root/.ssh /home/*/.ssh`); bundle them into
  one call:

  ```bash
  for a in root backup; do
    echo "== $a"
    sudo -n -u "$a" ssh -v -G <target> 2>&1 | grep -i \
      -e 'Reading configuration data' \
      -e '^stricthostkeychecking ' -e '^hostname ' \
      -e '^hostkeyalias ' -e '^userknownhostsfile ' \
      -e '^globalknownhostsfile '
  done
  ```

`stricthostkeychecking no`, or a known-hosts file of
`/dev/null`, accepts any host key — the check that
would notice a man in the middle is off. Severities:
`heinzel-security` → `references/ssh.md`.
