alias k = kubectl
alias kcuc = kubectl config use-context
alias kgp = kubectl get pods
alias kcsn = kubectl config set-context --current --namespace
alias vi = nvim

def to_records [env_vars] {
  echo $env_vars | grep export | sed s/export//g | split row "\n" | each { |it| $it | str trim | split column "=" name value | first } | reduce -f {} { |it, acc| $acc | upsert $it.name $it.value }
}

def eval [std_out] {
  to_records $std_out | load-env
}

def kswitch [dest] {
  let envs = (sonder aws config $dest)
  let namespaces = [["env", "namespace"]; ["staging", "preview"] ["prod", "production"]]

  let ns = (echo $namespaces | where env == $dest | get namespace -o)
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

export def install_highlights [] {
  let local = "vimrc/plugged/nvim-treesitter/queries/nu"
  let remote = "https://raw.githubusercontent.com/nushell/tree-sitter-nu/main/queries/nu/"
  let files = ["highlights.scm" "indents.scm" "injections.scm" "textobjects.scm"]

  mkdir $local

  $files | par-each {|file| http get ([$remote $file] | str join "/") | save --force ($local | path join $file) }
}


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

# Load the JWT Utils in the main shell
use jwt_utils.nu *
use sonder.nu *
use utils.nu *


# Modules
use asana.nu
use gemini.nu
use mistral.nu
