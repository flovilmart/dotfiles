use asana.nu

# Pricing: https://mistral.ai/products/la-plateforme#pricing
const models = [
  "mistral-small-latest" # not expensive
  "codestral-latest" # not very expensive
  "mistral-large-latest" # very expensive!
  "pixtral-large-latest"
  "mistral-saba-latest"
  "mistral-8b-latest"
  "mistral-3b-latest"
  "mistral-embed"
  "mistral-moderation-latest"
  "mistral-ocr-latest"
]

export def get_models [] {
  http get --headers (headers) "https://api.mistral.ai/v1/models"
}

const max_retry = 0

def get_agents [] {
  if ("MISTRAL_AGENTS" in $env) {
    return $env.MISTRAL_AGENTS
  }
  []
}

def get_current_runtime [state] {
  if ($state.config.agent | is-not-empty) {
    return $"ag:($state.config.agent | split row ":" | get 3)"
  }
  return $state.config.model
}

def content_block [source: string, str: string] {
  {
    "role": $source,
    "content": $str
  }
}

def get_prompt [state, prompt: string = ""] {
  $"(ansi rb)Mistral (ansi green)\((get_current_runtime $state)\)(ansi reset)(ansi blue)> (ansi reset)($prompt)"
}

def retry [block: closure, max = $max_retry] {
  mut cnt = $max
  loop {
    if ($cnt == 0) {
      return (do  $block)
    }
    try {
      return (do $block)
    } catch {
      |err| print $"Error: ($err.msg)"
    }
    $cnt = ($cnt - 1)
    print $"Retrying... ($cnt)/($max)"
  }
}

def build_history [state = []] {
  $state
}

def as_message [] {
  let input = $in
  if ($input | is-string) {
    content_block "user" $input
  } else {
    $input
  }
}

def fs_functions [] {
  return [
    { type: "function",
      function: {
        name: "fs_write",
        description: "write the content to the path in the file system",
        parameters: {
          type: "object",
          properties: {
            "path": { type: "string", description: "the path to write the contents" },
            "contents": { type: "string", description: "the content to write" }
          }
        }
      }
    },
    { type: "function",
      function: {
        name: "fs_read",
        description: "read the content to the path in the file system",
        parameters: {
          type: "object",
          properties: {
            "path": { type: "string", description: "the path to read the contents from" },
          }
        }
      }
    },
    { type: "function",
      function: {
        name: "fs_ls",
        description: "list the content of the provided directory at the path. This works only for directories. To read the content of a file, use fs_read",
        parameters: {
          type: "object",
          properties: {
            "path": { type: "string", description: "the path to list the files from" },
          }
        }
      }
    },
    { type: "function",
      function: {
        name: "exec",
        description: "execute an arbitrary command in the current directory. Retuns the stdout, stderr and exit_code of the command",
        parameters: {
          type: "object",
          properties: {
            "command": { type: "string", description: "the command to execute" },
          }
        }
      }
    },
  ]
}

def asana_tools [] {
  (asana ai function declarations | each { |item| { "type": "function", "function": $item } })
}

def headers [] {
  ["Authorization", $"Bearer ($env.MISTRAL_API_KEY)"]
}

export def generate_content [state, input] {
  mut body = {
    "messages": []
    tools: (asana_tools | append (fs_functions))
  }
  mut api = "chat"
  if ($state.config.agent | is-not-empty) {
    $body.agent_id = $state.config.agent
    $api = "agents"
  } else {
    $body.model = $state.config.model
  }
  let url = $"https://api.mistral.ai/v1/($api)/completions"
  $body.messages = build_history $state.history

  $body.messages = $body.messages | append ($input | as_message)

  let final_body = $body
  if ($state.config.debug) {
    print ($final_body | to json -r)
  }
  try {
    http post -t application/json -e -H (headers) $url $final_body
  } catch { |err| $err.msg }
}

def confirm [msg: string] {
  let res = (input $"(ansi yellow)($msg)(ansi reset) \(y/n\) ")
  return ($res | str starts-with "y")
}

def exec_function_call [tool_call] {
  let function_call = ($tool_call | get function)
  let id = ($tool_call | get id)
  let name = ($function_call | get name)
  let args = ($function_call | get arguments | from json)
  print $"Running (ansi yellow_italic)($name)(ansi reset) with args: (ansi blue)($args)(ansi reset)"
  try {
    match $name {
      "asana_typeahead" => {
        return (asana typeahead $args.type $args.query)
      },
      "asana_api_get" => {
        return (asana api get $args.url)
      }
      "asana_api_post" => {
        return (asana api post $args.url ($args.body | from json))
      }
      "asana_api_put" => {
        return (asana api put $args.url ($args.body | from json))
      }
      "fs_write" => {
        let dir = ($args.path | path dirname)
        if not ($dir | path exists) {
          print $"Creating directory ($dir)"
          mkdir $dir
        }
        try {
          return ($args.contents | save $args.path)
        } catch { |err|
          print $"Error writing to file: ($err.msg)"
          if (confirm "Do you want to overwrite the file?") {
            return ($args.contents | save -f $args.path)
          }
          return $err
        }
      }
      "fs_read" => {
        return (open -r $args.path)
      }
      "fs_ls" => {
        return (ls $args.path)
      }
      "exec" => {
        # Here we use complete to get stdout & stderr and exit code:
        # https://www.nushell.sh/book/stdout_stderr_exit_codes.html#stderr
        return (nu -c $args.command | complete)
      }
    }
  } catch {
    |err| print $"Error running function: ($err.msg)"
    return $err
  }
}

def is-string [] {
  ($in | describe) == "string"
}

def is-command [command] {
  let val = $in
  ($val | is-string) and ($val | str starts-with $command)
}

def param-from-command [val, command] {
  $val | split row $command | each { str trim } | filter { is-not-empty }
}

def --env init_session [state] {
  mut state = $state
  mkdir ~/.mistral/sessions
  if not ("session_id" in $state) {
    $state.session_id = (^date +%s)
  }
  $state.session_path = $"~/.mistral/sessions/($state.session_id).json"
  return $state
}

def append_session [state, entry] {
  (($entry | to json -r) + "\n") | save -a $state.session_path
}

def history_from_stream [] {
  let input = $in
  if (($input | describe) == "byte stream") {
    $input | lines | each { |line| $line | from json }
  } else {
    []
  }
}

def --env handle_command [state, text] {
  mut state = $state
  match $text {
    '\dump' => {
      $env.MISTRAL_STATE = $state
      print $state
    }
    '\exit' => {
      $state.exit = true
    }
    '\debug' => {
      $state.config.debug = true
    }
    '\debug off' => {
      $state.config.debug = false
    }
    '\usage' => {
      $state.config.usage = true
    }
    '\usage off' => {
      $state.config.usage = false
    }
    '\reset' => {
      $state.history = []
      $state.session_id = (^date +%s)
      $state.session_path = $"~/.mistral/sessions/($state.session_id).json"
    }
    '\model' => {
      $state.config.model = ($models | input list)
      $state.config.agent = ""
    }
    '\agent' => {
      let new_agent = ((get_agents | append "no agent") | input list)
      if ($new_agent == "no agent") {
        $state.config.agent = ""
      } else {
        $state.config.agent = $new_agent
      }
    }
    '\agent off' => {
      $state.config.agent = ""
    }
    '\session_info' => {
      # ensure a session exists before starting a new one
      $state = init_session $state
      print { path: $state.session_path, id: $state.session_id }
    }
    '\restore' => {
      let source = (ls ~/.mistral/sessions | input list | get name)
      $state.history = (open -r $source | history_from_stream)
    }
    # TODO: only run if this is a string before checking
    $val if ($val | is-command '\save') => {
      let param_list = param-from-command $val '\save'
      mut file_name = ""
      if ($param_list | is-empty) {
        $file_name = $"mistral-session-(^date +%s).json"
      } else {
        $file_name = $param_list | get 0
      }
      print $"Saving to ($file_name)"
      try {
        $state | save $file_name
      } catch { |err|
        print $"Error saving file: ($err.msg)"
      }
    }
  }
  $state
}

export def --env chat [initial_prompt, state] {
  mut state = init_session $state
  mut history: any = $state.history
  mut text = $initial_prompt

  mut next_call: any = null

  # Check if we have a prompt, if not, ask for one
  if ($text | is-empty) {
    # TODO: Listen for up / down keys to cycle through previous queries
    $text = (input $"(get_prompt $state)" | str trim)
  } else if ($text | is-string) {
    print (get_prompt $state $text)
  }
  if (($text | str index-of '\') == 0) {
    # handle command!
    $state = (handle_command $state $text)
  } else {
    print -rn $"- running...."
    let input_message = $text | as_message
    append_session $state $input_message

    let response = (generate_content $state $text)
    # Append the previous call in the history
    $state.history = $state.history | append $input_message

    if ($state.config.debug) {
      print ($response | to json -r)
    }

    if ("choices" in $response) {
      let message = $response | get choices.0.message
      $state.history = $state.history | append $message
      append_session $state $message

      print -rn $"\r"
      print ($message | get content)
      if ($state.config.usage) {
        print ($response | get usage)
      }

      if ("tool_calls" in $message) {
        # here we just get the 1st tool call.
        let tool_call = ($message | get tool_calls | get 0?)
        if ($tool_call | is-not-empty) {
          $next_call = ($message | get tool_calls | each { |tool_call|
            let call_res = (exec_function_call $tool_call)
            {
              "role": "tool",
              "name" : ($tool_call | get function.name),
              "tool_call_id": $tool_call.id,
              "content": ($call_res | to json -r)
            }
          })
        }
      }
    } else {
      print ($response | to json -r)
    }
  }

  if ($state.exit) {
    return $state
  }

  # loop back in!
  chat $next_call $state
}

const default_state = {
  exit: false,
  config: {
    debug: false,
    usage: false
    agent: "",
    model: "mistral-small-latest",
  }
  history: []
}

export def --env main [prompt: string = "", state = $default_state] {
  mut state = $state
  let input = $in
  if (($input | describe) == "byte stream") {
    $state.history = $input | history_from_stream
  }
  chat $prompt $state
}

