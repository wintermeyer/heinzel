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
