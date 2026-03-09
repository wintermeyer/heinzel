# Copying Directories Between Servers

When copying a directory tree from one server to
another (rsync, scp, tar, etc.), always check for
symlinks that point outside the copied tree:

```
find /path/to/copied/dir -type l \
  -exec readlink -f {} \; \
  | grep -v '^/path/to/copied/dir' \
  | sort -u
```

If any symlinks point to paths outside the directory,
their targets must also be copied.

Before marking a directory copy as complete, verify
on the destination:

```
find /path/to/copied/dir -xtype l
```

This lists broken symlinks. If any exist, investigate
and copy the missing targets.
