export def spinner [] {
  while true {
    for i in ["|", "/", "-", "\\"] {
      print -rn $"\r($i)"
      sleep 0.1sec
    }
  }
}

def fill [] {
  let max = (term size | get "columns")
  mut buf = ""
  for i in (seq 1 $max) {
    $buf = ($buf + "=")
    print $buf
    echo $buf | ansi gradient --fgstart '0x40c9ff' --fgend '0xe81cff'
    sleep 0.1sec
  }
}

export def "start spinner" [] {
  job spawn { spinner }
}

