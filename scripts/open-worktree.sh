#!/bin/bash
# Pick a git worktree of $WT_REPO with fzf and open it with open-project.sh
# The tmux server's env may predate nu.env.toml, so fall back to reading it directly
repo="${WT_REPO:-$(nu -c 'open ~/.config/nu.env.toml | get env.WT_REPO? | default ""' 2>/dev/null)}"
repo="${repo/#\~/$HOME}"
if [ -z "$repo" ]; then
  echo "WT_REPO is not set in the env or ~/.config/nu.env.toml"
  read -n 1 -s
  exit 1
fi
dir=$(git -C "$repo" worktree list |
  fzf --reverse --preview 'git -C {1} log --oneline --color=always -n 20; echo; git -C {1} status --short' |
  awk '{print $1}') || exit 0
[ -n "$dir" ] && exec bash ~/.tmux/open-project.sh "$dir"
