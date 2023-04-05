unsetopt CORRECT
setopt CLOBBER # Allow pipe to existing file. Prevent issue with history save in tmux-resurrect.

source ~/.aliases
source ~/.extra

# Source Prezto.
if [[ -s "${ZDOTDIR:-$HOME}/.zprezto/init.zsh"  ]]; then
   source "${ZDOTDIR:-$HOME}/.zprezto/init.zsh"
fi

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

bindkey "^E" end-of-line # Map end-of-line key in the same way as zprezto editor module to prevent issue with tmux-resurrect.
bindkey "^U" backward-kill-line


export PATH="$HOME/.poetry/bin:$PATH"
export PATH="/usr/local/opt/kubernetes-cli@1.22/bin:$PATH"
export VOLTA_HOME="$HOME/.volta"
export PATH="$VOLTA_HOME/bin:$PATH"

export ANDROID_SDK_ROOT=$HOME/Library/Android/sdk
export PATH=$PATH:$ANDROID_SDK_ROOT/emulator
export PATH=$PATH:$ANDROID_SDK_ROOT/platform-tools
