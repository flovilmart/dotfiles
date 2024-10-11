unsetopt CORRECT
setopt CLOBBER # Allow pipe to existing file. Prevent issue with history save in tmux-resurrect.

export LC_ALL=en_CA.UTF-8
export LANG=en_CA.UTF-8

source ~/.aliases
source ~/.extra

export PATH="/usr/local/bin:${PATH}"

# ZPrezto needs kubectl and docker to work properly we use the Rancher desktop one.
export PATH="${HOME}/.rd/bin:${PATH}"
# But we use the kubectl installed because the RD one is slow AF
# https://github.com/rancher-sandbox/rancher-desktop/issues/5216
export PATH="/usr/local/opt/kubernetes-cli@1.22/bin:$PATH"


ARCH=$(uname -m)
if [ "${ARCH}" = "arm64" ]; then
  export PATH="/opt/homebrew/bin:${PATH}"
fi

# Source Prezto.
if [[ -s "${ZDOTDIR:-$HOME}/.zprezto/init.zsh"  ]]; then
   source "${ZDOTDIR:-$HOME}/.zprezto/init.zsh"
fi

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
eval "$(rbenv init - zsh)"
export PATH="${HOME}/.poetry/bin:${PATH}"

export JAVA_19_CORRETTO_HOME=/Users/florentvilmart/.gradle/jdks/amazon_com_inc_-19-x86_64-os_x/amazon-corretto-19.jdk/Contents/Home
export JAVA_20_CORRETTO_HOME=/Users/florentvilmart/.gradle/jdks/amazon_com_inc_-20-x86_64-os_x/amazon-corretto-20.jdk/Contents/Home
export JAVA_19_HOME=/Library/Java/JavaVirtualMachines/amazon-corretto-19.jdk/Contents/Home
export JAVA_20_HOME=/Library/Java/JavaVirtualMachines/amazon-corretto-20.jdk/Contents/Home
export JAVA_21_HOME=/Library/Java/JavaVirtualMachines/amazon-corretto-21.jdk/Contents/Home
export JAVA_HOME=${JAVA_21_HOME}
export ANDROID_SDK_ROOT=${HOME}/Library/Android/sdk
export PATH=${PATH}:${ANDROID_SDK_ROOT}/emulator
export PATH=${PATH}:${ANDROID_SDK_ROOT}/platform-tools
export VOLTA_HOME="${HOME}/.volta"
export PATH="${VOLTA_HOME}/bin:${PATH}"
export PATH="${JAVA_HOME}/bin:${PATH}"

bindkey "^E" end-of-line # Map end-of-line key in the same way as zprezto editor module to prevent issue with tmux-resurrect.
bindkey "^U" backward-kill-line
