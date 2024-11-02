set -ex
all() {
  brew
  brew_bundle
  node
  ruby
  dotfiles
  vim
  tmux_plugins
  prezto
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
  brew_bundle_lang
	curl https://get.volta.sh | bash
	~/.volta/bin/volta install node
	~/.volta/bin/npm install -g typescript eslint prettier;
}

vim() {
  submodules
  cd $(pwd)/vimrc && make
}

tmux_plugins() {
  submodules
	mkdir -p ${HOME}/.tmux/plugins
	ln -sfn $(pwd)/tpm ${HOME}/.tmux/plugins
}

prezto() {
	ln -sfn $(pwd)/.zprezto ${HOME}
}

jira() {
	ln -sfn $(pwd)/.jira.d ${HOME}
}

nushell() {
  NU_CONFIG_DIR=$(nu -c '$nu.default-config-dir')
  NU_CONFIG=${NU_CONFIG_DIR}/config.nu
  NU_ENV=${NU_CONFIG_DIR}/env.nu
	ln -sfn $(pwd)/nushell/env.nu "${NU_ENV}"
	ln -sfn $(pwd)/nushell/config.nu "${NU_CONFIG}"
	ln -sfn $(pwd)/nushell/scripts "${NU_CONFIG_DIR}/scripts"
}

alanuship() {
	brew install alacritty nushell starship
	mkdir -p ${HOME}/.config/alacritty
	ln -sfn $(pwd)/starship.toml ${HOME}/.config/starship.toml
	ln -sfn $(pwd)/alacritty.yml ${HOME}/.config/alacritty/

  # Copy the nushell config
  nushell
}

# Run the command passed in
$1
