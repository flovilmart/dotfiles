# Terminal multiplexer abstraction over tmux and rex.
#
#   plexer detect                                  "tmux" or "rex"; override with $env.PLEXER
#   plexer split [cmd] --direction below --cwd .   split a pane, returns the new pane id
#   plexer window <name> [cmd] --cwd .             open a named window (a tab in rex), returns its pane id
#   plexer alive <pane>                            true while the pane's command runs
#   plexer kill <pane>                             close the pane
#
# Pane ids are opaque: tmux "%12", rex "block:...". A command runs through /bin/bash -c;
# without one, the pane opens a shell.

const REX_APP_BIN = "/Applications/Rex Beta.app/Contents/Helpers/Rex Server.rex/Contents/MacOS/rex"

export def detect [] {
  let forced = $env.PLEXER? | default ""
  if $forced in ["tmux" "rex"] {
    return $forced
  }
  # tmux first: a tmux started inside a Rex pane inherits REX_SESSION.
  if ($env.TMUX? | is-not-empty) {
    return "tmux"
  }
  if ($env.REX_SESSION? | is-not-empty) {
    return "rex"
  }
  error make { msg: "No terminal multiplexer found: run inside tmux or rex, or set PLEXER" }
}

# Split a pane and run a command in the new pane. Returns the new pane id.
export def split [
  command?: string
  --direction (-d): string = "right" # right, below, left or above
  --target (-t): string # pane to split; defaults to the focused pane
  --cwd (-c): string # working directory of the new pane
] {
  if $direction not-in ["right" "below" "left" "above"] {
    error make { msg: $"Unknown split direction: ($direction)" }
  }
  match (detect) {
    "tmux" => {
      let flags = tmux-direction-flags $direction
      let target_args = if $target != null { [-t $target] } else { [] }
      tmux split-window ...$flags ...$target_args ...(tmux-cwd-args $cwd) -P -F "#{pane_id}" ...(command-args $command) | str trim
    }
    "rex" => {
      let target_args = if $target != null { [-b $target] } else { [] }
      rex-cmd split ...(rex-session-args) ...$target_args ...(rex-cwd-args $cwd) $"--split=($direction)" --json ...(rex-command-args $command)
      | from json
      | get block_ids.0
    }
  }
}

# Open a named window (a tab in rex) that runs a command. Returns the pane id.
export def window [
  name: string
  command?: string
  --cwd (-c): string # working directory of the new window
] {
  match (detect) {
    "tmux" => {
      tmux new-window -n $name ...(tmux-cwd-args $cwd) -P -F "#{pane_id}" ...(command-args $command) | str trim
    }
    "rex" => {
      rex-cmd window new ...(rex-session-args) $name ...(rex-cwd-args $cwd) --json ...(rex-command-args $command)
      | from json
      | get block_ids.0
    }
  }
}

# True while the pane exists and its command still runs.
# Rex keeps a pane open after a quick failure, so the process state decides there.
export def alive [pane: string] {
  match (detect) {
    "tmux" => {
      tmux list-panes -a -F "#{pane_id}" | lines | any { $in == $pane }
    }
    "rex" => {
      let result = rex-cmd block call ...(rex-session-args) -b $pane process | complete
      if $result.exit_code != 0 {
        return false
      }
      ($result.stdout | from json | get child?) != null
    }
  }
}

# Close a pane and stop its command.
export def kill [pane: string] {
  match (detect) {
    "tmux" => { tmux kill-pane -t $pane }
    "rex" => { rex-cmd block close ...(rex-session-args) $pane }
  }
}

def tmux-direction-flags [direction: string] {
  match $direction {
    "right" => [-h]
    "left" => [-h -b]
    "below" => [-v]
    "above" => [-v -b]
  }
}

def tmux-cwd-args [cwd?: string] {
  if $cwd == null { [] } else { [-c ($cwd | path expand)] }
}

def rex-cwd-args [cwd?: string] {
  if $cwd == null { [] } else { [-c ($cwd | path expand)] }
}

def command-args [command?: string] {
  if $command == null { [] } else { [/bin/bash -c $command] }
}

def rex-command-args [command?: string] {
  if $command == null { [] } else { [-- /bin/bash -c $command] }
}

def rex-session-args [] {
  let session = $env.REX_SESSION? | default ""
  if ($session | is-empty) { [] } else { [-s $session] }
}

# The rex CLI is not always on PATH; fall back to the copy inside the app.
def --wrapped rex-cmd [...args: string] {
  let on_path = which rex | where type == external
  let bin = if ($on_path | is-not-empty) { $on_path.0.path } else { $REX_APP_BIN }
  ^$bin ...$args
}
