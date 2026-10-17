#!/bin/bash
# dev-entrypoint: prepare the slim dev-env container, then exec the command.
#
# 1. ~/.claude is a named volume (login, trust, sessions survive restarts). The
#    config that lives in git (dotclaude: agents, skills, hooks, settings.json,
#    workflows, nu modules)
#    is symlinked into it from the dotfiles checkout, so the container runs the
#    same agent workflow as the Mac without copying files around.
# 2. Volta lives in a volume: Node and pnpm follow each project's pins and are
#    installed on first use instead of being baked into the image.
# 3. gh-stack is installed as a gh extension when a GitHub token is available.
set -euo pipefail

DOTCLAUDE_DIR="${DOTCLAUDE_DIR:-/root/src/flovilmart/dotfiles/.claude}"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-/root/.claude}"
mkdir -p "$CLAUDE_DIR"
if [ -d "$DOTCLAUDE_DIR" ]; then
  # workflows: the coordinator's saved workflows; nu: shared nushell modules (the watcher's
  # OAuth, the shell's `linear` command)
  for entry in agents skills hooks docs output-styles settings.json CLAUDE.md workflows nu; do
    if [ -e "$DOTCLAUDE_DIR/$entry" ]; then
      ln -sfn "$DOTCLAUDE_DIR/$entry" "$CLAUDE_DIR/$entry"
    fi
  done
else
  echo "dev-entrypoint: $DOTCLAUDE_DIR not found; ~/.claude has no agents/skills (mount ~/src or set DOTCLAUDE_DIR)" >&2
fi

export VOLTA_HOME="${VOLTA_HOME:-/root/.volta}"
export PATH="$VOLTA_HOME/bin:$PATH"
if [ ! -x "$VOLTA_HOME/bin/volta" ]; then
  echo "dev-entrypoint: installing Volta into $VOLTA_HOME" >&2
  curl -fsSL https://get.volta.sh | bash -s -- --skip-setup
fi
if ! command -v node >/dev/null 2>&1; then
  echo "dev-entrypoint: installing default Node and pnpm (projects override with their own pins)" >&2
  volta install node pnpm
fi

if [ -n "${GH_TOKEN:-}" ] && ! gh extension list 2>/dev/null | grep -q 'gh-stack'; then
  gh extension install github/gh-stack || echo "dev-entrypoint: gh-stack install failed; stacks fall back to manual mode" >&2
fi

exec "$@"
