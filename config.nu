
alias k = kubectl
alias kcuc = kubectl config use-context
alias kgp = kubectl get pods
alias kcsn = kubectl config set-context --current --namespace

def to_records [env_vars] {
  echo $env_vars | grep export | sed s/export//g | split row "\n" | each { |it| $it | str trim | split column "=" name value | first } | reduce -f {} { |it, acc| $acc | upsert $it.name $it.value }
}

def sonder_aws_config [dest] {
  sonder config aws -a $dest | sed s/export//g | split row "\n" | each { |it| $it | str trim | split column "=" name value | first } | each { |it| { $it.name: $it.value }}
}

def eval [std_out] {
  to_records $std_out | load-env
}

def kswitch [dest] {
  let envs = (sonder_aws_config $dest)
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
      name: "fzf",
      modifier: control,
      keycode: char_f,
      mode: vi_insert,
      event: { send: executehostcommand, cmd: "fzf" }
    }, {
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
    }
  ]
}
