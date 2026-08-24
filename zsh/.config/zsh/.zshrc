#!/bin/zsh
# dotfiles 管理（stow zsh）。双机共用一份 —— 凡引用外部包/工具的行都带存在性守卫，
# 缺件时静默跳过而非报错刷屏。真相在 ~/dotfiles/zsh/，勿直接改 ~/.config/zsh/.zshrc。

# 提示符的路径段。starship 的 [directory] 只能按「层数」截断，治不了单段名字本身就
# 49 字符的情况（OpenWrt 包名+版本+git hash、buildroot 包目录、rust target triple…）。
# 这里改成按「列数」设硬上限：先砍层数 3→2→1，砍到只剩叶子还超预算，才砍段内保头保尾。
# 纯 zsh 内建、无 fork（实测每次 cd 约 0.04ms），算好导出给 starship 的 env_var 模块读。
# 窄 pane 里嫌长就调 PWD_SHORT_BUDGET。
: ${PWD_SHORT_BUDGET:=56}
_pwd_short() {
  local budget=$PWD_SHORT_BUDGET p=${PWD/#$HOME/\~} out keep
  local -a seg
  if (( ${#p} <= budget )); then export PWD_SHORT=$p; return; fi
  seg=(${(s:/:)p})
  for keep in 3 2 1; do
    (( keep >= $#seg )) && continue
    out="…/${(j:/:)seg[-keep,-1]}"
    (( ${#out} <= budget )) && { export PWD_SHORT=$out; return }
  done
  local leaf=$seg[-1] avail=$(( budget - 2 )) head tail
  head=$(( (avail - 1) * 2 / 3 )); tail=$(( avail - 1 - head ))
  export PWD_SHORT="…/${leaf[1,head]}…${leaf[-tail,-1]}"
}
autoload -Uz add-zsh-hook
add-zsh-hook chpwd _pwd_short
_pwd_short

command -v starship >/dev/null && eval "$(starship init zsh)"

for _p in zsh-autosuggestions zsh-syntax-highlighting; do
  [[ -r /usr/share/zsh/plugins/$_p/$_p.zsh ]] && source /usr/share/zsh/plugins/$_p/$_p.zsh
done
unset _p

autoload -Uz compinit
compinit

# 补全行为（原只在 matebook 上有，并入共用份）
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*' 'l:|=* r:|=*'
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "$HOME/.zsh/cache"

alias ll='ls -l'
alias la='ls -la'
alias p='paru'

export HISTFILE="$HOME/.zsh_history"
export HISTSIZE=100000
export SAVEHIST=100000

# 记录命令的执行时间戳和持续时间
setopt EXTENDED_HISTORY
# 多个终端会话实时共享历史（一个窗口输入的命令，另一个窗口立刻能用上下键找到）
setopt SHARE_HISTORY
setopt INC_APPEND_HISTORY
# 新命令与历史中某条重复时只留最新的，清掉旧的重复项
setopt HIST_IGNORE_ALL_DUPS
# 以空格开头的命令不写历史（输密码/敏感信息前加个空格）
setopt HIST_IGNORE_SPACE
# 存入前移除命令中多余的空白
setopt HIST_REDUCE_BLANKS
# 用 ! 语法（!! / !123）调历史时，只填到命令行不立即执行，方便先看一眼
setopt HIST_VERIFY

autoload -z edit-command-line
zle -N edit-command-line
bindkey "^X^E" edit-command-line

export KSRC=$HOME/workspace/linux/source
export KOUT=$HOME/workspace/linux/out

alias make-arm='make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf-'

command -v zoxide >/dev/null && eval "$(zoxide init zsh)"
[[ -r /usr/share/fzf/completion.zsh ]] && source /usr/share/fzf/completion.zsh
[[ -r /usr/share/fzf/key-bindings.zsh ]] && source /usr/share/fzf/key-bindings.zsh

# fzf 的两个外部依赖也要守卫：rg 缺了会让 fzf 列不出文件，bat 缺了预览窗报错。
# 缺件时退回 fzf 自带行为，而不是配了个跑不动的命令。
command -v rg >/dev/null && export FZF_DEFAULT_COMMAND='rg --files --hidden --follow -g "!.git/"'
FZF_DEFAULT_OPTS="--height 40% --layout=reverse --border"
command -v bat >/dev/null && FZF_DEFAULT_OPTS+=" --preview 'bat --style=numbers --color=always --line-range :500 {}'"
export FZF_DEFAULT_OPTS

# uv 装出来的 PATH 片段（机器相关，缺了不报错）
[[ -r "$HOME/.local/bin/env" ]] && . "$HOME/.local/bin/env"

alias tm='tmux new-session -A -s main'
