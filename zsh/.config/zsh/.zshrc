#!/bin/zsh
# dotfiles 管理（stow zsh）。双机共用一份 —— 凡引用外部包/工具的行都带存在性守卫，
# 缺件时静默跳过而非报错刷屏。真相在 ~/dotfiles/zsh/，勿直接改 ~/.config/zsh/.zshrc。

command -v starship >/dev/null && eval "$(starship init zsh)"

for _p in zsh-autosuggestions zsh-syntax-highlighting; do
  [[ -r /usr/share/zsh/plugins/$_p/$_p.zsh ]] && source /usr/share/zsh/plugins/$_p/$_p.zsh
done
unset _p

autoload -Uz compinit
compinit

export HISTFILE="$HOME/.zsh_history"
export HISTSIZE=10000
export SAVEHIST=10000

setopt SHARE_HISTORY
setopt INC_APPEND_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE

autoload -z edit-command-line
zle -N edit-command-line
bindkey "^X^E" edit-command-line

export KSRC=$HOME/workspace/linux/source
export KOUT=$HOME/workspace/linux/out

alias make-arm='make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf-'

command -v zoxide >/dev/null && eval "$(zoxide init zsh)"
[[ -r /usr/share/fzf/completion.zsh ]] && source /usr/share/fzf/completion.zsh
[[ -r /usr/share/fzf/key-bindings.zsh ]] && source /usr/share/fzf/key-bindings.zsh

# 使用 rg 作为搜索引擎，忽略 .git
export FZF_DEFAULT_COMMAND='rg --files --hidden --follow -g "!.git/"'
# 预览窗口设置：使用 bat 高亮代码
export FZF_DEFAULT_OPTS="--height 40% --layout=reverse --border --preview 'bat --style=numbers --color=always --line-range :500 {}'"

# uv 装出来的 PATH 片段（机器相关，缺了不报错）
[[ -r "$HOME/.local/bin/env" ]] && . "$HOME/.local/bin/env"

alias tm='tmux new-session -A -s main'
