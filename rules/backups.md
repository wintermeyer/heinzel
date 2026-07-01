# Backups Before Modifying Config Files

Before editing any config file, back it up:

```
BACKUP_DIR="/var/backups/heinzel"
mkdir -p "$BACKUP_DIR"
cp /etc/some/config.conf \
  "$BACKUP_DIR/config.conf.$(date +%Y%m%d-%H%M%S)"
# Clean backups older than 30 days
find "$BACKUP_DIR" -type f -mtime +30 -delete
```

In unprivileged mode, use `~/.heinzel-backups/` for
user-owned files. System config files cannot be
edited — defer those to the sysadmin report.

## Never back up in place inside drop-in directories

Several Linux config systems read **every** file in a
directory and parse them. A backup left next to the
original gets parsed too, often with a warning at best
and broken behaviour at worst.

Affected paths include (but are not limited to):

- `/etc/apt/apt.conf.d/`
- `/etc/apt/sources.list.d/`
- `/etc/cron.d/`
- `/etc/systemd/system/*.d/`
- `/etc/ssh/sshd_config.d/`
- `/etc/sudoers.d/`
- `/etc/nginx/conf.d/`, `sites-enabled/`,
  `modules-enabled/`
- `/etc/logrotate.d/`
- `/etc/profile.d/`

When editing a file in one of those directories, write
the backup to `/var/backups/heinzel/` only. Never leave
it in the source directory, not even with a `.bak` or
timestamped suffix:

- `apt` logs daily warnings about
  `50unattended-upgrades.bak.YYYYMMDD` files (invalid
  filename extension) and silently ignores them.
- `sshd` refuses to start with stray files in
  `sshd_config.d/`.
- A forgotten `/etc/sudoers.d/old.bak` can rescind
  privileges silently if its parser pass fails.

If a session uncovers an existing in-place backup in
one of those directories, move it to
`/var/backups/heinzel/` rather than leaving it where
it is.

## Verify cross-backups at the receiver, not the source

A cross-backup (host A's dumps copied to host B) is only
real when the dump **files** exist and are intact **on
the receiver**. A running pull job, a present cron line,
or a directory that looks populated prove nothing. When
asked whether a host holds a copy, go look on that host:
list the actual `*.sql.gz` (or equivalent), confirm the
newest matches the source's newest, and run an integrity
check (`gzip -t`, or the tool's own verify). "The job is
scheduled" is not "the data is there."

**Silent-failure gotcha — out-of-jail symlinks.** A
common pattern exposes dumps for pulling via a symlink in
the puller's reach, e.g. `outbox/dbbackup ->
/var/lib/dbbackup`, where the target is **outside** an
`rrsync -ro <dir>` jail. A plain `rsync -a` pull copies
that symlink **verbatim**: on the receiver it becomes a
dangling (or misleading) symlink and **zero data
transfers — with no error and no warning email**. The
pull must pass `--copy-unsafe-links` so the *sender*
follows the link and ships the real files. If one source
in a mesh works and another doesn't, diff their pull
commands for this flag first.

**Dry-run must be verbose.** To preview what a pull would
transfer, use `rsync -n -v`. A bare `rsync -n` lists
nothing and reads as "0 files would transfer", which
will mislead you into the wrong conclusion. Confirm by
grepping the `-nv` output for the specific files you
expect (e.g. the database name).
