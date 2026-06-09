# Contributing

Thanks for your interest in improving claude-notifier. It is a small, dependency-light
set of shell scripts, so the bar is mostly: keep it portable and keep it simple.

## Development workflow

1. Fork or branch off `main`.
2. Make your change. Match the existing style: POSIX-friendly bash, quoted
   expansions, no bashisms that break on macOS bash 3.2 (no associative arrays,
   no `mapfile`, no `${var,,}`).
3. Run the checks locally (see below).
4. Update `CHANGELOG.md` under `[Unreleased]`.
5. Open a pull request against `main`.

`main` is protected: changes land through pull requests, history is kept linear
(rebase, do not merge-commit), and force-pushes to `main` are blocked.

## Local checks

CI runs [ShellCheck](https://www.shellcheck.net/) and a syntax pass on every
script. Run the same checks before pushing:

```sh
shellcheck notify.sh install.sh uninstall.sh update.sh
for f in *.sh; do bash -n "$f"; done
```

Smoke-test the notifier and the installer without touching real settings:

```sh
./notify.sh --test
./install.sh --dry-run
echo '{"hook_event_name":"Stop","cwd":"'"$PWD"'"}' | ./notify.sh
```

## Adding a notification backend

Backends live in two places in `notify.sh`: detection in `detect_backend` and
dispatch in `send`. Add the command to the appropriate detection list (keep the
preference order sensible per platform) and add a matching `case` arm in `send`.
Keep the title/body/urgency contract identical across backends.

## Versioning and releases

This project follows [Semantic Versioning](https://semver.org/) and
[Keep a Changelog](https://keepachangelog.com/). Versioning is explicit: the
`VERSION` file and a matching `vX.Y.Z` git tag are the source of truth, and
`update.sh` resolves updates against those tags.

Cutting a release (maintainers):

1. Move the `[Unreleased]` entries in `CHANGELOG.md` under a new
   `[X.Y.Z] - YYYY-MM-DD` heading and update the compare links at the bottom.
2. Set `VERSION` to `X.Y.Z`.
3. Commit (`Release vX.Y.Z`), then tag and push:
   ```sh
   git tag -a vX.Y.Z -m "vX.Y.Z"
   git push origin main --follow-tags
   ```

`update.sh` (no arguments) will then offer this version as the latest release to
all users.
