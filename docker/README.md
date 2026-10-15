# Slim dev environment for the agent workflow

The image stays what it is: a shell layer (nushell, tmux, neovim, starship, git) plus the few
binaries the agent workflow needs (`claude` via the native installer, `gh`, `docker` CLI). Everything project-specific stays
out of the image and comes from volumes or from the project's own compose file:

| Need | Where it lives |
|------|----------------|
| Node, pnpm | Volta in the `volta` volume, installed on first start; projects pin their own versions |
| Claude login, trust, sessions, coordinator state | `claude-config` volume mounted at `~/.claude` |
| Agents, skills, hooks, settings (the `dotclaude` repo) | symlinked into `~/.claude` from `~/src/flovilmart/dotfiles/.claude` by the entrypoint |
| Browsers for smoke tests | the `browser` service (Playwright server), reached through `PW_TEST_CONNECT_WS_ENDPOINT` |
| Databases, queues, the app under test | the project's own compose file, run from inside `dev` against the host Docker daemon |

## First run

```nu
cp .env.example .env            # fill in SRC_DIR, DOCKER_SOCK, CLAUDE_CODE_OAUTH_TOKEN, GH_TOKEN
docker compose up -d --build
docker compose exec dev nu      # a shell with your dotfiles
```

`CLAUDE_CODE_OAUTH_TOKEN` comes from `claude setup-token` on the Mac; `GH_TOKEN` from `gh auth token`.
Neither `~/.ssh` nor cloud credentials are mounted. If a repo needs SSH, forward the agent socket
through `CONTAINER_SSH_AUTH_SOCK` instead of mounting keys.

## Running the agent workflow inside

```nu
docker compose exec dev claude --name dispatcher    # main session; /agent-workflow start
docker compose exec dev claude agents               # coordinators
docker compose exec dev claude attach ENG-123       # talk to one; ← to detach
```

Dispatcher and coordinators must be in the same container: cross-session messaging does not cross
the container boundary. The `dev` service runs `sleep infinity` so the background-session supervisor
and the coordinators keep running between your `exec`s.

Because the container confines commands and the network is yours to restrict, coordinators can run
with `--dangerously-skip-permissions` here (set `permission_mode: bypassPermissions` in the workflow
config) instead of `auto` mode. The CLI refuses that flag as root, so add a non-root `remoteUser`
before enabling it.

## Project services

From inside `dev`, `docker compose -f ~/src/<org>/<repo>/compose.yml up -d` starts the project's
services on the host daemon (the socket is mounted). Reach ports they publish through
`host.docker.internal`. To share a network instead, `include:` the project's compose file from this
one.

## Playwright

The `browser` service runs `playwright run-server`; the client in the project connects to it through
`PW_TEST_CONNECT_WS_ENDPOINT`, so no browsers are installed in `dev-env`. The server and client
versions must match: set `PLAYWRIGHT_VERSION` in `.env` to the project's `@playwright/test` version.

## musl

Alpine works for Node, pnpm and Claude Code (`USE_BUILTIN_RIPGREP=0` is set). A project that needs a
native module without a musl build is the one reason to switch the base image to
`debian:bookworm-slim`; nothing else in this setup changes.
