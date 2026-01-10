use asana.nu
# use spin.nu

const default_state = {
  exit: false,
  parent: {},
  result: {},
  config: {
    debug: false,
    usage: false
    force_overwrite: false,
    always_exec: false,
    agent: "",
    model: "mistral-small-latest",
    system_prompt: "~/.mistral/system_prompt.txt",
    agents: []
  }
  history: []
}

const DEFAULT_CONFIG_PATH = "~/.config/mistral.nuon"

# Pricing: https://mistral.ai/products/la-plateforme#pricing
const models = [
  "mistral-small-latest" # not expensive
  "magistral-small-latest" # not expensive
  "magistral-medium-latest" # not expensive
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

def get_agents [state] {
  return ($state.config.agents | each { |agent| $agent.name })
}

def get_agent [state, name] {
  return ($state.config.agents | where { |agent| $agent.name == $name } | first)
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
  mut parent_state = $state.parent
  mut parent_prompt = ""
  while ($parent_state | is-not-empty) {
    $parent_prompt = [(get_current_runtime $parent_state), ">", $parent_prompt] | str join " "
    $parent_state = $parent_state.parent
  }
  $"(ansi rb)Mistral (ansi green)\(($parent_prompt)(get_current_runtime $state)\)(ansi reset)(ansi blue)> (ansi reset)($prompt)"
}

def build_history [state = []] {
  $state
}

def as_message [] {
  mut input = $in
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
        name: "date",
        description: "get the current date",
        parameters: {
          type: "object",
          properties: {}
        }
      },
      handler: { |args, state|
        return (date now)
      }
    },
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
      handler: { |args, state|
        let dir = ($args.path | path dirname)
        if not ($dir | is-empty) and not ($dir | path exists) {
          print $"Creating directory (ansi yellow)($dir)(ansi reset)"
          mkdir $dir
        }
        try {
          if ($state.config.force_overwrite) {
            ($args.contents | save -f $args.path)
          } else {
            ($args.contents | save $args.path)
          }
        } catch { |err|
          print $"Error writing to file: ($err.msg)"
          if (confirm $"Do you want to overwrite ($args.path)?") {
            ($args.contents | save -f $args.path)
          } else {
            return $err
          }
        }
        return "File saved!"
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
      handler: { |args, state|
        return (open -r $args.path)
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
      handler:  { |args, state|
        if (not ($args.path | path exists)) {
          return { "error": "path does not exist" }
        }
        try {
          return (ls $args.path)
        } catch { |err|
          print $"Error listing directory: ($err.msg)"
          return { "error": $err }
        }
      }
    },
    { type: "function",
      function: {
        name: "exec",
        description: "execute or run an arbitrary command in the current directory. To run a full script, save is using fs_write first, in a temporary file in the /tmp folder. Retuns the stdout, stderr and exit_code of the command",
        parameters: {
          type: "object",
          properties: {
            "command": { type: "string", description: "the command to execute" },
          }
        }
      }
      handler: { |args, state|
        print $"Do you want to exec the command (ansi red)($args.command)(ansi reset)?"
        if (confirm) {
          # Here we use complete to get stdout & stderr and exit code:
          # https://www.nushell.sh/book/stdout_stderr_exit_codes.html#stderr
          return (nu -c $args.command | complete)
        }
        return { "error": "denied by the user" }
      }
    },
    # { type: "function",
    #   function: {
    #     name: "agent",
    #     description: "use an external agent to prompt. 1 agent (applescripter) is expert with interacting with the host system applications such as Mail. Once this agent has completed its work. it sends a DONE message.",
    #     parameters: {
    #       type: "object",
    #       properties: {
    #         "agent": { type: "string", description: "name of the agent" },
    #         "command": { type: "string", description: "the prompt to send to the agent" },
    #       }
    #     }
    #   }
    # },
  ]
}

def asana_tools [] {
  (asana ai function declarations)
}

def all_tools [] {
  asana_tools | append (fs_functions)
}

def headers [] {
  ["Authorization", $"Bearer ($env.MISTRAL_API_KEY)"]
}

def to-tools [] {
  let funcs = $in
  $funcs | each { |tool| { "type": "function", "function": $tool.function } }
}

export def generate_content [input, state = $default_state] {
  mut body = {
    "messages": []
    tools: (all_tools | to-tools)
  }
  mut api = "chat"
  if ($state.config.agent | is-not-empty) {
    $body.agent_id = $state.config.agent
    $api = "agents"
  } else {
    $body.model = $state.config.model
  }
  let url = $"https://api.mistral.ai/v1/($api)/completions"
  if ($state.config.system_prompt | path exists) {
    let prompt = (open -r ($state.config.system_prompt | path expand))
    if ($prompt | is-not-empty) {
      $body.messages = $body.messages | append (content_block "system" $prompt)
    }
  }
  $body.messages = $body.messages | append (build_history $state.history)

  $body.messages = $body.messages | append ($input | as_message)

  let final_body = $body
  if ($state.config.debug) {
    print $"Request: ($final_body | to json -r)"
  }
  try {
    http post -t application/json -e -H (headers) $url $final_body
  } catch { |err|
    print $err
    print "error..."
    "Error making http call"
  }
}

def confirm [msg: string = "Confirm?"] {
  let res = (input $"(ansi yellow)($msg)(ansi reset) \(y/n\) ")
  return ($res | str starts-with "y")
}

def exec_function_call [tool_call, state] {
  let function_call = ($tool_call | get function)
  let id = ($tool_call | get id)
  let name = ($function_call | get name)
  let args = ($function_call | get arguments | from json)
  print $"Running (ansi yellow_italic)($name)(ansi reset) with args: (ansi blue)($args)(ansi reset)"
  try {
    match $name {
      # "agent" => {
      #   let parent_state = $state
      #   mut state = $state
      #   $state.config.agent = "ag:71b0a997:20250318:applescripter:6484808f"
      #   # Remove the agent call
      #   $state.history = $state.history | drop
      #   $state.parent = $parent_state
      #   let res = (chat $"Never call the applescripter agent from yourself. Never call the agent tool. Always execute the generated script. Once done, respond with the result of the generated script and add \"\n\nDONE\". Do the following \'($args.command)\'" $state)
      #   print $"Agent completed ($res | get result)"
      #   return $res | get result
      # }
      _ => {
        let func = (all_tools | where { |f| $f.function.name == $name })

        if ($func | is-empty) {
          return { "error": "unknown function" }
        }

        try {
          return (do ($func | get handler | get 0) $args $state)
        } catch {
          |err| print $"Error running function: ($err.msg)"
          return $err
        }
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
  $val | split row $command | each { str trim } | where { is-not-empty }
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
  if (($input | describe) == "string") {
    ($input | lines | each { |line| $line | from json }) | flatten 1
  } else {
    []
  }
}

def --env handle_command [state] {
  mut state = $state
  let text = $in
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
    '\force_overwrite' => {
      $state.config.force_overwrite = true
    }
    '\force_overwrite off' => {
      $state.config.force_overwrite = false
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
      let new_agent = (((get_agents $state) | append "no agent") | input list)
      if ($new_agent == "no agent") {
        $state.config.agent = ""
      } else {
        $state.config.agent = (get_agent $state $new_agent) | get id
      }
    }
    '\config' => {
      print $state.config
    }
    '\config save' => {
      let config_path = $DEFAULT_CONFIG_PATH | path expand
      if not ($config_path | path exists) or (confirm "Config file already exists. Do you want to overwrite it? (y/n)") {
        print
        ($state.config | to nuon --indent 2) | save -f $config_path
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
    _ => {
      print $"(ansi red)Unknown command: (ansi rb)($text)(ansi reset)"
    }
  }
  $state
}

const DONE_FLAG = "DONE"

def set-exit [state] {
  if ($state.parent | is-empty) {
    return $state
  }

  mut state = $state
  let input = $in

  if ($input | is-string) and ($input | str ends-with $DONE_FLAG) {
    $state.exit = true
  }
  $state
}

def --env chat [initial_prompt, state] {
  mut state = init_session $state
  mut history: any = $state.history
  mut input: any = $initial_prompt

  loop {
    # Check if we have a prompt, if not, ask for one
    if ($input | is-empty) {
      $input = (input --history-file ~/.mistral/history $"(get_prompt $state)" | str trim)
    } else if ($input | is-string) {
      print (get_prompt $state $input)
    }
    if ($input | is-string) and (($input | str index-of '\') == 0) {
      # handle command!
      $state = ($input | handle_command $state)
      $input = ""
    } else {
      # let s = (spin start spinner)
      let input_message = $input | as_message
      append_session $state $input_message

      mut response = {};
      let prompt_input = $input
      let prompt_state = $state

      let generate_job = job spawn {
        let dat = job recv
        print $dat
        let res = generate_content $dat.0 $dat.1
        $res | job send 0
      }
      [$input $state] | job send $generate_job

      print "GENERATING"
      $response = job recv
      # job kill $generate_job

      # $response = generate_content $prompt_input $prompt_state
      # job kill $s
      if ($response | is-empty) {
        $response = {}
      }
      $input = ""
      # Append the previous call in the history
      $state.history = $state.history | append $input_message

      if ($state.config.debug) {
        print $"Response: $($response | to json -r)"
      }

      if ("choices" in $response) {
        let choice = $response | get choices.0
        let finish_reason = $choice | get finish_reason
        let message = $choice | get message
        $state.history = $state.history | append $message
        append_session $state $message
        let content = $message | get content

        print -rn $"\r"

        if ($content | is-not-empty) {
          if ($content | describe) == "string" {
            print $content
          } else {
            def print_content [c] {
              let type = $c | get "type"
              if $type == "text" {
                print $"($type): ($c | get $type)"
              } else {
                ($c | get $type) | each { |d| print_content $d }
              }
            }
            $content | each { |c| print_content $c }
          }
          $state.result = $content
          $state = ($content | set-exit $state)
        }

        if ($state.config.usage) {
          print ($response | get usage)
        }

        if ($finish_reason == "tool_calls") {
          # here we just get the 1st tool call.
          let tool_calls = ($message | get tool_calls)
          let immut_state = $state
          let result = ($tool_calls | each { |i| $i | exec_tool_call $immut_state })
          # store the result here. If we are doing an agentic call, then the input will be passed back to the agent
          # which will in turn respond with DONE, if complete. At that point, we will return the $state with the previous result.
          # We could embed also the whole history for the agent call (query, responses) but that seems wasteful!
          $state.result = $result
          # it is unlikely the tool call will return a DONE, but let's exit anyway
          $state = ($result | set-exit $state)
          # set the result of the tools call as the next input
          $input = $result
        }
      } else {
        #   print "---- Unexpected response ----"
        #   print ""
        #   print ($response | to json -r)
        #   print ""
        #   print "---- Unexpected response ----"
      }
    }

    # IF we marked to exit, exit now...
    if ($state.exit) {
      return $state
    }
  }
}

def exec_tool_call [state] {
  let tool_call = $in
  let call_res = (exec_function_call $tool_call $state)
  if ($state.config.debug) {
    print $"Tool call response: ($call_res | to json -r)"
  }
  {
    "role": "tool",
    "name" : ($tool_call | get function.name),
    "tool_call_id": $tool_call.id,
    "content": ($call_res | to json -r)
  }
}

def load_config [state, config_path = $DEFAULT_CONFIG_PATH] {
  let full_path = $config_path | path expand
  if not ($full_path | path exists) {
    return $state
  }
  mut state = $state
  try {
    $state.config = ($state.config | merge (open $full_path))
  } catch { |err|
    print $"Error loading config from ($config_path): ($err.msg)"
  }
  $state
}

export def --env main [--model: string = "", --exit, prompt?: string = "", state = $default_state] {
  mut state = (load_config $state)
  $state.exit = $exit
  let input = $in
  if (($input | describe) == "string") {
    $state.history = $input | history_from_stream
    print $"Restored history ($state.history | length) entries"
  }
  if ($model | is-not-empty) {
    if ($model in $models) {
      $state.config.model = $model
    } else {
      print $"Model ($model) not found in available models"
      $state.config.model = ($models | input list)
      $state.config.agent = ""
    }
  }
  chat $prompt $state
}

