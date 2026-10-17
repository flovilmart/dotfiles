#!/bin/bash
set -ex
# Usage: open-project.sh [dir]  — without a dir, pick one from ~/src with fzf
if [ -n "$1" ]; then
  dir="$1"
else
  dir=$(cd ~; find ./src -maxdepth 2 -type d | fzf --reverse --preview 'cd {}; git branch --show-current') || exit 0
  dir=$(cd ~; realpath -- $dir)
fi
tmux new-window -c "$dir" &&
tmux split-window -h -c "$dir" &&
tmux select-pane -L &&
tmux send-keys 'vi -c "DiffviewOpen origin/main"' Enter &&
tmux select-pane -R &&
tmux split-window -v -c "$dir" &&
tmux select-pane -U &&
tmux send-keys 'claude' Enter
