-- tmux-style keys for Rex, mirroring ~/.tmux.conf (prefix ctrl+b).
-- Rex tab = tmux window, Rex pane = tmux pane, Rex session = tmux session.
local P = "ctrl+b>"

local function prefix(key, action, args)
  rex.bind(P .. key, action, args)
end

-- ctrl+b ctrl+b sends a literal ctrl+b to the program, as in tmux.
prefix("ctrl+b", "pane.send_key", { key = "ctrl+b" })

-- Windows (Rex tabs)
prefix("c", "client.tab.new")
prefix("n", "client.tab.next")
prefix("p", "client.tab.previous")
prefix(",", "client.tab.rename")
prefix("shift+7", "client.tab.close") -- &
for i = 1, 9 do
  prefix(tostring(i), "client.tab.goto", { index = i })
end

-- Panes
prefix("shift+\\", "pane.split.right") -- |, as in my tmux.conf
prefix("-", "pane.split.down")
prefix("x", "pane.close")
prefix("z", "pane.zoom")
prefix("shift+1", "pane.move_to_new_tab") -- !
prefix("shift+[", "pane.move.left") -- {
prefix("shift+]", "pane.move.right") -- }
prefix("alt+1", "pane.balance")
prefix("left", "pane.focus.left")
prefix("right", "pane.focus.right")
prefix("up", "pane.focus.up")
prefix("down", "pane.focus.down")

-- ctrl+b ctrl+<arrow> resizes, like tmux's repeatable resize.
for _, dir in ipairs({ "left", "right", "up", "down" }) do
  prefix("ctrl+" .. dir, "pane.resize", { direction = dir })
end

-- Sessions
prefix("s", "session.switch")
prefix("shift+4", "session.rename") -- $
prefix("shift+9", "session.previous") -- (
prefix("shift+0", "session.next") -- )

-- prefix w w: the session tree (tmux choose-tree)
prefix("w>w", "session.switch")

-- Misc, from my tmux.conf
prefix("k", "com.superlogical.terminal.clear") -- clear pane + history
prefix("/", "client.find.open") -- search the scrollback
prefix("r", "client.config.reload")
prefix("shift+;", "client.palette.toggle") -- : command prompt

-- Popups and scripts (tmux display-popup / new-window "cmd")
local SHELL = "com.superlogical.terminal.shell"
local SCRIPTS = os.getenv("HOME") .. "/src/flovilmart/dotfiles/scripts/"

local function check(result, err)
  if err ~= nil then error(err, 0) end
  return result
end

local function terminal(options)
  return rex.layout.block{ flavor = SHELL, options = options }
end

local function new_tab(label, command, cwd)
  return check(rex.session.new_window{
    window_label = label,
    layout = terminal{ command = command, cwd = cwd },
  })
end

-- A centered floating terminal that closes when its command exits.
rex.action{
  name = "popup",
  title = "Open Popup",
  args = { command = "array", width = "number?", height = "number?" },
  run = function(ctx, args)
    local w, h = args.width or 0.8, args.height or 0.8
    return check(rex.session.new_layer{
      bounds = { (1 - w) / 2, (1 - h) / 2, w, h },
      layout = terminal{ command = args.command },
      focus = true,
    })
  end,
}

-- open-project.sh layout: diffview on the left, claude top right, a shell bottom right.
rex.action{
  name = "project_layout",
  title = "Open Project Layout",
  args = { dir = "string" },
  run = function(ctx, args)
    local dir = args.dir
    local win = check(rex.session.new_window{
      window_label = dir:match("([^/]+)/*$"),
      layout = rex.layout.horizontal(0.5,
        terminal{ cwd = dir, initial_input = 'vi -c "DiffviewOpen origin/main"\r' },
        rex.layout.vertical(0.5,
          terminal{ cwd = dir, initial_input = "claude\r" },
          terminal{ cwd = dir })),
    })
    if win.block_ids and win.block_ids[2] then
      rex.session.focus_block{ block_id = win.block_ids[2] }
    end
    return win
  end,
}

rex.action{
  name = "goto_window",
  title = "Go to Tab",
  args = { session_id = "string", window_id = "string" },
  run = function(ctx, args)
    if args.session_id == ctx.session_id then
      return check(rex.session.focus_window{ window_id = args.window_id })
    end
    -- Another session needs the app; it accepts this from the CLI only with Remote Control on.
    rex.client.queue("session.select", { session_id = args.session_id, window_id = args.window_id })
  end,
}

rex.action{
  name = "k9s",
  title = "Open k9s",
  run = function() return new_tab("k9s", { "k9s" }) end,
}

rex.action{
  name = "edit_config",
  title = "Edit Rex Config",
  run = function()
    local dir = os.getenv("HOME") .. "/.config/rex"
    return new_tab("init.lua", { "nvim", "init.lua" }, dir)
  end,
}

prefix("o", "popup", { command = { "bash", SCRIPTS .. "open-project.sh" } })
prefix("w>t", "popup", { command = { "bash", SCRIPTS .. "open-worktree.sh" }, width = 0.9, height = 0.8 })
prefix("shift+w", "popup", { command = { "bash", SCRIPTS .. "rex-pick-window.sh" }, width = 0.9, height = 0.8 })
prefix("shift+e", "popup", { command = { "bash", SCRIPTS .. "rex-broadcast.sh" }, width = 0.6, height = 0.2 })
prefix(".", "k9s")
prefix("e", "edit_config")

-- No-prefix keys from my tmux.conf
rex.bind("shift+left", "client.tab.previous")
rex.bind("shift+right", "client.tab.next")
rex.bind("shift+up", "pane.focus_previous")
