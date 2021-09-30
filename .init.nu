def blastoff [] {
  config set env $nu.env
  config set path $nu.path
}

def starship_prompt [] {
  let dur = $nu.env.CMD_DURATION_MS;
  if $dur == "0" {
    STARSHIP_CONFIG="/Users/florent/.config/starship-short.toml" starship prompt --cmd-duration $nu.env.CMD_DURATION_MS
  } {
    starship prompt --cmd-duration $nu.env.CMD_DURATION_MS
  }
}
