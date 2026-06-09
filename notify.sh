#!/usr/bin/env bash
#
# claude-notifier: send a desktop notification when Claude Code needs you.
#
# Invoked by Claude Code hooks (Notification, Stop, SubagentStop). The hook
# event JSON arrives on stdin. This script parses it, builds a human message,
# auto-detects an available notification backend, and dispatches the alert.
#
# Run `./notify.sh --test` to send a sample notification without a hook.
#
# Environment overrides:
#   CLAUDE_NOTIFIER_BACKEND   Force a backend (notify-send|dunstify|
#                             terminal-notifier|osascript|kdialog|zenity|logger)
#   CLAUDE_NOTIFIER_APPNAME   App name shown by the backend (default "Claude Code")
#   CLAUDE_NOTIFIER_ICON      Icon name or path for backends that support it
#   CLAUDE_NOTIFIER_SOUND     Sound file to play (needs paplay/aplay/afplay)
#   CLAUDE_NOTIFIER_EVENTS    Comma list of events to allow (default: all).
#                             e.g. "Notification" to silence Stop/SubagentStop.

set -uo pipefail

APPNAME="${CLAUDE_NOTIFIER_APPNAME:-Claude Code}"
ICON="${CLAUDE_NOTIFIER_ICON:-dialog-information}"

#-- Read input -----------------------------------------------------------------

INPUT=""
if [ "${1:-}" = "--test" ]; then
  INPUT='{"hook_event_name":"Notification","message":"Claude needs your permission to use Bash","cwd":"'"${PWD}"'"}'
elif [ ! -t 0 ]; then
  INPUT="$(cat)"
fi

#-- Field extraction (jq -> python3 -> naive regex) -----------------------------

field() {
  local key="$1"
  [ -n "$INPUT" ] || { printf ''; return; }
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$INPUT" | jq -r --arg k "$key" '.[$k] // empty' 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$INPUT" | python3 -c '
import sys, json
try:
    print(json.load(sys.stdin).get(sys.argv[1], "") or "")
except Exception:
    pass' "$key" 2>/dev/null
  else
    # Best-effort fallback for simple string values (no escaped quotes).
    printf '%s' "$INPUT" \
      | grep -o "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
      | head -n1 \
      | sed -E "s/.*:[[:space:]]*\"(.*)\"$/\1/"
  fi
}

EVENT="$(field hook_event_name)"
MESSAGE="$(field message)"
CWD="$(field cwd)"
[ -n "$CWD" ] || CWD="$PWD"
PROJECT="$(basename "$CWD" 2>/dev/null || echo "$CWD")"

#-- Event gating ---------------------------------------------------------------

if [ -n "${CLAUDE_NOTIFIER_EVENTS:-}" ] && [ -n "$EVENT" ]; then
  case ",${CLAUDE_NOTIFIER_EVENTS}," in
    *",$EVENT,"*) : ;;
    *) exit 0 ;;
  esac
fi

#-- Build title / body / urgency -----------------------------------------------

case "$EVENT" in
  Notification)
    TITLE="Claude needs you · $PROJECT"
    BODY="${MESSAGE:-Waiting for your input}"
    URGENCY="critical"
    ;;
  Stop)
    TITLE="Claude finished · $PROJECT"
    BODY="${MESSAGE:-Task complete}"
    URGENCY="low"
    ;;
  SubagentStop)
    TITLE="Subagent finished · $PROJECT"
    BODY="${MESSAGE:-Subagent complete}"
    URGENCY="low"
    ;;
  *)
    TITLE="$APPNAME · $PROJECT"
    BODY="${MESSAGE:-${EVENT:-Notification}}"
    URGENCY="normal"
    ;;
esac

#-- Backend detection ----------------------------------------------------------

detect_backend() {
  if [ -n "${CLAUDE_NOTIFIER_BACKEND:-}" ]; then
    printf '%s' "$CLAUDE_NOTIFIER_BACKEND"
    return
  fi
  case "$(uname -s)" in
    Darwin)
      for b in terminal-notifier osascript; do
        command -v "$b" >/dev/null 2>&1 && { printf '%s' "$b"; return; }
      done
      ;;
    *)
      for b in notify-send dunstify kdialog zenity; do
        command -v "$b" >/dev/null 2>&1 && { printf '%s' "$b"; return; }
      done
      ;;
  esac
  printf 'logger'
}

BACKEND="$(detect_backend)"

#-- Sound (optional) -----------------------------------------------------------

play_sound() {
  local snd="${CLAUDE_NOTIFIER_SOUND:-}"
  [ -n "$snd" ] && [ -f "$snd" ] || return 0
  for player in paplay afplay aplay; do
    if command -v "$player" >/dev/null 2>&1; then
      "$player" "$snd" >/dev/null 2>&1 &
      return 0
    fi
  done
}

#-- Dispatch -------------------------------------------------------------------

send() {
  case "$BACKEND" in
    notify-send)
      notify-send -a "$APPNAME" -u "$URGENCY" -i "$ICON" -- "$TITLE" "$BODY"
      ;;
    dunstify)
      # Replace prior notifications from this app (stable id keeps it tidy).
      dunstify -a "$APPNAME" -u "$URGENCY" -i "$ICON" -r 7373 -- "$TITLE" "$BODY"
      ;;
    terminal-notifier)
      # -group lets a later notification replace an earlier one. No -sender:
      # a non-installed bundle id can make terminal-notifier silently no-op.
      terminal-notifier -title "$TITLE" -message "$BODY" -group claude-notifier
      ;;
    osascript)
      # Escape double quotes and backslashes for AppleScript string literals.
      local t b
      t="$(printf '%s' "$TITLE" | sed 's/\\/\\\\/g; s/"/\\"/g')"
      b="$(printf '%s' "$BODY"  | sed 's/\\/\\\\/g; s/"/\\"/g')"
      osascript -e "display notification \"$b\" with title \"$t\""
      ;;
    kdialog)
      kdialog --title "$TITLE" --passivepopup "$BODY" 10
      ;;
    zenity)
      zenity --notification --text="$TITLE"$'\n'"$BODY"
      ;;
    logger|*)
      if command -v logger >/dev/null 2>&1; then
        logger -t claude-notifier "$TITLE: $BODY"
      fi
      printf '[claude-notifier] %s: %s\n' "$TITLE" "$BODY" >&2
      ;;
  esac
}

send
play_sound
exit 0
