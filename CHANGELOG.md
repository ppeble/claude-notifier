# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/ppeble/claude-notifier/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/ppeble/claude-notifier/releases/tag/v0.1.0
