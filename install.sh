#!/bin/bash

all() {
  base
  langs
}

base()  {
  brew
  brew_bundle
  dotfiles
  nushell
  starship
  vim
  tmux_plugins
}

langs()  {
  node
  ruby
}

dotfiles() {
	for file in $(find $(pwd) -maxdepth 1 -type f -name ".*" -not -name ".gitignore" -not -name ".travis.yml" -not -name ".git" -not -name ".*.swp" -not -name ".gnupg"); do
		f=$(basename $file);
		echo $file;
		ln -sfn $file ${HOME}/$f;
	done;
	mkdir -p ${HOME}/.config/kitty;
	ln -sfn $(pwd)/kitty.conf ${HOME}/.config/kitty
	mkdir -p ${HOME}/.config/ghostty;
	ln -sfn $(pwd)/ghostty/config ${HOME}/.config/ghostty/config
	ln -sfn $(pwd)/ghostty/themes ${HOME}/.config/ghostty/themes
}

fix_nu_path() {
  NU_INSTALL_PATH=$(which nu)
  if [ -z "${NU_INSTALL_PATH}" ]; then
    echo "Nu not found in path. Please install Nu and try again"
    exit 1
  fi
  if [ "${NU_INSTALL_PATH}" == "/opt/homebrew/bin/nu" ]; then
    echo "nothing to do..."
  else
    sed -i "s#/opt/homebrew/bin/nu#${NU_INSTALL_PATH}#" ./.tmux.conf
  fi
}


submodules() {
  if [ -d .git ]; then
    git submodule update --init --recursive
  else
    echo "Not a git repo... skipping submodules"
  fi
}

brew() {
	which brew || curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh | bash
}

brew_bundle() {
	brew bundle
	brew bundle --file=Brewfile.cloud
}

brew_bundle_lang() {
  brew
	brew bundle --file=Brewfile.lang
}

brew_bundle_ruby() {
  brew
	brew bundle --file=Brewfile.ruby
}

ruby() {
  brew_bundle_ruby
	rbenv install -s 3.4.5
	rbenv global 3.4.5
	gem install rails --version=6.0.1 --no-document
}

node() {
	curl https://get.volta.sh | bash
	~/.volta/bin/volta install node
	~/.volta/bin/npm install -g typescript eslint prettier;
}

vim() {
  pushd $(pwd)/vimrc;
  sh ./install.sh all
  popd;
}

tmux_plugins() {
	mkdir -p ${HOME}/.tmux/plugins
	ln -sfn $(pwd)/tpm ${HOME}/.tmux/plugins
}

jira() {
	ln -sfn $(pwd)/.jira.d ${HOME}
}

nushell() {
  NU_CONFIG_DIR=$(nu -c '$nu.default-config-dir')
  NU_CONFIG=${NU_CONFIG_DIR}/config.nu
  NU_ENV=${NU_CONFIG_DIR}/env.nu
  mkdir -p ${NU_CONFIG_DIR}
  mkdir -p ${HOME}/.config
  touch ${HOME}/.config/nu.env.toml
	ln -sfn $(pwd)/nushell/env.nu "${NU_ENV}"
	ln -sfn $(pwd)/nushell/config.nu "${NU_CONFIG}"
	ln -sfn $(pwd)/nushell/scripts "${NU_CONFIG_DIR}/scripts"
	ln -sfn $(pwd)/nushell/modules "${NU_CONFIG_DIR}/modules"
}

starship() {
  ln -sfn $(pwd)/starship.toml ${HOME}/.config/starship.toml
}

while (("$#")) ; do
    echo "Running $1"
    $1
    shift
done
