#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
cd "$ROOT"
PROMPT="$(cat AI_BOOTSTRAP.md)"
if [ "$#" -gt 0 ]; then PROMPT="$PROMPT

当前任务：
$*"; fi
if command -v codex >/dev/null 2>&1; then
  exec codex -C "$ROOT" "$PROMPT"
elif command -v claude >/dev/null 2>&1; then
  exec claude "$PROMPT"
else
  echo "未找到 codex 或 claude CLI。" >&2
  exit 1
fi
