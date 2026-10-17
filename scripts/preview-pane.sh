#!/bin/bash
target=$(echo "$1" | cut -d' ' -f1)
tmux capture-pane -t "${target}.0" -p -e 2>/dev/null
