#!/bin/bash
# Rex version of tmux `prefix W`: pick a tab in any session with fzf, previewing its focused pane
rex=$(command -v rex || echo "$HOME/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS/rex")
export rex

line=$("$rex" ls --json | jq -r '.sessions[].session_id' | while read -r sid; do
  "$rex" session inspect "$sid" --json |
    jq -r '.label as $s | .session_id as $sid | .windows[] | "\($sid)\t\(.window_id)\t\($s) — \(.label)"'
done | fzf --reverse --delimiter '\t' --with-nth 3 \
  --preview '"$rex" capture -s {1} -w {2} --trim | tail -n "$FZF_PREVIEW_LINES"' \
  --preview-window 'right:60%') || exit 0

sid=$(cut -f1 <<<"$line")
wid=$(cut -f2 <<<"$line")
exec "$rex" do -s "$REX_SESSION" goto_window session_id="$sid" window_id="$wid"
