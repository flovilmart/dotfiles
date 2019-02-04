# Source Prezto.
unsetopt CORRECT

source ~/.aliases
source ~/.extra

if [[ -s "${ZDOTDIR:-$HOME}/.zprezto/init.zsh"  ]]; then
   source "${ZDOTDIR:-$HOME}/.zprezto/init.zsh"
fi

export N_PREFIX="$HOME/n"; [[ :$PATH: == *":$N_PREFIX/bin:"* ]] || PATH+=":$N_PREFIX/bin"  # Added by n-install (see http://git.io/n-install-repo).
