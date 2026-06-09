#!/usr/bin/env bash
#
# Update claude-notifier to the latest version from GitHub.
#
# Pulls the latest commits (rebasing local work on top, auto-stashing any
# uncommitted changes) and re-asserts executable bits. Because the hooks point
# at notify.sh by absolute path, no reinstall is needed after an update unless
# you want to change which events are wired (then re-run ./install.sh).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Error: $SCRIPT_DIR is not a git checkout; can't self-update." >&2
  echo "Re-clone from https://github.com/ppeble/claude-notifier instead." >&2
  exit 1
fi

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
BEFORE="$(git rev-parse HEAD)"

echo "Updating claude-notifier ($BRANCH)..."
git pull --rebase --autostash --quiet

AFTER="$(git rev-parse HEAD)"
chmod +x notify.sh install.sh uninstall.sh update.sh 2>/dev/null || true

if [ "$BEFORE" = "$AFTER" ]; then
  echo "Already up to date."
else
  echo "Updated $(git rev-parse --short "$BEFORE")..$(git rev-parse --short "$AFTER")"
  echo "Changes:"
  git --no-pager log --oneline "$BEFORE..$AFTER"
fi
