def blastoff [] {
  config set env $nu.env
  config set path $nu.path
}

alias k = kubectl
alias kcuc = kubectl config use-context
alias kgp = kubectl get pods 
alias kcsn = kubectl config set-context --current --namespace

def from_toml [path: string] {
  open $path | get env | pivot | rename name value
}

def starship_prompt [] {
  let dur = $nu.env.CMD_DURATION_MS; 
  let hist = (build-string (dirname (config path) | str trim) "/history.txt")
  let mod_time = (ls $hist | get modified | date format "%+")

  if ($dur == "0") {
    starship prompt --right --cmd-duration $nu.env.CMD_DURATION_MS
  } {
    starship prompt --cmd-duration $nu.env.CMD_DURATION_MS
  }
}

def sonder_aws_config [dest] {
  sonder config aws -a $dest | sed s/export//g | split row "\n" | each { str trim | split column "=" name value }
}

def kswitch [dest] {
  let envs = (sonder_aws_config $dest)
  let namespaces = [["env", "namespace"]; ["staging", "preview"] ["prod", "production"]]
  
  let ns = (echo $namespaces | where env == $dest | get namespace)
  echo "Switching to $ns" 
  kcsn $ns
  echo $envs
}

alias kswitch_prod = load-env (kswitch prod) 
alias kswitch_stage = load-env (kswitch staging) 
