#!/usr/bin/env bash
# PreToolUse(Bash) hook: block bare `pip install` / `python -m pip install`,
# steering toward uv. Allows `uv pip ...` and anything else.
# Blocks by exiting 2 with a message on stderr.

raw=$(cat)

# 缺 jq 时不能静默放行——那等于这道闸门在没装 jq 的机器上默默失效。
# 退化方案:直接扫原始 JSON。范围略宽(命令外的字段若含 pip install 也会中),
# 但代价只是多拦一次并给出提示,方向是 fail closed。
if command -v jq >/dev/null 2>&1; then
  cmd=$(printf '%s' "$raw" | jq -r '.tool_input.command // ""')
else
  cmd=$raw
fi

# Does the command invoke a bare pip install (incl. `python -m pip install`)?
if printf '%s' "$cmd" | grep -Eq '(^|[;&|`(]|[[:space:]])(pip3?|python3?[[:space:]]+-m[[:space:]]+pip)[[:space:]]+install'; then
  # `uv pip install` is fine — uv is managing it.
  if printf '%s' "$cmd" | grep -Eq '\buv[[:space:]]+pip[[:space:]]'; then
    exit 0
  fi
  echo "Blocked: bare 'pip install' pollutes the system Python environment." >&2
  echo "Use uv instead:" >&2
  echo "  - One-off task:   uv run --with <pkg> [--with <pkg>...] script.py" >&2
  echo "  - In a project:   uv add <pkg>" >&2
  echo "  - uv's own pip:   uv pip install <pkg>   (if you really need pip semantics)" >&2
  exit 2
fi

exit 0
