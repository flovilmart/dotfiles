# Example of a machine-specific module. Copy it into the autoload directory under a name that
# sorts after 00-dotclaude.nu, then edit it there (it isn't tracked):
#
#   cp ~/src/flovilmart/dotfiles/nushell/local.example.nu ($nu.user-autoload-dirs | first | path join 50-work.nu)
#
# Everything here is sourced into the interactive shell after config.nu.

# Modules that only exist on this machine (a work checkout, a client's tooling)
# use ~/src/tato/tools/nu/tato.nu

# Machine-only aliases and commands
# alias kprod = kubectl --context prod
# def vpn [] { ^open -a "Cisco Secure Client" }

# Extend a shared command: list only this team's issues
# def "linear mine" [] { linear issues | where state != "Backlog" }
