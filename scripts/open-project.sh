#!/bin/bash
set -ex
# Usage: open-project.sh [dir]  — without a dir, pick one from ~/src with fzf
if [ -n "$1" ]; then
  dir="$1"
else
  dir=$(cd ~; find ./src -maxdepth 2 -type d | fzf --reverse --preview 'cd {}; git branch --show-current') || exit 0
  dir=$(cd ~; realpath -- $dir)
fi
# Inside Rex (not tmux), the layout is the project_layout action in ~/.config/rex/init.lua
if [ -n "$REX_SESSION" ] && [ -z "$TMUX" ]; then
  rex=$(command -v rex || echo "$HOME/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS/rex")
  exec "$rex" do -s "$REX_SESSION" project_layout dir="$dir"
fi
tmux new-window -c "$dir" &&
tmux split-window -h -c "$dir" &&
tmux select-pane -L &&
tmux send-keys 'vi -c "DiffviewOpen origin/main"' Enter &&
tmux select-pane -R &&
tmux split-window -v -c "$dir" &&
tmux select-pane -U &&
tmux send-keys 'claude' Enter
