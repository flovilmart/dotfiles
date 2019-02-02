.PHONY: all
all: dotfiles fonts vim tmux_plugins prezto n lang-server

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
	brew install ag ack fzf || exit 0

.PHONY: prezto
prezto:
	ln -sfn $(CURDIR)/.zprezto $(HOME)
	
.PHONY: n
n:
	which node && exit 0 || curl -sL https://git.io/n-install | bash
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

#.PHONY: test
#test: shellcheck ## Runs all the tests on the files in the repository.
#
## if this session isn't interactive, then we don't want to allocate a
## TTY, which would fail, but if it is interactive, we do want to attach
## so that the user can send e.g. ^C through.
#INTERACTIVE := $(shell [ -t 0 ] && echo 1 || echo 0)
#ifeq ($(INTERACTIVE), 1)
#	DOCKER_FLAGS += -t
#endif
#
#.PHONY: shellcheck
#shellcheck: ## Runs the shellcheck tests on the scripts.
#	docker run --rm -i $(DOCKER_FLAGS) \
#		--name df-shellcheck \
#		-v $(CURDIR):/usr/src:ro \
#		--workdir /usr/src \
#		r.j3ss.co/shellcheck ./test.sh
#
.PHONY: help
help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

