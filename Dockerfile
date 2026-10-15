FROM alpine:edge

RUN echo "https://alpine.fury.io/nushell/" | tee -a /etc/apk/repositories; \
  apk update; \
  apk add --allow-untrusted nushell;
RUN apk add tmux git neovim starship curl bash openssh-client

# Agent workflow toolchain, kept small on purpose:
#   github-cli + docker-cli  -> gh / gh stack, and project compose files against the host daemon
#   libgcc libstdc++ ripgrep -> Claude Code runtime deps on musl (USE_BUILTIN_RIPGREP=0)
# Node/pnpm are NOT in the image: Volta installs them into a volume on first start (docker/entrypoint.sh).
RUN apk add github-cli docker-cli docker-cli-compose libgcc libstdc++ ripgrep
# C toolchain for nvim-treesitter parsers (cc + linker + libc headers); without
# musl-dev/binutils every parser compile fails with "posix_spawn failed".
RUN apk add gcc musl-dev make

# Claude Code through the native installer (the documented path for Alpine/musl).
# It lands in /root/.local/bin and keeps itself updated inside a long-lived container.
RUN curl -fsSL https://claude.ai/install.sh | bash -s stable \
  && /root/.local/bin/claude --version

RUN mkdir -p ~/.ssh && ssh-keyscan -t rsa github.com >> ~/.ssh/known_hosts
RUN ln -sf /usr/bin/nvim /usr/bin/vi

WORKDIR /root/src/flovilmart/dotfiles

COPY . .

RUN ./install.sh dotfiles nushell fix_nu_path tmux_plugins starship
# Adds SSH keys to make sure we can clone submodules
RUN --mount=type=ssh ./install.sh vim

ENV USE_BUILTIN_RIPGREP=0 \
    VOLTA_HOME=/root/.volta \
    VOLTA_FEATURE_PNPM=1 \
    PATH=/root/.volta/bin:/root/.local/bin:$PATH

COPY docker/entrypoint.sh /usr/local/bin/dev-entrypoint
RUN chmod +x /usr/local/bin/dev-entrypoint

# back home
WORKDIR /root

ENTRYPOINT ["dev-entrypoint"]
CMD ["nu"]
