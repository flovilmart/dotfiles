use asana.nu

const config = { default_model: "mistral-large-latest", api_version: "v1" }

const models = [
  "mistral-large-latest"
  "pixtral-large-latest"
  "mistral-small-latest"
  "mistral-saba-latest"
  "mistral-8b-latest"
  "mistral-3b-latest"
  "mistral-embed"
  "mistral-moderation-latest"
  "mistral-ocr-latest"
]

const max_retry = 0
export def --env set_model [model: string] {
  $env.MISTRAL_MODEL = $model
}

def get_model [] {
  if ("MISTRAL_MODEL" in $env) {
    return $env.MISTRAL_MODEL
  }
  return $config.default_model
}

def debug-is-on [] {
  "MISTRAL_DEBUG" in $env
}

def get_api_version [] {
  if ("MISTRAL_API_VERSION" in $env) {
    return $env.MISTRAL_API_VERSION
  }
  return $config.api_version
}

def content_block [source: string, str: string] {
  {
    "role": $source,
    "content": $str
  }
}

def get_prompt [prompt: string = ""] {
  $"(ansi rb)Mistral (ansi green)\((get_model)\)(ansi reset)(ansi blue)> (ansi reset)($prompt)"
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
  ]
}

def asana_tools [] {
  (asana ai function declarations | each { |item| { "type": "function", "function": $item } })
}

export def generate_content [input, generation_config = {}, history = []] {
  let url = $"https://api.mistral.ai/(get_api_version)/chat/completions"
  mut body = {
    model: (get_model)
    "messages": []
    tools: (asana_tools | append (fs_functions))
  }
  $body.messages = build_history $history

  $body.messages = $body.messages | append ($input | as_message)

  let final_body = $body
  if (debug-is-on) {
    print ($final_body | to json -r)
  }
  retry { http post --content-type "application/json" --allow-errors --headers ["Authorization", $"Bearer ($env.MISTRAL_API_KEY)"] $url $final_body }
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
        return ($args.contents | save $args.path)
      }
      "fs_read" => {
        return (open -r $args.path)
      }
    }
  } catch {
    |err| print $"Error running function: ($err.msg)"
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

export def --env chat [initial_prompt, generation_config = {}, history = []] {
  mut history: any = $history
  mut text = $initial_prompt

  mut next_call: any = null

  let state = {
    session: $history
  }
  # Check if we have a prompt, if not, ask for one
  if ($text | is-empty) {
    # TODO: Listen for up / down keys to cycle through previous queries
    $text = (input $"(get_prompt)" | str trim)
  } else if ($text | is-string) {
    print (get_prompt $text)
  }
  match $text {
    '\dump' => {
      $env.MISTRAL_STATE = $state
      print $state
    }
    '\exit' => {
      return $state
    }
    '\debug' => {
      $env.MISTRAL_DEBUG = "true"
    }
    '\debug off' => {
      if (debug-is-on) {
        hide-env MISTRAL_DEBUG
      }
    }
    '\reset' => {
      $history = []
    }
    '\model' => {
      set_model ($models | input list)
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
      print -rn $"- running...."
      let response = (generate_content $text $generation_config $history)
      # Append the previous call in the history
      $history = $history | append ($text | as_message)

      if (debug-is-on) {
        print ($response | to json -r)
      }

      if ("choices" in $response) {
        let message = $response | get choices.0.message
        $history = $history | append $message
        print -rn $"\r"
        print ($message | get content)

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
  }

  # loop back in!
  chat $next_call $generation_config $history
}

export def --env main [prompt: string = "", generation_config = {}] {
  mut history = []
  let input = $in
  if (($input | is-not-empty) and "session" in $input) {
    $history = $input | get session
  }
  chat $prompt $generation_config $history
}

