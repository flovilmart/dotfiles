.PHONY: all
all: brew brew_bundle node ruby dotfiles vim tmux_plugins prezto

.PHONY: dotfiles/
dotfiles:
	for file in $(shell find $(CURDIR) -maxdepth 1 -type f -name ".*" -not -name ".gitignore" -not -name ".travis.yml" -not -name ".git" -not -name ".*.swp" -not -name ".gnupg"); do \
		f=$$(basename $$file); \
		echo $$file; \
		ln -sfn $$file $(HOME)/$$f; \
	done; \
	mkdir -p $(HOME)/.config/kitty; \
	ln -sfn $(CURDIR)/kitty.conf $(HOME)/.config/kitty

.PHONY: submodules
submodules:
	git submodule update --init --recursive

brew:
	which brew || curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh | bash

brew_bundle:
	brew bundle
	brew bundle --file=Brewfile.cloud

brew_bundle_lang: brew
	brew bundle --file=Brewfile.lang

brew_bundle_ruby: brew
	brew bundle --file=Brewfile.ruby

ruby: brew_bundle_ruby
	rbenv install -s 2.6.5
	rbenv global 2.6.5
	gem install rails --version=6.0.1 --no-document

node: brew_bundle_lang
	curl https://get.volta.sh | bash
	~/.volta/bin/volta install node
	~/.volta/bin/npm install -g typescript eslint prettier;

.PHONY: vim
vim: submodules
	cd $(CURDIR)/vimrc && make

.PHONY: tmux_plugins
tmux_plugins: submodules
	mkdir -p $(HOME)/.tmux/plugins
	ln -sfn $(CURDIR)/tpm $(HOME)/.tmux/plugins

.PHONY: prezto
prezto:
	ln -sfn $(CURDIR)/.zprezto $(HOME)

.PHONY: jira
jira:
	ln -sfn $(CURDIR)/.jira.d $(HOME)

.PHONY: help
help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

NU_CONFIG_HOME = $(HOME)/Library/Application\ Support/nushell

.PHONY: nushell
nushell:
	mkdir -p $(NU_CONFIG_HOME)
	ln -sfn $(CURDIR)/env.nu $(NU_CONFIG_HOME)/env.nu
	ln -sfn $(CURDIR)/config.nu $(NU_CONFIG_HOME)/config.nu
	ln -sfn $(CURDIR)/nushell_mods $(NU_CONFIG_HOME)/nushell_mods

.PHONY: alanuship
alanuship:
	brew install alacritty nushell starship
	mkdir -p $(HOME)/.config/alacritty
	ln -sfn $(CURDIR)/starship.toml $(HOME)/.config/starship.toml
	ln -sfn $(CURDIR)/alacritty.yml $(HOME)/.config/alacritty/
	ln -sfn $(CURDIR)/.init.nu $(HOME)/.config/.init.nu
	-cp -n $(CURDIR)/nushell.config.toml "$(shell dirname "$(shell nu -c "config path")")/config.toml"
	touch $(HOME)/.config/nu.env.toml
	nu -c "blastoff"
