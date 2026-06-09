#!/usr/bin/env bash
#
# Wire claude-notifier into Claude Code's settings.json hooks.
#
# Usage:
#   ./install.sh [--user|--project] [--no-stop] [--no-subagent] [--dry-run]
#
#   With no scope flag, prompts interactively (user vs project); falls back to
#   --user when there is no terminal to prompt at.
#
#   --user      Install into ~/.claude/settings.json
#   --project   Install into ./.claude/settings.json (current repo)
#   --no-stop       Skip the Stop hook (no "finished" notifications)
#   --no-subagent   Skip the SubagentStop hook
#   --dry-run   Print the resulting settings without writing

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NOTIFY="$SCRIPT_DIR/notify.sh"

SCOPE="user"
SCOPE_SET=0
WANT_STOP=1
WANT_SUBAGENT=1
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --user) SCOPE="user"; SCOPE_SET=1 ;;
    --project) SCOPE="project"; SCOPE_SET=1 ;;
    --no-stop) WANT_STOP=0 ;;
    --no-subagent) WANT_SUBAGENT=0 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required to safely merge settings.json." >&2
  if [ "$(uname -s)" = "Darwin" ]; then
    echo "Install it (e.g. 'brew install jq') and re-run." >&2
  else
    echo "Install it (e.g. 'sudo apt install jq') and re-run." >&2
  fi
  exit 1
fi

if [ ! -f "$NOTIFY" ]; then
  echo "Error: notify.sh not found at $NOTIFY" >&2
  exit 1
fi
chmod +x "$NOTIFY"

# If scope wasn't given on the command line, ask. Fall back to the --user
# default when there's no terminal to prompt at (e.g. piped/CI installs).
if [ "$SCOPE_SET" -eq 0 ]; then
  if [ -t 0 ] && [ -t 1 ]; then
    echo "Where should claude-notifier be installed?"
    echo "  1) User    ~/.claude/settings.json        (all your projects)"
    echo "  2) Project $(pwd)/.claude/settings.json   (this directory only)"
    while true; do
      printf 'Choose [1/2] (default 1): '
      read -r reply || reply=""
      case "$reply" in
        ""|1|u|user|User)       SCOPE="user"; break ;;
        2|p|project|Project)    SCOPE="project"; break ;;
        *) echo "Please answer 1 (user) or 2 (project)." ;;
      esac
    done
  else
    echo "No scope specified and no terminal to prompt; defaulting to --user." >&2
  fi
fi

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

# Each event is wired with its own key so notify.sh can give it distinct copy
# and sound. Notification splits into permission/elicitation by matcher, and
# AskUserQuestion rides PreToolUse.
TRIPLES="$(jq -n --arg n "$NOTIFY" '
  [ { event: "Notification", matcher: "permission_prompt",  cmd: ($n + " permission") },
    { event: "Notification", matcher: "elicitation_dialog", cmd: ($n + " elicitation") },
    { event: "PreToolUse",   matcher: "AskUserQuestion",    cmd: ($n + " question") },
    { event: "Stop",         matcher: null,                 cmd: ($n + " stop") },
    { event: "SubagentStop", matcher: null,                 cmd: ($n + " subagent") } ]')"

[ "$WANT_STOP" -eq 1 ] || TRIPLES="$(printf '%s' "$TRIPLES" | jq 'map(select(.event != "Stop"))')"
[ "$WANT_SUBAGENT" -eq 1 ] || TRIPLES="$(printf '%s' "$TRIPLES" | jq 'map(select(.event != "SubagentStop"))')"

# Merge: first drop any existing group that runs our script (with or without a
# key, so old installs migrate cleanly), once per touched event, then append a
# fresh group per matcher. Idempotent.
UPDATED="$(jq \
  --arg notify "$NOTIFY" \
  --argjson triples "$TRIPLES" '
  def clean(ev):
    (.hooks[ev] // [])
      | map(select((.hooks // [])
          | any(.command == $notify or (.command | startswith($notify + " "))) | not));
  def group(m; cmd):
    (if m == null then { hooks: [ { type: "command", command: cmd } ] }
     else { matcher: m, hooks: [ { type: "command", command: cmd } ] } end);
  .hooks = (.hooks // {})
  | reduce ($triples | map(.event) | unique)[] as $ev (.; .hooks[$ev] = clean($ev))
  | reduce $triples[] as $t (.;
      .hooks[$t.event] = ((.hooks[$t.event] // []) + [group($t.matcher; $t.cmd)]))
' "$SETTINGS")"

if [ "$DRY_RUN" -eq 1 ]; then
  echo "# Would write to $SETTINGS:"
  printf '%s\n' "$UPDATED"
  exit 0
fi

cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"
printf '%s\n' "$UPDATED" > "$SETTINGS"

echo "Installed claude-notifier hooks into $SETTINGS"
printf '%s' "$TRIPLES" | jq -r '.[]
  | "  - " + .event
    + (if .matcher then " [" + .matcher + "]" else "" end)
    + " -> " + .cmd'
echo "  Backup:  $SETTINGS.bak.*"
echo
echo "Test it now:  $NOTIFY --test"
