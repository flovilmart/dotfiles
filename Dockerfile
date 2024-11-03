FROM alpine:edge

RUN apk add tmux git neovim nushell starship curl bash openssh-client

RUN ln -sf /usr/bin/nvim /usr/bin/vi

WORKDIR /root/src/flovilmart/dotfiles

COPY . .

RUN ./install.sh dotfiles
RUN ./install.sh nushell
RUN ./install.sh fix_tmux_nu_path
RUN ./install.sh tmux_plugins
RUN ./install.sh starship
RUN ./install.sh vim

CMD nu
