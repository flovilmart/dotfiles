const config = { default_model: "gemini-2.0-flash", api_version: "v1beta" }

export def --env set_model [model: string] {
  $env.GEMINI_MODEL = $model
}

def get_model [] {
  if ("GEMINI_MODEL" in $env) {
    return $env.GEMINI_MODEL
  }
  return $config.default_model
}

def get_api_version [] {
  if ("GEMINI_API_VERSION" in $env) {
    return $env.GEMINI_API_VERSION
  }
  return $config.api_version
}

def content_block [source: string, str: string] {
  {
    "role": $source,
    "parts": [
      {
        "text": $str
      }
    ]
  }
}

def get_prompt [prompt: string = ""] {
  $"Gemini \((get_model)\)> ($prompt)"
}

def retry [block: closure, max = 5] {
  mut cnt = $max
  loop {
    if ($cnt == 0) {
      return (do  $block )
    }
    try {
      return (do $block)
    }
    $cnt = ($cnt - 1)
    print $"Retrying... ($cnt)/($max)"
  }
}

def build_history [state = []] {
  $state | each { |item|
    if ("text" in $item) {
      return (content_block "user" $item.text)
    }
    [(content_block "user" $item.text),
    $item.response.candidates.0.content]
  } | flatten
}

export def generate_content [input, system_instruction: string = "", generation_config = {}, history = []] {
  let url = $"https://generativelanguage.googleapis.com/(get_api_version)/models/(get_model):generateContent?key=($env.GEMINI_API_KEY)"
  mut body = {
    "contents": []
    generationConfig: $generation_config
    tools: [
      { "function_declarations": (asana ai function declarations) }
    ]
  }
  if ($system_instruction | is-not-empty) {
    $body.system_instruction = { "parts": { "text": $system_instruction } }
  }
  $body.contents = $history

  if (($input | describe) =~ "string") {
    $body.contents = $body.contents | append (content_block "user" $input)
  } else {
    $body.contents = $body.contents | append $input
  }

  let final_body = $body
  retry { http post --content-type "application/json" $url $final_body }
}

export def add_function_response [response, system_instruction: string = "", state = []] {
  let url = $"https://generativelanguage.googleapis.com/(get_api_version)/models/(get_model):generateContent?key=($env.GEMINI_API_KEY)"
  mut body = {
    "contents": []
    tools: [
      { "function_declarations": (asana ai function declarations) }
    ]
  }
  if ($system_instruction | is-not-empty) {
    $body.system_instruction = { "parts": { "text": $system_instruction } }
  }
  $body.contents = build_history $state

  $body.contents = $body.contents | append {
    "role": "user",
    "parts": [
      {
        "functionResponse": $response
      }
    ]
  }
  let final_body = $body
  retry { http post -e --content-type "application/json" $url $final_body }
}

export def interactive_prompt [base = "Gemini> ", responses = []] {
  mut buf = ""
  mut res_idx = ($responses | length) - 1
  mut is_previous = false
  def render [buf: string] {
    print -rn $"\r($base)($buf)"
  }
  def clear_line [buf: string] {
    let len = ($buf | str length) + ($base | str length)
    print -rn ($"\r" | fill -c ' ' -w $len)
    print -rn $"\r"
  }

  render ""
  loop {
    let res = (input listen --types [key])
    if ($res.code == "up") {
      clear_line $buf
      # TODO: When looping - make sure we get the last line as well is there was one!
      if $res_idx < ($responses | length) and $res_idx >= 0 {
        $buf = $responses | get $res_idx
      }
      $res_idx = ($res_idx - 1)
      # loop
      if ($res_idx < 0) {
        $res_idx = ($responses | length) - 1
      }
      $is_previous = true
    } else if ($res.code == "down") {
      clear_line $buf
      # TODO: When looping - make sure we get the last line as well is there was one!
      if $res_idx < ($responses | length) and $res_idx >= 0 {
        $buf = $responses | get $res_idx
      }
      $res_idx = ($res_idx + 1)
      # loop
      if ($res_idx >= ($responses | length)) {
        $res_idx = 0
      }
      $is_previous = true
    } else if ($res.code == "enter") {
      print "enter"
      break
    } else if ($res.code == "backspace") {
      $buf = ($buf | str substring 0..-2)
    } else if ($res.key_type == "char" and $res.modifiers == []) {
      if ($is_previous) {
        clear_line $buf
        $buf = ""
        $is_previous = false
      }
      $buf = $buf + $res.code
    } else {
      print $res
    }
    render $buf
  }
  return $buf
}

def exec_function_call [function_call] {
  let name = ($function_call | get name)
  let args = ($function_call | get args)
  match $name {
    "asana_typeahead" => {
      let res = (asana typeahead $args.type $args.query)
      return { name: $name, response: { name: $name, content: $res } }
    },
    "asana_api_post" => {
      let res = (asana api post $args.url ($args.body | from json))
      return { name: $name, response: { name: $name, content: $res } }
    }
  }
}

export def --env chat [--system-instruction (-i): string = "", initial_prompt, generation_config = {}, history = []] {
  mut system_instruction = $system_instruction
  mut history: any = $history
  mut text = $initial_prompt

  mut next_call: any = null
  # System instructions may be passed in directly or throught he flag"
  let in_instructions = $in
  if ($in_instructions | is-not-empty) {
    $system_instruction = $in_instructions
  }

  let state = {
    system_instruction: $system_instruction
    session: $history
  }
  # Check if we have a prompt, if not, ask for one
  if ($text | is-empty) {
    # TODO: Listen for up / down keys to cycle through previous queries
    $text = input $"(get_prompt)"
  } else if (($text | describe) == "string") {
    print (get_prompt $text)
  } else {
    print "Prompt is an object..."
  }
  match $text {
    '\dump' => {
      $env.GEMINI_STATE = $state
      print $state
    }
    '\exit' => {
      return $state
    }
    '\execute' => {
      # let response = $responses | last | get response
      # let call_res = (exec_function_call ($response | get candidates.0.content.parts.0.functionCall))
      # let input = {
      #   "role": "user",
      #   "parts": [
      #     {
      #       "text": $response | get candidates.0.content.parts.0.functionCall
      #     }
      #   ]
      # }

      # let func_res = (generate_content $input $system_instruction $responses)
      # $responses = $responses | append { "response": $func_res }
      # print ($response | get candidates.0.content.parts)

      # if "functionCall" in ($response | get candidates.0.content.parts.0) {
      #   $next_call = '\execute'
      # }
      # print $func_res
    },
    $val if ($val | str starts-with '\save') => {
      mut param_list = $val | split row '\save' | each { str trim } | where { is-not-empty }
      mut file_name = ""
      if ($param_list | is-empty) {
        $file_name = $"gemini-session-(^date +%s).json"
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
    $val if ($val | str starts-with '\system_instruction') => {
      $system_instruction = $val | split row '\system_instruction' | get 1
    }
    _ => {
      print -rn $"- running...."
      $history = $history | append (content_block "user" $text)
      let response = (generate_content $text $system_instruction $generation_config $history)
      let content = $response | get candidates.0.content
      $history = $history | append $content
      print -rn $"\r"
      print ($content | get parts)

      let function_call = ($content | get parts?.0?.functionCall?)
      if ($function_call | is-not-empty) {
        let call_res = (exec_function_call $function_call)
        $next_call = {
          "role": "user",
          "parts": [
            {
              "functionResponse": $call_res
            }
          ]
        }
      }
    }
  }

  # loop back in!
  chat --system-instruction $system_instruction $next_call $generation_config $history
}

export def --env main [--system-instruction (-i): string = "", prompt: string = "", generation_config = {}] {
  $in | chat --system-instruction $system_instruction $prompt $generation_config
}

