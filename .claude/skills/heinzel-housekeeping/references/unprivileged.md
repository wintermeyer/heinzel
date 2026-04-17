# Unprivileged Mode

When running in unprivileged mode (no sudo, no root SSH), run
every check that works as a regular user and skip those that
require root.

At the end of the report, add a section:

```
### Skipped (needs root)

- Pending security updates (apt-get update)
- Firewall status (ufw requires root)
- SSL certificate files (/etc/letsencrypt/)
```

List each skipped check with a brief reason.
