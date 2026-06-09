# Contributing

Thanks for your interest in improving claude-notifier. It is a small, dependency-light
set of shell scripts, so the bar is mostly: keep it portable and keep it simple.

## Development workflow

1. Fork or branch off `main`.
2. Make your change. Match the existing style: POSIX-friendly bash, quoted
   expansions, no bashisms that break on macOS bash 3.2 (no associative arrays,
   no `mapfile`, no `${var,,}`).
3. Run the checks locally (see below).
4. **Bump the version.** Every change must raise `VERSION` (at least a patch
   bump) and add a matching `## [X.Y.Z] - YYYY-MM-DD` section to `CHANGELOG.md`.
   CI enforces this; a PR that does not bump the version (or omits the changelog
   entry) cannot merge.
5. Open a pull request against `main`.

`main` is protected: changes land through pull requests, CI must pass (ShellCheck
plus the version-bump check), history is kept linear (rebase, do not merge-commit),
and force-pushes to `main` are blocked. Admins may override in emergencies.

Because the version-bump check is strict (your branch must be up to date with
`main` before merging), if another PR lands first you may need to rebase and pick
the next version number.

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
[Keep a Changelog](https://keepachangelog.com/). Versioning is explicit and
continuous: **every merged change advances `VERSION`** and records a matching
`## [X.Y.Z]` entry in `CHANGELOG.md`. Pick the bump that fits the change:

- patch (`0.1.0` -> `0.1.1`) for fixes and docs,
- minor (`0.1.1` -> `0.2.0`) for new, backward-compatible features,
- major (`0.2.0` -> `1.0.0`) for breaking changes.

So each PR includes, alongside its code:

1. `VERSION` raised to the new `X.Y.Z`.
2. A new `## [X.Y.Z] - YYYY-MM-DD` section in `CHANGELOG.md` describing the change
   (and the compare links at the bottom updated).

### Tagging a release

`VERSION` always reflects the current code, but `update.sh` offers users the
latest released **tag**. To publish the current `VERSION` as a release that
`./update.sh` will hand out:

```sh
git tag -a "v$(tr -d '[:space:]' < VERSION)" -m "v$(tr -d '[:space:]' < VERSION)"
git push origin "v$(tr -d '[:space:]' < VERSION)"
```

A CI check guards that any pushed `vX.Y.Z` tag matches the `VERSION` file.
