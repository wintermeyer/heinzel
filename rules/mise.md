# mise — Language Runtime Manager

Rules for installing programming languages on servers
using [mise](https://mise.jdx.dev). This is a cross-distro
rule file — it applies to all distro families.

## When to Use mise

Use mise for **language runtimes** — Node.js, Ruby,
Python, Elixir, Go, Java, etc. Do **not** use mise for
system tools or services (nginx, PostgreSQL, etc.) —
those should come from the distro's package manager.

## Common Pitfalls

- mise must be installed as the SSH user, not root.
  Running `mise use` as root installs runtimes for
  root only.
- The shims PATH setup in `~/.bashrc` must be
  **before** the interactive guard (`case $- in ...`).
  If placed after, `ssh user@host "command"` won't
  find mise-installed binaries.
- After installing a language, always verify over SSH:
  `ssh user@host "node --version"`. If it fails, the
  PATH setup is wrong.
- `mise use --global` sets the default version. Without
  `--global`, it creates a local `.tool-versions` file
  in the current directory.
- For standalone installs, `~/.local/bin` must be in
  PATH for the `mise` binary itself. This is separate
  from the shims directory (`~/.local/share/mise/shims`)
  which provides the language runtime binaries. Both
  must be in PATH.

## Installation

mise is installed as **the SSH user** (not root).

### Default: Standalone Installer (no root)

Always try this first. It works on any Linux distro,
needs no root or sudo, and avoids third-party repos.

```
curl https://mise.run | sh
```

- Installs to `~/.local/bin/mise`
- No root or sudo needed — works in unprivileged mode
- Works on all distro families
- Updates via `mise self-update`
- Requires `curl` (fall back to `wget` if unavailable:
  `wget -qO - https://mise.run | sh`)
- Does **not** modify shell config — the SSH
  Non-Interactive Shell Setup section handles PATH

After installing, add `~/.local/bin` to PATH in
`~/.bashrc` (before the interactive guard) so the
`mise` binary itself is found over SSH. This is
handled in the SSH Non-Interactive Shell Setup section
below.

### Alternative: Distro Package Manager (needs root)

Only use this when the user **explicitly prefers** it
and root access is available. **Ask the user before
adding the repo** — these are third-party repos.

Trade-offs:

- **Pro:** auto-updates via system package manager
- **Con:** requires root, adds a third-party repo,
  `mise self-update` is disabled

#### Debian & Ubuntu

```
apt-get update && apt-get install -y gpg sudo wget curl
wget -qO - https://mise.jdx.dev/gpg-key.pub \
  | gpg --dearmor \
  | tee /etc/apt/keyrings/mise-archive-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/mise-archive-keyring.gpg arch=amd64] https://mise.jdx.dev/deb stable main" \
  | tee /etc/apt/sources.list.d/mise.list
apt-get update && apt-get install -y mise
```

#### RHEL & Fedora

```
dnf install -y dnf-plugins-core
dnf config-manager --add-repo \
  https://mise.jdx.dev/rpm/mise.repo
dnf install -y mise
```

On RHEL 7/CentOS 7, use `yum` instead of `dnf`.

#### SUSE

```
zypper addrepo \
  https://mise.jdx.dev/rpm/mise.repo mise
zypper refresh
zypper install -y mise
```

### Which Method to Use

- **Default:** standalone installer — always try this
  first.
- **Alternative:** distro package — only when the user
  explicitly prefers it and root access is available.
- **Unprivileged mode:** standalone installer is the
  only option (no root for package manager installs).

## SSH Non-Interactive Shell Setup

**This is critical.** All heinzel work runs via
`ssh user@host "command"` — a non-interactive,
non-login shell where `.bashrc` is typically not
sourced.

After installing mise, add both `~/.local/bin` (for the
`mise` binary itself) and the shims directory (for
language runtimes) to `PATH` **at the top of
`~/.bashrc`** — before the interactive guard
(`case $- in ...`). This is the only reliable way to
get mise into `ssh user@host "command"` on
Debian/Ubuntu, because `~/.bash_profile` is **not**
sourced for non-login, non-interactive SSH commands.

```bash
# Insert at the very top of ~/.bashrc
sed -i '1i# mise (before interactive guard)\
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"\
' ~/.bashrc
```

Also create `~/.bash_profile` to source `.bashrc`
for interactive login shells and set XDG_RUNTIME_DIR
(needed for systemd user services over SSH):

```bash
cat > ~/.bash_profile << 'EOF'
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"
export XDG_RUNTIME_DIR=/run/user/$(id -u)

# Source .bashrc for interactive login shells
if [ -n "$BASH_VERSION" ] && [ -f "$HOME/.bashrc" ]; then
    . "$HOME/.bashrc"
fi
EOF
```

**Verify it works:**

```
ssh user@host "mise --version"
ssh user@host "node --version"
```

If neither file is sourced, fall back to:

1. **Explicit PATH prefix** in commands:
   ```
   PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH" node -v
   ```
2. **`mise exec`** to run commands in a mise-managed
   environment:
   ```
   ~/.local/bin/mise exec -- node -v
   ```

## Installing Languages

Install languages **as the SSH user** (not root). Use
`mise use --global` to set a default version:

```
mise use --global node@24
mise use --global ruby@3.3
```

After installing, verify over SSH:

```
ssh user@host "node --version"
ssh user@host "ruby --version"
```

## Server Memory Convention

When mise and languages are installed, add a single
line to the server's `memory.md`:

```
- mise: node@24.1.0, ruby@3.3.7
```

Update this line whenever languages are added, removed,
or upgraded.
