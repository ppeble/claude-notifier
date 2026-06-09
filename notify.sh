#!/usr/bin/env bash
#
# claude-notifier: send a desktop notification when Claude Code needs you.
#
# Invoked by Claude Code hooks. The installer wires each hook to this script
# with an event-key argument so every event gets distinct copy and sound:
#
#   Stop                              -> notify.sh stop         ✅ Task completed
#   Notification / permission_prompt  -> notify.sh permission   🔐 Permission needed
#   Notification / elicitation_dialog -> notify.sh elicitation  ✏️ Waiting for input
#   PreToolUse  / AskUserQuestion     -> notify.sh question     ❓ Has a question
#
# The hook event JSON still arrives on stdin; it is used for session context
# (project dir + short session id) so concurrent sessions are tellable apart.
# When called with no event key (e.g. a legacy install), the key is derived
# from the stdin `hook_event_name` field, so older wiring keeps working.
#
# Run `./notify.sh --test [event-key]` to send a sample notification.
#
# Environment overrides:
#   CLAUDE_NOTIFIER_BACKEND   Force a backend (notify-send|dunstify|
#                             terminal-notifier|osascript|kdialog|zenity|logger)
#   CLAUDE_NOTIFIER_APPNAME   App name shown by the backend (default "Claude Code")
#   CLAUDE_NOTIFIER_ICON      Icon name or path for backends that support it
#   CLAUDE_NOTIFIER_SOUND     Sound file to play (needs paplay/aplay/afplay).
#                             Overrides the per-event macOS system sound.
#   CLAUDE_NOTIFIER_EVENTS    Comma list of events to allow (default: all).
#                             Accepts event keys (stop,permission,elicitation,
#                             question) and/or hook names (Stop,
#                             Notification). e.g. "permission,question".

set -uo pipefail

APPNAME="${CLAUDE_NOTIFIER_APPNAME:-Claude Code}"
ICON="${CLAUDE_NOTIFIER_ICON:-dialog-information}"

#-- Parse the event key / --test -----------------------------------------------

KEY=""
TEST=0
if [ "${1:-}" = "--test" ]; then
  TEST=1
  KEY="${2:-permission}"
elif [ -n "${1:-}" ] && [ "${1#-}" = "$1" ]; then
  # First arg is a bare word: treat it as the event key.
  KEY="$1"
fi

#-- Read input -----------------------------------------------------------------

INPUT=""
if [ "$TEST" -eq 1 ]; then
  INPUT='{"hook_event_name":"Notification","message":"Sample notification","cwd":"'"${PWD}"'","session_id":"test1234abcd"}'
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
SESSION_ID="$(field session_id)"
SHORT_ID=""
[ -n "$SESSION_ID" ] && SHORT_ID="$(printf '%s' "$SESSION_ID" | cut -c1-8)"

#-- Derive the event key from the hook name when none was passed ---------------

if [ -z "$KEY" ]; then
  case "$EVENT" in
    Stop)         KEY="stop" ;;
    PreToolUse)   KEY="question" ;;
    Notification) KEY="notification" ;;
    *)            KEY="notification" ;;
  esac
fi

# Subagent completion is intentionally silent: it double-pinged alongside the
# main Stop notification, so the SubagentStop hook was dropped. Stay quiet for
# any legacy install still wired to call us with it before re-running install.sh.
case "$KEY" in
  subagent) exit 0 ;;
esac
[ "$EVENT" = "SubagentStop" ] && exit 0

#-- Event gating ---------------------------------------------------------------
# Allow a token that matches either the resolved key or the raw hook name, so
# both new (key) and legacy (hook-name) CLAUDE_NOTIFIER_EVENTS values work.

if [ -n "${CLAUDE_NOTIFIER_EVENTS:-}" ]; then
  allowed=0
  case ",${CLAUDE_NOTIFIER_EVENTS}," in
    *",$KEY,"*) allowed=1 ;;
  esac
  if [ -n "$EVENT" ]; then
    case ",${CLAUDE_NOTIFIER_EVENTS}," in
      *",$EVENT,"*) allowed=1 ;;
    esac
  fi
  [ "$allowed" -eq 1 ] || exit 0
fi

#-- Build title / body / urgency / sound ---------------------------------------
# Distinct copy per event mirrors the Glass/Funk split: Glass on the "done"
# events, Funk on the "needs you" events so they sound different by ear.

SOUND_NAME=""
case "$KEY" in
  stop)
    BODY="✅ Task completed successfully"
    URGENCY="low"
    SOUND_NAME="Glass"
    ;;
  permission)
    BODY="🔐 Permission needed to continue"
    URGENCY="critical"
    SOUND_NAME="Funk"
    ;;
  elicitation)
    BODY="✏️ Waiting for your input"
    URGENCY="critical"
    SOUND_NAME="Funk"
    ;;
  question)
    BODY="❓ Claude has a question for you"
    URGENCY="critical"
    SOUND_NAME="Funk"
    ;;
  notification|*)
    BODY="${MESSAGE:-Waiting for your input}"
    URGENCY="critical"
    SOUND_NAME="Funk"
    ;;
esac

# Title carries session context so concurrent sessions are tellable apart.
TITLE="$APPNAME · $PROJECT"
[ -n "$SHORT_ID" ] && TITLE="$TITLE · $SHORT_ID"

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
# A configured CLAUDE_NOTIFIER_SOUND file plays via paplay/afplay/aplay on any
# platform; the per-event macOS system sound is handled inline by the macOS
# backends below.

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
      if [ -n "$SOUND_NAME" ]; then
        terminal-notifier -title "$TITLE" -message "$BODY" -group claude-notifier -sound "$SOUND_NAME"
      else
        terminal-notifier -title "$TITLE" -message "$BODY" -group claude-notifier
      fi
      ;;
    osascript)
      # Escape double quotes and backslashes for AppleScript string literals.
      local t b
      t="$(printf '%s' "$TITLE" | sed 's/\\/\\\\/g; s/"/\\"/g')"
      b="$(printf '%s' "$BODY"  | sed 's/\\/\\\\/g; s/"/\\"/g')"
      if [ -n "$SOUND_NAME" ]; then
        osascript -e "display notification \"$b\" with title \"$t\" sound name \"$SOUND_NAME\""
      else
        osascript -e "display notification \"$b\" with title \"$t\""
      fi
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
