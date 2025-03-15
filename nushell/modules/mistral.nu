use asana.nu

const config = { default_model: "mistral-small-latest", api_version: "v1" }

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
  ]
}

def asana_tools [] {
  (asana ai function declarations | each { |item| { "type": "function", "function": $item } })
}

def headers [] {
  ["Authorization", $"Bearer ($env.MISTRAL_API_KEY)"]
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
  retry { http post -t application/json -e -H (headers) $url $final_body }
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
    '\usage' => {
      $env.MISTRAL_PRINT_USAGE = "true"
    }
    '\usage off' => {
      if ("MISTRAL_PRINT_USAGE" in $env) {
        hide-env MISTRAL_PRINT_USAGE
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
        if ("MISTRAL_PRINT_USAGE" in $env) {
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

