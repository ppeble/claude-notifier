# claude-notifier

Desktop notifications for [Claude Code](https://claude.com/claude-code) on Linux
(and macOS), using your system's native notification tooling. Get a popup the
moment Claude needs your input, finishes a task, or a subagent completes, so you
don't have to babysit the terminal.

No runtime dependencies beyond a notification backend you almost certainly
already have. `jq` is used by the installer to edit `settings.json` safely.

## Quick start

Clone the repo somewhere permanent, install once, and update whenever you like.
Run every command from the cloned directory:

```sh
git clone https://github.com/ppeble/claude-notifier.git
cd claude-notifier

./install.sh        # install: wire the hooks into Claude Code
./update.sh         # update:  pull the latest, no reinstall needed
```

The installer points Claude Code at `notify.sh` using this directory's absolute
path, so **keep the clone where it is** and run `./update.sh` from inside it to
upgrade. The path never changes, so updates take effect with no reinstall. (If
you move or re-clone the directory, run `./install.sh` again to re-point it.)

## How it works

Claude Code fires [hooks](https://docs.claude.com/en/docs/claude-code/hooks) at
key moments and passes event JSON on stdin. The installer wires each hook to
`notify.sh` with an event key, so every event gets its own message (and, on
macOS, its own system sound). `notify.sh` reads the JSON for session context,
then sends the alert through an auto-detected backend.

| Hook event / matcher                | Key          | Message                          | Urgency  | Sound |
|--------------------------------------|--------------|----------------------------------|----------|-------|
| `Notification` / `permission_prompt` | `permission` | 🔐 Permission needed to continue | critical | Funk  |
| `Notification` / `elicitation_dialog`| `elicitation`| ✏️ Waiting for your input         | critical | Funk  |
| `PreToolUse` / `AskUserQuestion`     | `question`   | ❓ Claude has a question for you  | critical | Funk  |
| `Stop`                               | `stop`       | ✅ Task completed successfully    | low      | Glass |
| `SubagentStop`                       | `subagent`   | Subagent finished                | low      | Glass |

The notification title carries session context (`Claude Code · project ·
session-id`) so several concurrent sessions are tellable apart. The macOS
system sound applies to the `osascript` and `terminal-notifier` backends;
set `CLAUDE_NOTIFIER_SOUND` to a file to override it on any platform.

## Supported backends

Auto-detected in this order (first match wins):

- **Linux:** `notify-send`, `dunstify`, `kdialog`, `zenity`
- **macOS:** `terminal-notifier`, `osascript` (built in)
- **Fallback:** `logger` + stderr

Force one with `CLAUDE_NOTIFIER_BACKEND`.

### macOS notes

- `osascript` is built into macOS, so notifications work with **no extra
  install**. The installer still needs `jq` (`brew install jq`).
- For a nicer experience (custom app icon, notification grouping/replacement),
  install [`terminal-notifier`](https://github.com/julienXX/terminal-notifier)
  (`brew install terminal-notifier`); it's auto-detected and preferred.
- With the `osascript` backend, macOS attributes the notification to the calling
  app (e.g. your terminal or "Script Editor"). Make sure that app is allowed to
  send notifications in **System Settings → Notifications**, and that Do Not
  Disturb / Focus isn't suppressing it.

## Install

```sh
./install.sh            # asks: user-wide or this project only?
./notify.sh --test      # verify a notification appears
```

Run with no scope flag and the installer asks whether to install **user-wide**
(`~/.claude/settings.json`, all your projects) or **per-project**
(`./.claude/settings.json`, this directory only). Pass `--user` or `--project`
to skip the prompt; when there's no terminal (CI, piped install) it defaults to
`--user`.

Installer options:

```sh
./install.sh --user          # user-wide, no prompt
./install.sh --project       # this project's ./.claude/settings.json, no prompt
./install.sh --no-stop       # skip "Claude finished" notifications
./install.sh --no-subagent   # skip subagent notifications
./install.sh --dry-run       # preview the merged settings, write nothing
```

The installer is idempotent and backs up `settings.json` before each change.
Restart any running Claude Code sessions to pick up the new hooks.

> **Tip:** `Stop` fires at the end of *every* response, which can be chatty in an
> interactive session. Use `--no-stop` if you only want to be alerted when Claude
> is actually blocked on you.

## Uninstall

```sh
./uninstall.sh           # remove from ~/.claude/settings.json
./uninstall.sh --project # remove from ./.claude/settings.json
```

## Update

Updating is version-aware. With no arguments it moves you to the latest released
version; you can also pin a specific version or follow the bleeding edge:

```sh
./update.sh             # latest released version (newest vX.Y.Z tag)
./update.sh 0.2.0       # a specific version (0.2.0 or v0.2.0 both work)
./update.sh --edge      # latest commit on main (may be unreleased)
./update.sh --list      # show available released versions
```

It auto-stashes any local edits, refreshes the executable bits, and prints what
changed. Since the hooks reference `notify.sh` by absolute path, **you don't need
to reinstall** after updating unless you want to change which events are wired
(then re-run `./install.sh`).

## Versioning

This project uses [Semantic Versioning](https://semver.org/). Each release is a
git tag `vX.Y.Z`, mirrored by the [`VERSION`](VERSION) file, with changes recorded
in [`CHANGELOG.md`](CHANGELOG.md). `update.sh` resolves updates against these tags,
so "the latest version" always means the newest tagged release, not whatever
happens to be on `main`. See [CONTRIBUTING.md](CONTRIBUTING.md) for the release
process.

## Configuration

`notify.sh` honors these environment variables (set them in your shell profile,
or inline in the hook command):

| Variable                  | Purpose                                              |
|---------------------------|------------------------------------------------------|
| `CLAUDE_NOTIFIER_BACKEND` | Force a backend instead of auto-detecting            |
| `CLAUDE_NOTIFIER_APPNAME` | App name shown by the backend (default `Claude Code`)|
| `CLAUDE_NOTIFIER_ICON`    | Icon name or path (default `dialog-information`)      |
| `CLAUDE_NOTIFIER_SOUND`   | Sound file to play; overrides the per-event macOS sound |
| `CLAUDE_NOTIFIER_EVENTS`  | Comma list of events to allow, e.g. `permission,question` |

`CLAUDE_NOTIFIER_EVENTS` accepts the event keys (`stop`, `permission`,
`elicitation`, `question`, `subagent`) and/or the hook names (`Stop`,
`Notification`, `SubagentStop`); anything not listed is silenced.

## Manual hook setup

If you'd rather wire it up yourself, add this to `settings.json`. Each hook
passes `notify.sh` the matching event key:

```json
{
  "hooks": {
    "Notification": [
      { "matcher": "permission_prompt",  "hooks": [ { "type": "command", "command": "/abs/path/to/notify.sh permission" } ] },
      { "matcher": "elicitation_dialog", "hooks": [ { "type": "command", "command": "/abs/path/to/notify.sh elicitation" } ] }
    ],
    "PreToolUse": [
      { "matcher": "AskUserQuestion", "hooks": [ { "type": "command", "command": "/abs/path/to/notify.sh question" } ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "command", "command": "/abs/path/to/notify.sh stop" } ] }
    ],
    "SubagentStop": [
      { "hooks": [ { "type": "command", "command": "/abs/path/to/notify.sh subagent" } ] }
    ]
  }
}
```

## License

MIT. See [LICENSE](LICENSE).
