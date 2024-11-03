FROM alpine:edge

RUN apk add tmux git neovim nushell starship curl bash openssh-client

RUN mkdir -p ~/.ssh && ssh-keyscan -t rsa github.com >> ~/.ssh/known_hosts
RUN ln -sf /usr/bin/nvim /usr/bin/vi

WORKDIR /root/src/flovilmart/dotfiles

COPY . .

RUN --mount=type=ssh ./install.sh submodules
RUN ./install.sh dotfiles
RUN ./install.sh nushell
RUN ./install.sh fix_tmux_nu_path
RUN ./install.sh tmux_plugins
RUN ./install.sh starship
# Adds SSH keys to make sure we can clone submodules
RUN --mount=type=ssh ./install.sh vim

CMD nu
