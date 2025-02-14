alias k = kubectl
alias kcuc = kubectl config use-context
alias kgp = kubectl get pods
alias kcsn = kubectl config set-context --current --namespace

def to_records [env_vars] {
  echo $env_vars | grep export | sed s/export//g | split row "\n" | each { |it| $it | str trim | split column "=" name value | first } | reduce -f {} { |it, acc| $acc | upsert $it.name $it.value }
}

def eval [std_out] {
  to_records $std_out | load-env
}

def kswitch [dest] {
  let envs = (sonder aws config $dest)
  let namespaces = [["env", "namespace"]; ["staging", "preview"] ["prod", "production"]]

  let ns = (echo $namespaces | where env == $dest | get namespace --ignore-errors)
  if (($ns | empty?) != true) {
    kcsn $ns
  }
  echo $envs
}

def ambassador [] {
  echo "Visit http://127.0.0.1:8877/ambassador/v0/diag/"
  kubectl -n ambassador port-forward service/ambassador-admin 8877:8877
}

def klogs [app_name] {
  k logs -l app.kubernetes.io/name=$app_name
}

alias kswitch_prod = load-env (kswitch prod)
alias kswitch_stage = load-env (kswitch staging)

def "nu-complete git branches" [] {
  ^git branch | lines | each { |line| $line | str replace '\* ' '' | str trim }
}

def "nu-complete git remotes" [] {
  ^git remote | lines | each { |line| $line | str trim }
}

extern "git checkout" [
  branch?: string@"nu-complete git branches" # name of the branch to checkout
  -b: string                                 # create and checkout a new branch
  -B: string                                 # create/reset and checkout a branch
  # note: other parameters removed for brevity
]

$env.config = {
  show_banner: false,
  edit_mode: "vi",
  keybindings: [
    {
    #  name: "fzf",
    #  modifier: control,
    #  keycode: char_o,
    #  mode: vi_insert,
    #  event: { send: executehostcommand, cmd: "cd (^find ./src -maxdepth 2 -type d | fzf --reverse); vi .;" }
    #}, {
      name: "move_to_start",
      modifier: alt,
      keycode: char_b,
      mode: [emacs, vi_insert],
      event: { edit: movewordleft }
    }, {
      name: "move_to_end",
      modifier: alt,
      keycode: char_f,
      mode: [emacs, vi_insert],
      event: { edit: movewordright }
    }, {
      name: "delete_word",
      modifier: alt,
      keycode: backspace,
      mode: [emacs, vi_insert],
      event: { edit: backspaceword }
    }
  ]
}

export def install_highlights [] {
  let local = "vimrc/plugged/nvim-treesitter/queries/nu"
  let remote = "https://raw.githubusercontent.com/nushell/tree-sitter-nu/main/queries/nu/"
  let files = ["highlights.scm" "indents.scm" "injections.scm" "textobjects.scm"]

  mkdir $local

  $files | par-each {|file| http get ([$remote $file] | str join "/") | save --force ($local | path join $file) }
}


export def "sonder codeartifact_auth_token" [] {
  aws --profile sonder-dev/codeartifact-readonly codeartifact get-authorization-token --domain sonder-prod --domain-owner 111664848662 --region us-east-1 --query authorizationToken --output text
}

export def "sonder relogin" [] {
  sonder aws signout
  sonder setup
  sonder rewrap
}

export def "sonder rewrap" [] {
  warp-cli disconnect
  warp-cli connect
}

export def --env "sonder auth codeartifact" [profile?: string] {
  {CODEARTIFACT_AUTH_TOKEN: (sonder codeartifact_auth_token)} | load-env
}

export def --env "sonder config aws" [profile?: string] {
  try {
    ^sonder ...([config aws $profile] | compact)
        | lines
        | where $it =~ export | parse "export {key}={value}" | transpose -d -i -r | load-env
  }
}

export def "sonder proxy db" [] {
  let DB_HOST = "shared-aurora-pg-staging.cluster-c0kopnruetbd.us-east-1.rds.amazonaws.com"
  let USER_SOCAT = $"($env.USER)-socat"
  kubectl run $USER_SOCAT --image=marcnuri/port-forward --env=$"REMOTE_HOST=($DB_HOST)" --env="REMOTE_PORT=5432" --env="LOCAL_PORT=5433" ;
  kubectl wait --for=condition=ready --timeout=60s pod $USER_SOCAT;
  kubectl port-forward --pod-running-timeout=10s $USER_SOCAT 5433:5433;
  kubectl delete pod $USER_SOCAT;
}

export def "sonder --help" [] {
  ^sonder --help

  print "sonder relogin"
  print "sonder rewrap"
  print "sonder proxy db"
  print "sonder auth"
}
