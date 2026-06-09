#!/usr/bin/env bash
#
# Wire claude-notifier into Claude Code's settings.json hooks.
#
# Usage:
#   ./install.sh [--user|--project] [--no-stop] [--no-subagent] [--dry-run]
#
#   --user      Install into ~/.claude/settings.json (default)
#   --project   Install into ./.claude/settings.json (current repo)
#   --no-stop       Skip the Stop hook (no "finished" notifications)
#   --no-subagent   Skip the SubagentStop hook
#   --dry-run   Print the resulting settings without writing

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NOTIFY="$SCRIPT_DIR/notify.sh"

SCOPE="user"
WANT_STOP=1
WANT_SUBAGENT=1
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --user) SCOPE="user" ;;
    --project) SCOPE="project" ;;
    --no-stop) WANT_STOP=0 ;;
    --no-subagent) WANT_SUBAGENT=0 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required to safely merge settings.json." >&2
  echo "Install it (e.g. 'sudo apt install jq') and re-run." >&2
  exit 1
fi

if [ ! -f "$NOTIFY" ]; then
  echo "Error: notify.sh not found at $NOTIFY" >&2
  exit 1
fi
chmod +x "$NOTIFY"

if [ "$SCOPE" = "project" ]; then
  SETTINGS_DIR="$(pwd)/.claude"
else
  SETTINGS_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
fi
SETTINGS="$SETTINGS_DIR/settings.json"

mkdir -p "$SETTINGS_DIR"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

if ! jq empty "$SETTINGS" >/dev/null 2>&1; then
  echo "Error: $SETTINGS is not valid JSON. Aborting." >&2
  exit 1
fi

# Build the list of events to install.
EVENTS=(Notification)
[ "$WANT_STOP" -eq 1 ] && EVENTS+=(Stop)
[ "$WANT_SUBAGENT" -eq 1 ] && EVENTS+=(SubagentStop)
EVENTS_JSON="$(printf '%s\n' "${EVENTS[@]}" | jq -R . | jq -s .)"

# Merge: for each requested event, drop any existing group that already runs
# our command (idempotent), then append a fresh group.
UPDATED="$(jq \
  --arg cmd "$NOTIFY" \
  --argjson events "$EVENTS_JSON" '
  def ensure(ev):
    .hooks[ev] = (((.hooks[ev] // [])
      | map(select((.hooks // []) | any(.command == $cmd) | not)))
      + [{ hooks: [ { type: "command", command: $cmd } ] }]);
  .hooks = (.hooks // {})
  | reduce $events[] as $e (.; ensure($e))
' "$SETTINGS")"

if [ "$DRY_RUN" -eq 1 ]; then
  echo "# Would write to $SETTINGS:"
  printf '%s\n' "$UPDATED"
  exit 0
fi

cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"
printf '%s\n' "$UPDATED" > "$SETTINGS"

echo "Installed claude-notifier hooks into $SETTINGS"
echo "  Events: ${EVENTS[*]}"
echo "  Command: $NOTIFY"
echo "  Backup:  $SETTINGS.bak.*"
echo
echo "Test it now:  $NOTIFY --test"
