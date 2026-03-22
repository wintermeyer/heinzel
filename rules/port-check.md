# Port Conflict Check

Before starting or deploying any application or
service that binds to a network port, check whether
that port is already in use. **This check is
mandatory — do not skip it.**

## When to Check

- Deploying a web application (Rails, Phoenix, etc.)
- Installing or starting a network-facing service
- Changing a service's listen port
- Creating a systemd/rc unit that binds a port

## Prefer Unix Sockets Over TCP Ports

When the application sits behind a reverse proxy
such as nginx, **recommend a Unix socket** instead
of a TCP port. Unix sockets are faster (no TCP
overhead) and eliminate port conflicts entirely.

Examples:

- **Ruby on Rails (Puma):**
  `bundle exec puma -b unix:///run/myapp/puma.sock`
- **Phoenix Framework:**
  Configure the endpoint with
  `server: true, http: [ip: {:local, "/run/myapp/phoenix.sock"}]`
  (requires Bandit or Cowboy socket support).
- **Node.js / Express:**
  `app.listen('/run/myapp/node.sock')`

The nginx upstream then uses:

```nginx
upstream myapp {
    server unix:/run/myapp/puma.sock;
}
```

**Socket file permissions:** ensure the web server
user (e.g. `www-data`, `www`, `nginx`) can read
and write the socket. A common approach:

```bash
chmod 660 /run/myapp/puma.sock
chown deploy:www-data /run/myapp/puma.sock
```

If the application supports sockets and is proxied,
suggest sockets first. Only fall back to a TCP port
when sockets are not practical (e.g. the app must
be reachable directly, or the framework lacks
socket support).

## Check Commands

Run the appropriate command for the detected OS.
Replace `<port>` with the target port number.

### Linux

```bash
ss -tulnp | grep :<port>
```

The `-p` flag requires root to show process names.
Unprivileged fallback:

```bash
ss -tuln | grep :<port>
```

### FreeBSD

```bash
sockstat -4 -6 -l | grep :<port>
```

No root needed. Shows user, command, PID, protocol,
and local address.

### macOS

```bash
lsof -iTCP:<port> -sTCP:LISTEN -P -n
```

Shows command, PID, and user. Use `sudo` to see
processes owned by other users.

## If the Port Is Occupied

1. **Never kill or stop the occupying process
   without explicit user approval.**
2. Report to the user:
   - Process name and PID
   - User running the process
   - Full bind address (e.g. `127.0.0.1:3000`
     vs `0.0.0.0:3000`)
3. Present options:
   - **(a)** Stop the existing service first.
   - **(b)** Change the new application's port.
   - **(c)** Switch to a Unix socket (if proxied).
   - **(d)** Abort.
4. If the occupying process is the **same
   application** being redeployed (same binary or
   service name), note this — a restart rather than
   a fresh start may be appropriate. Still confirm
   with the user.

## If the Port Is Free

Proceed with the deployment. No action needed
beyond logging.

## Server Memory

After a service is successfully started and
listening, update
`memory/servers/<hostname>/memory.md` with:

```markdown
- <App name>: port <N> (<tcp/udp>, <bind address>)
```

Or for socket-based setups:

```markdown
- <App name>: unix socket /run/myapp/puma.sock
```

If the port or socket path changes, update the
existing entry. If the service is removed, remove
the entry.

## Changelog

Log the port binding per `rules/changelog.md`:

```bash
logger -t heinzel \
  "Started <app> on port <N> (<bind address>)"
```

Or for sockets:

```bash
logger -t heinzel \
  "Started <app> on unix:/run/myapp/puma.sock"
```
