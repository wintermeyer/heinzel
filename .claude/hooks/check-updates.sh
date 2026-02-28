#!/bin/sh
# SessionStart hook: check if the repo is behind origin/main.

cd "$CLAUDE_PROJECT_DIR" || exit 0

git fetch --quiet 2>/dev/null || exit 0

LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/main 2>/dev/null) || exit 0

if [ "$LOCAL" = "$REMOTE" ]; then
  exit 0
fi

BEHIND=$(git rev-list --count HEAD..origin/main)

if [ "$BEHIND" -gt 0 ]; then
  cat <<EOF
{"additionalContext":"The heinzel repo is ${BEHIND} commit(s) behind origin/main. Inform the user and suggest running: git pull"}
EOF
fi
