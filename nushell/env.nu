# Nushell Environment Config File

try {
  open ~/.config/nu.env.toml | get env | load-env
} catch {
  echo "unable to load ~/.config/nu.env.toml"
}

def starship_prompt [short_prompt = false] {
  let dur = $env.CMD_DURATION_MS;
  let short_prompt = $short_prompt # or $dur == "0" or $dur == "";

  if ($short_prompt == true) {
    starship prompt --profile short --cmd-duration $env.CMD_DURATION_MS $'--status=($env.LAST_EXIT_CODE)' | decode utf8 | str trim --right
  } else {
    starship prompt --cmd-duration $env.CMD_DURATION_MS $'--status=($env.LAST_EXIT_CODE)' | decode utf8 | str trim --right
  }
}

$env.PROMPT_COMMAND = {
  starship_prompt
}
$env.PROMPT_INDICATOR = ' '
$env.PROMPT_COMMAND_RIGHT = ""
$env.PROMPT_INDICATOR_VI_INSERT = ' '
$env.PROMPT_INDICATOR_VI_NORMAL = '〉'
$env.PROMPT_MULTILINE_INDICATOR = '::: '
$env.TRANSIENT_PROMPT_COMMAND = {
  starship_prompt true
}

$env.EDITOR = "nvim"
$env.ANDROID_SDK_ROOK = $"($env.HOME)/Library/Android/sdk"

$env.NUPM_HOME = ($env.HOME | path join ".config" | path join "nupm")

$env.PATH = (
    [
        ($env.NUPM_HOME | path join "scripts"),
        "/usr/local/opt/kubernetes-cli@1.22/bin",
        ($env.HOME | path join ".volta" "bin"),
        ($env.HOME | path join ".rd" "bin"),
        ($env.HOME | path join "go" "bin"),
        ($env.HOME | path join ".krew" "bin"),
        ($env.HOME | path join ".cargo" "bin"),
        ($env.HOME | path join ".rbenv" "shims"),
        '/opt/homebrew/bin',
        '/opt/homebrew/sbin',
        '/usr/local/bin',
        (
            $env.ANDROID_SDK_ROOK
            | path join "platform_tools"
        ),
        (
            $env.ANDROID_SDK_ROOK
            | path join "emulator"
        ),
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin",
    ]
)

if ('GITHUB_TOKEN' in $env) {
  $env.HOMEBREW_GITHUB_API_TOKEN = $env.GITHUB_TOKEN
}

# Specifies how environment variables are:
# - converted from a string to a value on Nushell startup (from_string)
# - converted from a value back to a string when running external commands (to_string)
# Note: The conversions happen *after* config.nu is loaded
# $env.ENV_CONVERSIONS = {
#   "PATH": {
#     from_string: { |s| $s | split row (char esep) }
#     to_string: { |v| $v | str collect (char esep) }
#   }
# }

# Directories to search for scripts when calling source or use
#
# By default, <nushell-config-dir>/scripts is added
$env.NU_LIB_DIRS = [
    ($nu.config-path | path dirname | path join 'scripts')
    ($nu.config-path | path dirname | path join 'modules')
    ($env.NUPM_HOME | path join "modules")
]

# Directories to search for plugin binaries when calling register
#
# By default, <nushell-config-dir>/plugins is added
$env.NU_PLUGIN_DIRS = [
    ($nu.config-path | path dirname | path join 'plugins')
]

