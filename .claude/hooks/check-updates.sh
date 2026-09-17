#!/bin/sh
# SessionStart hook: auto-pull latest heinzel changes
# with version awareness and pinning support. Also
# runs bin/heinzel-migrate after every pull, which
# migrates old user state and creates local
# directories new versions need.

if [ -n "$CLAUDE_PROJECT_DIR" ] && [ -d "$CLAUDE_PROJECT_DIR" ]; then
  cd "$CLAUDE_PROJECT_DIR" || exit 0
fi

# Never hang the SessionStart hook on a credential
# prompt (HTTPS remote with expired token, etc.).
# Fail fast instead and let the user fix it.
export GIT_TERMINAL_PROMPT=0
GIT_ASKPASS=${GIT_ASKPASS:-true}
export GIT_ASKPASS

# Migration is implemented in bin/heinzel-migrate so
# both the Claude Code hook and bin/heinzel-update
# use the same logic.
run_migration() {
  [ -f bin/heinzel-migrate ] && sh bin/heinzel-migrate
}

# Opt-out via environment variable.
if [ "$HEINZEL_NO_UPDATE" = "1" ]; then
  echo "heinzel auto-update disabled (HEINZEL_NO_UPDATE=1)"
  exit 0
fi

# Skip if not on the main branch (user pinned to a
# version tag or is on a custom branch).
BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null)
if [ $? -ne 0 ]; then
  # Detached HEAD — likely pinned to a tag.
  TAG=$(git describe --tags --exact-match 2>/dev/null)
  if [ -n "$TAG" ]; then
    echo "heinzel pinned to $TAG — skipping auto-update"
  else
    echo "heinzel on detached HEAD — skipping auto-update"
  fi
  exit 0
fi

if [ "$BRANCH" != "main" ]; then
  echo "heinzel on branch '$BRANCH' — skipping auto-update"
  exit 0
fi

# Remember current version before pulling.
OLD_VERSION=""
if [ -f VERSION ]; then
  OLD_VERSION=$(cat VERSION)
fi

# Pull latest changes. --ff-only: a diverged local
# main should fail loudly here, never produce a
# silent merge commit.
OUTPUT=$(git pull --ff-only --quiet 2>&1)
PULL_STATUS=$?

if [ $PULL_STATUS -ne 0 ]; then
  echo "heinzel auto-update failed: $OUTPUT"
  echo "Likely causes: local changes, local commits on a"
  echo "diverged main, or no network. Run 'git status' to"
  echo "inspect."
  exit 0
fi

# Migrate 1.x → 2.0 layout if needed. Idempotent
# and silent when there's nothing to do.
run_migration

# Read new version after pulling.
NEW_VERSION=""
if [ -f VERSION ]; then
  NEW_VERSION=$(cat VERSION)
fi

# Report what happened.
if [ -z "$OUTPUT" ] && [ "$OLD_VERSION" = "$NEW_VERSION" ]; then
  # Nothing changed — stay quiet.
  exit 0
fi

if [ "$OLD_VERSION" != "$NEW_VERSION" ] \
   && [ -n "$OLD_VERSION" ] \
   && [ -n "$NEW_VERSION" ]; then
  echo "heinzel updated: $OLD_VERSION -> $NEW_VERSION"

  # Extract changelog section for the new version.
  if [ -f CHANGELOG.md ]; then
    # Print lines between "## $NEW_VERSION" and the
    # next "## " heading (or end of file). Compare
    # the whole second field so "## 2.8.0" does not
    # also match "## 2.8.0-rc1".
    awk -v ver="$NEW_VERSION" '
      /^## / { if (insec) exit; insec = ($2 == ver); next }
      insec && NF { print }
    ' CHANGELOG.md
  fi

  # Warn on major version change.
  OLD_MAJOR=$(echo "$OLD_VERSION" | cut -d. -f1)
  NEW_MAJOR=$(echo "$NEW_VERSION" | cut -d. -f1)
  if [ "$OLD_MAJOR" != "$NEW_MAJOR" ]; then
    echo ""
    echo "BREAKING CHANGES — read CHANGELOG.md"
  fi
elif [ -n "$OUTPUT" ]; then
  echo "heinzel repo updated: $OUTPUT"
fi
