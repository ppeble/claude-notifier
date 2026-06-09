#!/usr/bin/env bash
#
# Update claude-notifier from GitHub, by version.
#
# Usage:
#   ./update.sh                 Update to the latest released version (newest tag)
#   ./update.sh <version>       Update to a specific version, e.g. 0.2.0 or v0.2.0
#   ./update.sh --edge          Update to the latest commit on main (may be unreleased)
#   ./update.sh --list          List the available released versions
#
# Releases are git tags of the form vX.Y.Z; the VERSION file mirrors the current
# tag. Because the hooks point at notify.sh by absolute path, no reinstall is
# needed after an update unless you want to change which events are wired (then
# re-run ./install.sh).

set -euo pipefail

REPO_URL="https://github.com/ppeble/claude-notifier"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

usage() { sed -n '4,12p' "$0" | sed 's/^# \{0,1\}//'; }

TARGET_KIND="latest"   # latest | edge | version
TARGET_VERSION=""
DO_LIST=0

while [ $# -gt 0 ]; do
  case "$1" in
    --edge|--main) TARGET_KIND="edge" ;;
    --latest)      TARGET_KIND="latest" ;;
    --list)        DO_LIST=1 ;;
    -h|--help)     usage; exit 0 ;;
    -*)            echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    *)             TARGET_KIND="version"; TARGET_VERSION="$1" ;;
  esac
  shift
done

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Error: $SCRIPT_DIR is not a git checkout; can't self-update." >&2
  echo "Re-clone from $REPO_URL instead." >&2
  exit 1
fi

git fetch --tags --force --prune --quiet origin

list_versions() { git tag -l 'v*' --sort=-v:refname; }

if [ "$DO_LIST" -eq 1 ]; then
  echo "Available versions:"
  list_versions | sed 's/^/  /'
  exit 0
fi

current_version() {
  if [ -f VERSION ]; then tr -d '[:space:]' < VERSION; else echo "unknown"; fi
}

# Resolve the requested target into a git ref plus a human label.
case "$TARGET_KIND" in
  edge)
    TARGET_REF="origin/main"
    LABEL="latest main (edge)"
    ;;
  version)
    case "$TARGET_VERSION" in v*) TAG="$TARGET_VERSION" ;; *) TAG="v$TARGET_VERSION" ;; esac
    if ! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
      echo "Error: version $TAG not found. Available versions:" >&2
      list_versions | sed 's/^/  /' >&2
      exit 1
    fi
    TARGET_REF="$TAG"
    LABEL="$TAG"
    ;;
  latest|*)
    TAG="$(list_versions | head -n1)"
    if [ -z "$TAG" ]; then
      TARGET_REF="origin/main"
      LABEL="latest main (no release tags yet)"
    else
      TARGET_REF="$TAG"
      LABEL="$TAG (latest release)"
    fi
    ;;
esac

BEFORE="$(git rev-parse HEAD)"
TARGET_SHA="$(git rev-parse "${TARGET_REF}^{commit}")"
OLD_VERSION="$(current_version)"

if [ "$BEFORE" = "$TARGET_SHA" ]; then
  echo "Already at $LABEL (version $OLD_VERSION)."
  exit 0
fi

# Best-effort autostash so local edits don't block the checkout.
STASHED=0
if ! git diff --quiet || ! git diff --cached --quiet; then
  if git stash push --quiet --include-untracked -m "claude-notifier update autostash"; then
    STASHED=1
  fi
fi

echo "Updating ($OLD_VERSION) -> $LABEL ..."
if [ "$TARGET_KIND" = "edge" ]; then
  git checkout --quiet main 2>/dev/null || git checkout --quiet -B main origin/main
  git merge --ff-only --quiet origin/main
else
  # Detaches HEAD at the release tag; fine for an install directory.
  git checkout --quiet "$TARGET_REF"
fi

if [ "$STASHED" -eq 1 ]; then
  git stash pop --quiet \
    || echo "Note: stashed local changes could not be reapplied; see 'git stash list'." >&2
fi

chmod +x notify.sh install.sh uninstall.sh update.sh 2>/dev/null || true

NEW_VERSION="$(current_version)"
echo "Now at version $NEW_VERSION ($(git rev-parse --short HEAD))."
if git merge-base --is-ancestor "$BEFORE" HEAD 2>/dev/null; then
  echo "Changes:"
  git --no-pager log --oneline "$BEFORE..HEAD" | sed 's/^/  /'
else
  echo "(switched to a different version line)"
fi
