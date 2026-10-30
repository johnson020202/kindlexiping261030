#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h}"
cd "$ROOT"
if command -v codex >/dev/null 2>&1; then
  exec codex -C "$ROOT" "$(cat AI_BOOTSTRAP.md)"
elif command -v claude >/dev/null 2>&1; then
  exec claude "$(cat AI_BOOTSTRAP.md)"
else
  echo "未找到 codex 或 claude CLI。请先安装并登录其中一个。"
  echo "Codex: https://github.com/openai/codex"
  read -r "?按回车关闭…"
fi
