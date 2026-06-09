# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2026-06-09

### Added
- Per-event notifications with distinct copy and sound, dispatched by an
  event-key argument the installer wires onto each hook:
  - `Stop` -> `stop`: "✅ Task completed successfully" (Glass)
  - `Notification` / `permission_prompt` -> `permission`: "🔐 Permission needed
    to continue" (Funk)
  - `Notification` / `elicitation_dialog` -> `elicitation`: "✏️ Waiting for your
    input" (Funk)
  - `PreToolUse` / `AskUserQuestion` -> `question`: "❓ Claude has a question for
    you" (Funk)
  - `SubagentStop` -> `subagent`: "Subagent finished" (Glass)
- Notification titles now carry session context (`project · short-session-id`)
  so concurrent Claude Code sessions are tellable apart.
- macOS backends (`osascript`, `terminal-notifier`) play a per-event system
  sound (Glass for "done", Funk for "needs you"); `CLAUDE_NOTIFIER_SOUND` still
  overrides with a sound file on any platform.

### Changed
- `install.sh` now wires five matchers (splitting `Notification` into
  `permission_prompt` / `elicitation_dialog` and adding `PreToolUse` /
  `AskUserQuestion`) instead of three coarse events. Re-running it migrates an
  older install in place.
- `notify.sh` selects its message from the event-key argument; when called with
  no argument it falls back to deriving the key from the stdin `hook_event_name`,
  so legacy wiring keeps working.
- `CLAUDE_NOTIFIER_EVENTS` accepts the new event keys (`stop`, `permission`,
  `elicitation`, `question`, `subagent`) as well as the legacy hook names.

## [0.2.0] - 2026-06-09

### Added
- CI now enforces a version bump on every pull request: `VERSION` must increase
  (semver) and `CHANGELOG.md` must contain a matching `## [X.Y.Z]` entry. Wired
  in as a required, strict status check on `main`.

### Changed
- Versioning model is now continuous: every merged change advances `VERSION` and
  adds a changelog entry, rather than accumulating under an `Unreleased` heading.
  `CONTRIBUTING.md` updated accordingly.

## [0.1.0] - 2026-06-09

### Added
- Desktop notifications for Claude Code via system-native tooling, triggered by
  the `Notification`, `Stop`, and `SubagentStop` hooks.
- `notify.sh`: reads the hook event JSON on stdin, builds a message, auto-detects
  a notification backend, and dispatches the alert. JSON parsing falls back
  through `jq`, `python3`, then a minimal regex parser, so the script itself has
  no hard dependency.
- Multi-backend support with auto-detection: `notify-send`, `dunstify`,
  `kdialog`, `zenity` on Linux; `terminal-notifier` and `osascript` (AppleScript,
  built in) on macOS; a `logger` fallback otherwise.
- Configuration via environment variables: `CLAUDE_NOTIFIER_BACKEND`,
  `CLAUDE_NOTIFIER_APPNAME`, `CLAUDE_NOTIFIER_ICON`, `CLAUDE_NOTIFIER_SOUND`,
  `CLAUDE_NOTIFIER_EVENTS`.
- `install.sh`: merges hooks into Claude Code `settings.json` with `jq`. Prompts
  for user-wide vs per-project scope when no scope flag is given, is idempotent,
  and backs up settings before each change. Flags: `--user`, `--project`,
  `--no-stop`, `--no-subagent`, `--dry-run`.
- `uninstall.sh`: removes the notifier's hooks and prunes empty event arrays.
- `update.sh`: version-aware self-update. Defaults to the latest released tag,
  accepts a specific version, supports `--edge` for the latest `main`, and
  `--list` to show available versions.
- `notify.sh --test` to send a sample notification.
- Documentation (`README.md`) and MIT license.

[0.3.0]: https://github.com/ppeble/claude-notifier/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/ppeble/claude-notifier/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/ppeble/claude-notifier/releases/tag/v0.1.0
