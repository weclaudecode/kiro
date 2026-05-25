#!/usr/bin/env bash
# Install the kiro headless git hooks into a target repo by copying them into
# <repo>/.githooks/ and pointing core.hooksPath there. Because .githooks/ is
# tracked in the repo, the whole team (and future-you on a new machine) gets the
# hooks automatically — unlike .git/hooks/, which is never tracked.
#
#   install-hooks.sh                 # install into the current repo
#   install-hooks.sh ~/code/my-repo  # install into a specific repo
#   install-hooks.sh --print         # print the hook source dir and exit
#
# Bypass any installed hook for one command with:  KIRO_SKIP=1 git commit ...
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/githooks" && pwd)"

if [ "${1:-}" = "--print" ]; then
  echo "$SRC"
  exit 0
fi

TARGET="${1:-$PWD}"
cd "$TARGET"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not a git repo: $TARGET" >&2; exit 1; }
ROOT="$(git rev-parse --show-toplevel)"

mkdir -p "$ROOT/.githooks"
cp "$SRC"/* "$ROOT/.githooks/"
chmod +x "$ROOT"/.githooks/*
git -C "$ROOT" config core.hooksPath .githooks

echo "installed hooks into $ROOT/.githooks and set core.hooksPath=.githooks"
echo "next: review them, then commit .githooks/ so your team gets them"
echo "bypass any hook for one command with: KIRO_SKIP=1 git commit ..."
