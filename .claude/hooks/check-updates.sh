#!/bin/sh
# SessionStart hook: auto-pull latest changes.

cd "$CLAUDE_PROJECT_DIR" || exit 0

OUTPUT=$(git pull --quiet 2>&1) || exit 0

# If something changed, tell Claude so it knows.
if [ -n "$OUTPUT" ]; then
  echo "heinzel repo updated: $OUTPUT"
fi
