# mise — Language Runtime Manager

Rules for installing programming languages on servers
using [mise](https://mise.jdx.dev). This is a cross-distro
rule file — it applies to all distro families.

## When to Use mise

Use mise for **language runtimes** — Node.js, Ruby,
Python, Elixir, Go, Java, etc. Do **not** use mise for
system tools or services (nginx, PostgreSQL, etc.) —
those should come from the distro's package manager.

## Installation

mise is installed as **the SSH user** (not root). The
installation method varies by distro family.

### Alpine

mise is in the official Alpine repos — no third-party
source needed:

```
apk add mise
```

### Debian & Ubuntu

mise provides an apt repository. **Ask the user before
adding it** — this is a third-party repo that requires
adding a GPG key and apt source.

```
apt-get update && apt-get install -y gpg sudo wget curl
wget -qO - https://mise.jdx.dev/gpg-key.pub \
  | gpg --dearmor \
  | tee /etc/apt/keyrings/mise-archive-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/mise-archive-keyring.gpg arch=amd64] https://mise.jdx.dev/deb stable main" \
  | tee /etc/apt/sources.list.d/mise.list
apt-get update && apt-get install -y mise
```

### RHEL & Fedora

mise provides a COPR/rpm repository. **Ask the user
before adding it** — this is a third-party repo.

```
dnf install -y dnf-plugins-core
dnf config-manager --add-repo \
  https://mise.jdx.dev/rpm/mise.repo
dnf install -y mise
```

On RHEL 7/CentOS 7, use `yum` instead of `dnf`.

### SUSE

mise provides an rpm repository. **Ask the user before
adding it** — this is a third-party repo.

```
zypper addrepo \
  https://mise.jdx.dev/rpm/mise.repo mise
zypper refresh
zypper install -y mise
```

## SSH Non-Interactive Shell Setup

**This is critical.** All heinzel work runs via
`ssh user@host "command"` — a non-interactive,
non-login shell where `.bashrc` is typically not
sourced.

After installing mise, add the shims directory to
`PATH` **at the top of `~/.bashrc`** — before the
interactive guard (`case $- in ...`). This is the
only reliable way to get mise shims into
`ssh user@host "command"` on Debian/Ubuntu, because
`~/.bash_profile` is **not** sourced for non-login,
non-interactive SSH commands.

```bash
# Insert at the very top of ~/.bashrc
sed -i '1i# mise shims (before interactive guard)\
export PATH="$HOME/.local/share/mise/shims:$PATH"\
' ~/.bashrc
```

Also create `~/.bash_profile` to source `.bashrc`
for interactive login shells and set XDG_RUNTIME_DIR
(needed for systemd user services over SSH):

```bash
cat > ~/.bash_profile << 'EOF'
export PATH="$HOME/.local/share/mise/shims:$PATH"
export XDG_RUNTIME_DIR=/run/user/$(id -u)

# Source .bashrc for interactive login shells
if [ -n "$BASH_VERSION" ] && [ -f "$HOME/.bashrc" ]; then
    . "$HOME/.bashrc"
fi
EOF
```

**Verify it works:**

```
ssh user@host "node --version"
```

If neither file is sourced, fall back to:

1. **Explicit PATH prefix** in commands:
   ```
   PATH="$HOME/.local/share/mise/shims:$PATH" node -v
   ```
2. **`mise exec`** to run commands in a mise-managed
   environment:
   ```
   mise exec -- node -v
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
