#!/usr/bin/env bash
# Claude Code statusline - best practices configuration
# Based on PS1: [\u@\h \W]\$

input=$(cat)

# --- Core identity (from PS1) ---
user=$(whoami)
# Arch 默认不装 `hostname`(在 inetutils 里)——用 coreutils 的 uname -n，双机都在。
host=$(uname -n)
dir=$(echo "$input" | jq -r '.workspace.current_dir')
dir_name=$(basename "$dir")

# --- Model ---
model=$(echo "$input" | jq -r '.model.display_name // empty')

# --- Context window ---
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
if [ -n "$used_pct" ]; then
    used_int=$(printf '%.0f' "$used_pct")
    if [ "$used_int" -ge 80 ]; then
        ctx_str="ctx:${used_int}%!"
    else
        ctx_str="ctx:${used_int}%"
    fi
else
    ctx_str=""
fi

# --- Git repo (skip optional locks for speed) ---
repo=$(echo "$input" | jq -r '.workspace.repo | if . then .owner + "/" + .name else empty end')
git_worktree=$(echo "$input" | jq -r '.workspace.git_worktree // empty')

git_str=""
if [ -n "$repo" ]; then
    git_str="$repo"
    if [ -n "$git_worktree" ]; then
        git_str="$git_str@$git_worktree"
    fi
fi

# --- PR badge ---
pr_num=$(echo "$input" | jq -r '.pr.number // empty')
pr_str=""
if [ -n "$pr_num" ]; then
    pr_state=$(echo "$input" | jq -r '.pr.review_state // "open"')
    pr_str="PR#${pr_num}(${pr_state})"
fi

# --- Rate limits (Claude.ai subscribers only) ---
five_h=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
seven_d=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
rate_str=""
if [ -n "$five_h" ]; then
    rate_str="5h:$(printf '%.0f' "$five_h")%"
fi
if [ -n "$seven_d" ]; then
    [ -n "$rate_str" ] && rate_str="$rate_str "
    rate_str="${rate_str}7d:$(printf '%.0f' "$seven_d")%"
fi

# --- Assemble parts ---
# Left side: [user@host dir]
left=$(printf '[%s@%s %s]' "$user" "$host" "$dir_name")

# Right side: collect non-empty segments
parts=()
[ -n "$model" ]    && parts+=("$model")
[ -n "$git_str" ]  && parts+=("$git_str")
[ -n "$pr_str" ]   && parts+=("$pr_str")
[ -n "$ctx_str" ]  && parts+=("$ctx_str")
[ -n "$rate_str" ] && parts+=("$rate_str")

# Join right parts with " | "
right=""
for part in "${parts[@]}"; do
    if [ -z "$right" ]; then
        right="$part"
    else
        right="$right | $part"
    fi
done

if [ -n "$right" ]; then
    printf '%s  %s' "$left" "$right"
else
    printf '%s' "$left"
fi
