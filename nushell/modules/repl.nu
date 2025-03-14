export def interactive_prompt [base = "> ", history = []] {
  mut buf = ""
  mut res_idx = -1
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
    if ($res.code == "enter") {
      return $buf
    }
    # TODO: Pattern matching rewrite
    if ($res.code == "c") and ($res.modifiers == ["keymodifiers(control)"]) {
      clear_line $buf
      $buf = ""
      error make {
        msg: "SIGINT"
      }
    } else if ($res.code == "up") {
      clear_line $buf
      if ($res_idx <= 0) {
        $res_idx = ($history | length)
      }
      $res_idx = ($res_idx - 1)
      $buf = $history | get $res_idx
      $is_previous = true
    } else if ($res.code == "down") {
      clear_line $buf
      if ($res_idx >= ($history | length) - 1) {
        $res_idx = -1
      }
      $res_idx = ($res_idx + 1)
      $buf = $history | get $res_idx
      $is_previous = true
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
}
