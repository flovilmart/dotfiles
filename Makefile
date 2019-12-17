.PHONY: all
all: brew tmux dotfiles fonts vim tmux_plugins prezto nvm lang-server

.PHONY: dotfiles/
dotfiles:
	for file in $(shell find $(CURDIR) -maxdepth 1 -type f -name ".*" -not -name ".gitignore" -not -name ".travis.yml" -not -name ".git" -not -name ".*.swp" -not -name ".gnupg"); do \
		f=$$(basename $$file); \
		ln -sfn $$file $(HOME)/$$f; \
	done; \

.PHONY: fonts
fonts:
	cp -R $(CURDIR)/fonts/* $(HOME)/Library/fonts/; 

.PHONY: submodules
submodules:
	git submodule update --init --recursive

brew:
	/usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"


tmux: brew
	brew install tmux hub || brew upgrade tmux hub

.PHONY: vim
vim: vim_brew submodules
	ln -sfn $(CURDIR)/vimrc $(HOME)/.vim_runtime
	sh $(HOME)/.vim_runtime/install_awesome_vimrc.sh

.PHONY: tmux_plugins
tmux_plugins: submodules
	mkdir -p $(HOME)/.tmux/plugins
	ln -sfn $(CURDIR)/tpm $(HOME)/.tmux/plugins

.PHONY: vim_brew
vim_brew:
	brew install ag ack fzf  || brew upgrade ag ack fzf || exit 0

.PHONY: prezto
prezto:
	ln -sfn $(CURDIR)/.zprezto $(HOME)
	
.PHONY: nvm
nvm:
	curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.35.1/install.sh | bash

.PHONY: lang-server
lang-server:
	npm install -g typescript;
	ROOT=$(shell npm root -g); \
	rm -rf $$ROOT/javascript-typescript-langserver;		 \
	DIR=$(shell mktemp -d); \
	curl -sL https://github.com/sourcegraph/javascript-typescript-langserver/archive/master.zip -o $$DIR/archive.zip; \
	cd $$DIR; \
	unzip archive.zip; \
	cd javascript-typescript-langserver-master; npm install; npm run build && npm install -g .;

.PHONY: help
help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

