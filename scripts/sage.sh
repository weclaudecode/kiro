# sage.sh — Gruvbox Material Dark ("Claude — Sage") palette + git prompt for bash
# ----------------------------------------------------------------------------
# Install on a RHEL / Linux box:
#   1. Copy this file to ~/.sage.sh
#   2. Append to ~/.bashrc:
#         [ -f ~/.sage.sh ] && source ~/.sage.sh
#   3. Open a new shell.
#
# Terminal palette is applied via OSC escape sequences. This works in:
#   xterm, alacritty, kitty, wezterm, foot, st, mlterm, Konsole (mostly),
#   and through tmux/screen (passthrough required — see note below).
#
# GNOME Terminal — the default on RHEL Workstation — IGNORES OSC 4.
# For GNOME Terminal, open Preferences → your profile → Colors and paste:
#
#   Background:  #282828        Foreground:  #d4be98        Cursor:  #d4be98
#   Palette (Built-in schemes → Custom):
#     0  #32302f   black           8  #45403d   bright black
#     1  #ea6962   red             9  #ea6962   bright red
#     2  #a9b665   green          10  #a9b665   bright green
#     3  #d8a657   yellow         11  #d8a657   bright yellow
#     4  #7daea3   blue           12  #7daea3   bright blue
#     5  #d3869b   magenta        13  #d3869b   bright magenta
#     6  #89b482   cyan           14  #89b482   bright cyan
#     7  #d4be98   white          15  #d4be98   bright white
#
# For tmux palette passthrough, add to ~/.tmux.conf:
#     set -g default-terminal "tmux-256color"
#     set -ga terminal-overrides ",*256col*:Tc"
#     set -g allow-passthrough on
# ----------------------------------------------------------------------------

# --- 1. Apply the Sage palette via OSC ---------------------------------------
if [[ -t 1 ]]; then
  _sage_osc() {
    if [[ -n $TMUX ]]; then
      printf '\ePtmux;\e\e]%s\a\e\\' "$1"
    elif [[ ${TERM%%-*} == screen ]]; then
      printf '\eP\e]%s\a\e\\' "$1"
    else
      printf '\e]%s\a' "$1"
    fi
  }

  _sage_osc '4;0;#32302f'   # ANSI 0  black
  _sage_osc '4;1;#ea6962'   # ANSI 1  red
  _sage_osc '4;2;#a9b665'   # ANSI 2  green
  _sage_osc '4;3;#d8a657'   # ANSI 3  yellow
  _sage_osc '4;4;#7daea3'   # ANSI 4  blue
  _sage_osc '4;5;#d3869b'   # ANSI 5  magenta
  _sage_osc '4;6;#89b482'   # ANSI 6  cyan
  _sage_osc '4;7;#d4be98'   # ANSI 7  white / foreground
  _sage_osc '4;8;#45403d'   # ANSI 8  bright black (selection)
  _sage_osc '4;9;#ea6962'
  _sage_osc '4;10;#a9b665'
  _sage_osc '4;11;#d8a657'
  _sage_osc '4;12;#7daea3'
  _sage_osc '4;13;#d3869b'
  _sage_osc '4;14;#89b482'
  _sage_osc '4;15;#d4be98'
  _sage_osc '10;#d4be98'    # default foreground
  _sage_osc '11;#282828'    # default background
  _sage_osc '12;#d4be98'    # cursor
  unset -f _sage_osc
fi

# --- 2. Git-aware prompt -----------------------------------------------------
# Status indicators shown after the branch name:
#   +   staged changes              *   unstaged changes
#   %   untracked files             $   stash entries exist
#   ↑N  commits ahead of upstream   ↓N  commits behind upstream
# Branch colour: green=clean, yellow=dirty, red=detached HEAD.

_sage_git_ps1() {
  git rev-parse --is-inside-work-tree &>/dev/null || return 0

  local branch detached=0 dirty=0 staged=0 untracked=0 stashed=0
  local ahead=0 behind=0 line x y upstream counts

  if branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null); then
    :
  else
    branch=$(git rev-parse --short HEAD 2>/dev/null) || return 0
    detached=1
  fi

  while IFS= read -r line; do
    [[ -z $line ]] && continue
    x=${line:0:1}; y=${line:1:1}
    if [[ $x == '?' && $y == '?' ]]; then
      untracked=1
    else
      [[ $x != ' ' ]] && staged=1
      [[ $y != ' ' ]] && dirty=1
    fi
  done < <(git status --porcelain=v1 2>/dev/null)

  git rev-parse --verify --quiet refs/stash >/dev/null 2>&1 && stashed=1

  upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)
  if [[ -n $upstream ]]; then
    counts=$(git rev-list --left-right --count "HEAD...$upstream" 2>/dev/null)
    if [[ -n $counts ]]; then
      ahead=${counts%%[[:space:]]*}
      behind=${counts##*[[:space:]]}
    fi
  fi

  # Non-printing markers \001 / \002 are the raw bytes for \[ \].
  # readline needs them around colour codes to measure prompt width.
  local _on=$'\001' _off=$'\002'
  local c_dim="${_on}"$'\e[38;5;8m'"${_off}"
  local c_reset="${_on}"$'\e[0m'"${_off}"
  local c_branch="${_on}"$'\e[38;5;2m'"${_off}"          # green = clean
  (( dirty || staged || untracked )) && c_branch="${_on}"$'\e[38;5;3m'"${_off}"
  (( detached ))                     && c_branch="${_on}"$'\e[38;5;1m'"${_off}"

  local marks=''
  (( staged ))    && marks+='+'
  (( dirty ))     && marks+='*'
  (( untracked )) && marks+='%'
  (( stashed ))   && marks+='$'

  local sync=''
  (( ahead ))  && sync+="↑${ahead}"
  (( behind )) && sync+="↓${behind}"

  local body="${c_branch}${branch}${c_dim}"
  [[ -n $marks ]] && body+=" ${marks}"
  [[ -n $sync  ]] && body+=" ${sync}"

  printf ' %s(%s%s)%s' "${c_dim}" "${body}" "${c_dim}" "${c_reset}"
}

# Sage prompt: cyan user@host, yellow cwd, dim git block, fg-coloured $
PS1='\[\e[38;5;6m\]\u@\h\[\e[0m\] \[\e[38;5;3m\]\w\[\e[0m\]$(_sage_git_ps1)\n\[\e[38;5;7m\]\$\[\e[0m\] '

# Coloured ls + grep, matching the Sage palette.
if command -v dircolors >/dev/null 2>&1; then
  eval "$(dircolors -b 2>/dev/null)"
fi
alias ls='ls --color=auto'
alias ll='ls -lah --color=auto'
alias grep='grep --color=auto'
