# claude-notifier

Desktop notifications for [Claude Code](https://claude.com/claude-code) on Linux
(and macOS), using your system's native notification tooling. Get a popup the
moment Claude needs your input, finishes a task, or a subagent completes, so you
don't have to babysit the terminal.

No runtime dependencies beyond a notification backend you almost certainly
already have. `jq` is used by the installer to edit `settings.json` safely.

## How it works

Claude Code fires [hooks](https://docs.claude.com/en/docs/claude-code/hooks) at
key moments and passes event JSON on stdin. `notify.sh` reads that JSON, builds a
message, auto-detects a notification backend, and sends the alert.

| Hook event    | When it fires                              | Urgency  |
|---------------|--------------------------------------------|----------|
| `Notification`| Claude needs permission or is idle waiting | critical |
| `Stop`        | Claude finishes responding                 | low      |
| `SubagentStop`| A spawned subagent finishes                | low      |

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
git clone <this-repo> claude-notifier
cd claude-notifier
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

Pull the latest version with one command:

```sh
./update.sh
```

It fetches the newest commits, rebases any local changes on top (auto-stashing
uncommitted work), and refreshes the executable bits. Since the hooks reference
`notify.sh` by absolute path, **you don't need to reinstall** after updating
unless you want to change which events are wired (then re-run `./install.sh`).

Prefer doing it by hand? `git pull --rebase` from the repo does the same thing.

## Configuration

`notify.sh` honors these environment variables (set them in your shell profile,
or inline in the hook command):

| Variable                  | Purpose                                              |
|---------------------------|------------------------------------------------------|
| `CLAUDE_NOTIFIER_BACKEND` | Force a backend instead of auto-detecting            |
| `CLAUDE_NOTIFIER_APPNAME` | App name shown by the backend (default `Claude Code`)|
| `CLAUDE_NOTIFIER_ICON`    | Icon name or path (default `dialog-information`)      |
| `CLAUDE_NOTIFIER_SOUND`   | Sound file to play (needs `paplay`/`aplay`/`afplay`) |
| `CLAUDE_NOTIFIER_EVENTS`  | Comma list of events to allow, e.g. `Notification`   |

## Manual hook setup

If you'd rather wire it up yourself, add this to `settings.json`:

```json
{
  "hooks": {
    "Notification": [
      { "hooks": [ { "type": "command", "command": "/abs/path/to/notify.sh" } ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "command", "command": "/abs/path/to/notify.sh" } ] }
    ],
    "SubagentStop": [
      { "hooks": [ { "type": "command", "command": "/abs/path/to/notify.sh" } ] }
    ]
  }
}
```

## License

MIT. See [LICENSE](LICENSE).
