FROM alpine:edge

RUN apk add tmux git neovim nushell starship curl bash openssh-client

RUN mkdir -p ~/.ssh && ssh-keyscan -t rsa github.com >> ~/.ssh/known_hosts
RUN ln -sf /usr/bin/nvim /usr/bin/vi

WORKDIR /root/src/flovilmart/dotfiles

COPY . .

RUN ./install.sh dotfiles nushell fix_nu_path tmux_plugins starship
# Adds SSH keys to make sure we can clone submodules
RUN --mount=type=ssh ./install.sh vim

# back home
WORKDIR /root

CMD ["nu"]
