#!/bin/bash
# Rex version of tmux `prefix E`: type a command into every terminal pane of every session
rex=$(command -v rex || echo "$HOME/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS/rex")
read -r -e -p "Command: " cmd || exit 0
[ -n "$cmd" ] || exit 0

"$rex" ls --json | jq -r '.sessions[].session_id' | while read -r sid; do
  "$rex" session inspect "$sid" --json |
    jq -r '.windows[].layers[].blocks[] | select(.creator_name == "com.superlogical.terminal") | .block_id' |
    while read -r bid; do
      [ "$bid" = "$REX_BLOCK" ] && continue
      "$rex" send -s "$sid" -b "$bid" "$cmd" && "$rex" send-key -s "$sid" -b "$bid" enter
    done
done
