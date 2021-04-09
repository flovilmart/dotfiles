unsetopt CORRECT
setopt CLOBBER # Allow pipe to existing file. Prevent issue with history save in tmux-resurrect.

export N_PREFIX="$HOME/n"; [[ :$PATH: == *":$N_PREFIX/bin:"* ]] || PATH+=":$N_PREFIX/bin"

source ~/.aliases
source ~/.extra

# Source Prezto.
if [[ -s "${ZDOTDIR:-$HOME}/.zprezto/init.zsh"  ]]; then
   source "${ZDOTDIR:-$HOME}/.zprezto/init.zsh"
fi

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

bindkey "^E" end-of-line # Map end-of-line key in the same way as zprezto editor module to prevent issue with tmux-resurrect.
bindkey "^U" backward-kill-line

