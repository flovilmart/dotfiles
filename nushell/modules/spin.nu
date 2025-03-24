export def spinner [] {
  while true {
    for i in ["|", "/", "-", "\\"] {
      print -rn $"\r($i)"
      sleep 0.1sec
    }
  }
}

export def "start spinner" [] {
  job spawn { spinner }
}

