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

# Claude Code from the signed apk repository (stable channel)
RUN wget -q -O /etc/apk/keys/claude-code.rsa.pub https://downloads.claude.ai/keys/claude-code.rsa.pub \
  && echo "395759c1f7449ef4cdef305a42e820f3c766d6090d142634ebdb049f113168b6  /etc/apk/keys/claude-code.rsa.pub" | sha256sum -c - \
  && echo "https://downloads.claude.ai/claude-code/apk/stable" >> /etc/apk/repositories \
  && apk update \
  && apk add claude-code

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
    PATH=/root/.volta/bin:/root/.claude/bin:$PATH

COPY docker/entrypoint.sh /usr/local/bin/dev-entrypoint
RUN chmod +x /usr/local/bin/dev-entrypoint

# back home
WORKDIR /root

ENTRYPOINT ["dev-entrypoint"]
CMD ["nu"]
