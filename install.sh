set -ex
all() {
  brew
  brew_bundle
  node
  ruby
  dotfiles
  vim
  tmux_plugins
}

dotfiles() {
	for file in $(find $(pwd) -maxdepth 1 -type f -name ".*" -not -name ".gitignore" -not -name ".travis.yml" -not -name ".git" -not -name ".*.swp" -not -name ".gnupg"); do
		f=$(basename $file);
		echo $file;
		ln -sfn $file ${HOME}/$f;
	done;
	mkdir -p ${HOME}/.config/kitty;
	ln -sfn $(pwd)/kitty.conf ${HOME}/.config/kitty
}

fix_tmux_nu_path() {
  NU_INSTALL_PATH=$(which nu)
  sed -i "s#/opt/homebrew/bin/nu#${NU_INSTALL_PATH}#" ./.tmux.conf
}

submodules() {
	git submodule update --init --recursive
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
	rbenv install -s 2.6.5
	rbenv global 2.6.5
	gem install rails --version=6.0.1 --no-document
}

node() {
	curl https://get.volta.sh | bash
	~/.volta/bin/volta install node
	~/.volta/bin/npm install -g typescript eslint prettier;
}

vim() {
  submodules
  cd $(pwd)/vimrc && sh ./install.sh all
}

tmux_plugins() {
  submodules
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
}

starship() {
  ln -sfn $(pwd)/starship.toml ${HOME}/.config/starship.toml
}

alanuship() {
	which brew && brew install alacritty nushell starship
  mkdir -p ${HOME}/.config
	mkdir -p ${HOME}/.config/alacritty
	ln -sfn $(pwd)/alacritty.yml ${HOME}/.config/alacritty/

  starship
  # Copy the nushell config
  nushell
}

# Check which function to invoke
invoke=$1
shift

# Invoke the function and pass args
$invoke $@
