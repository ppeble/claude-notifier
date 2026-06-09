#!/usr/bin/env bash
#
# Remove claude-notifier hooks from Claude Code's settings.json.
#
# Usage:
#   ./uninstall.sh [--user|--project] [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NOTIFY="$SCRIPT_DIR/notify.sh"

SCOPE="user"
DRY_RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --user) SCOPE="user" ;;
    --project) SCOPE="project" ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) sed -n '2,7p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required." >&2
  exit 1
fi

if [ "$SCOPE" = "project" ]; then
  SETTINGS="$(pwd)/.claude/settings.json"
else
  SETTINGS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
fi

if [ ! -f "$SETTINGS" ]; then
  echo "Nothing to do: $SETTINGS does not exist."
  exit 0
fi

# Remove any hook group that runs our script (with or without an event key);
# drop now-empty event arrays.
UPDATED="$(jq --arg cmd "$NOTIFY" '
  if .hooks then
    .hooks |= ( to_entries
      | map(.value |= map(select((.hooks // [])
          | any(.command == $cmd or (.command | startswith($cmd + " "))) | not)))
      | map(select((.value | length) > 0))
      | from_entries )
  else . end
' "$SETTINGS")"

if [ "$DRY_RUN" -eq 1 ]; then
  echo "# Would write to $SETTINGS:"
  printf '%s\n' "$UPDATED"
  exit 0
fi

cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"
printf '%s\n' "$UPDATED" > "$SETTINGS"
echo "Removed claude-notifier hooks from $SETTINGS"
