#!/bin/bash

UNAME_MACHINE="$(/usr/bin/uname -m)"

if [[ "${UNAME_MACHINE}" == "arm64" ]]
then
  # On ARM macOS, this script installs to /opt/homebrew only
  HOMEBREW_PREFIX="/opt/homebrew"
  HOMEBREW_REPOSITORY="${HOMEBREW_PREFIX}"
else
  # On Intel macOS, this script installs to /usr/local only
  HOMEBREW_PREFIX="/usr/local"
  HOMEBREW_REPOSITORY="${HOMEBREW_PREFIX}/Homebrew"
fi

all() {
  base
}

extras() {
  base
  langs
}

base()  {
  submodules
  homebrew
  brew_bundle
  dotfiles
  nushell
  starship
  vim
  tmux_plugins
  claude
  pi
}

claude() {
	ln -sfn $(pwd)/.claude ${HOME}/.claude
}

# Wire dotclaude resources into the paths pi scans. CLAUDE.md and skills use
# formats pi reads natively (context file + Agent Skills standard), so no plugin
# is needed. rex is managed by "rex skill setup", so skip it to avoid a duplicate.
pi() {
	# Keep ~/.pi in the repo (like ~/.claude), so config is version controlled.
	# One-time: migrate existing runtime state into the repo dir, then replace
	# ~/.pi with a symlink. Secrets and generated state stay out of git via
	# .pi/.gitignore; only agent/settings.json is tracked.
	pi_src="$(pwd)/.pi"
	mkdir -p "${pi_src}/agent"
	if [ -e "${HOME}/.pi" ] && [ ! -L "${HOME}/.pi" ]; then
		rsync -a "${HOME}/.pi/agent/" "${pi_src}/agent/"
		mv "${HOME}/.pi" "${HOME}/.pi.pre-dotfiles.$(date +%Y%m%d%H%M%S)"
	fi
	ln -sfn "${pi_src}" "${HOME}/.pi"

	mkdir -p ${HOME}/.pi/agent/skills ${HOME}/.pi/agent/agents ${HOME}/.pi/agent/extensions
	ln -sfn ${HOME}/.claude/CLAUDE.md ${HOME}/.pi/agent/AGENTS.md
	# Link every dir that holds a SKILL.md. This finds the nested "synced/<uuid>/<skill>"
	# skills and skips non-skill dirs like the control-center plugin. rex is managed by
	# "rex skill setup", so skip it to avoid a duplicate.
	find -L ${HOME}/.claude/skills -maxdepth 4 -name SKILL.md -print0 | while IFS= read -r -d '' f; do
		skill_dir=$(dirname "$f")
		name=$(basename "$skill_dir")
		[ "$name" = "rex" ] && continue
		ln -sfn "$skill_dir" ${HOME}/.pi/agent/skills/"$name"
	done
	# Sub-agents: pi has no native sub-agent concept, so wire the shipped "subagent"
	# example extension and expose the dotclaude agent defs to it. The extension reads
	# ~/.pi/agent/agents/*.md, whose frontmatter matches the Claude agent format.
	pi_pkg=$(ls -d ${HOME}/.volta/tools/image/packages/@earendil-works/pi-coding-agent/lib/node_modules/@earendil-works/pi-coding-agent 2>/dev/null | head -1)
	if [ -n "$pi_pkg" ] && [ -d "$pi_pkg/examples/extensions/subagent" ]; then
		mkdir -p ${HOME}/.pi/agent/extensions/subagent
		ln -sfn "$pi_pkg/examples/extensions/subagent/index.ts" ${HOME}/.pi/agent/extensions/subagent/index.ts
		# index.ts imports "./agents.ts"; use our vendored copy that treats
		# `model: inherit` as "inherit parent model" instead of a model pattern.
		ln -sfn $(pwd)/pi/subagent/agents.ts ${HOME}/.pi/agent/extensions/subagent/agents.ts
	else
		echo "pi: subagent example not found; skipping sub-agent wiring" >&2
	fi
	for f in ${HOME}/.claude/agents/*.md; do
		[ -e "$f" ] || continue
		ln -sfn "$f" ${HOME}/.pi/agent/agents/"$(basename "$f")"
	done
	# pi-only per-agent model overrides. The shared Claude agent files can't carry
	# these (Claude Code can't target these providers), so replace the symlink with
	# a generated copy whose frontmatter model: line is rewritten. Include a :off
	# thinking suffix for models the subagent extension would otherwise run with a
	# default thinking level they reject.
	pi_agent_model security-reviewer "mistral/mistral-large-4:off"
	# Fable is a pi-catalog Anthropic model Claude Code may not expose; keep it
	# pi-only so the shared file stays Claude-valid (opus). slice-planner runs once
	# per stack and is high-leverage, so it gets the premium frontier model.
	pi_agent_model slice-planner "anthropic/claude-fable-5-1"
}

# Rewrite only the frontmatter `model:` line of a dotclaude agent into a pi copy.
pi_agent_model() {
	name="$1"; model="$2"
	src="${HOME}/.claude/agents/${name}.md"
	dst="${HOME}/.pi/agent/agents/${name}.md"
	[ -f "$src" ] || return 0
	rm -f "$dst"
	awk -v m="$model" '
		NR==1 && $0=="---" { infm=1; print; next }
		infm && $0=="---" { if(!done){print "model: " m; done=1} infm=0; print; next }
		infm && /^model:/ { print "model: " m; done=1; next }
		{ print }
	' "$src" > "$dst"
}

# Agent workflow toolchain on macOS (see .claude/docs/agent-workflow.md):
# Claude Code CLI, GitHub native stacks, pnpm through Volta.
agent() {
  command -v claude >/dev/null 2>&1 || ${HOMEBREW_PREFIX}/bin/brew install --cask claude-code
  gh extension list 2>/dev/null | grep -q gh-stack || gh extension install github/gh-stack
  VOLTA_FEATURE_PNPM=1 ~/.volta/bin/volta install pnpm
}

langs()  {
  node
  ruby
}

dotfiles() {
	for file in $(find $(pwd) -maxdepth 1 -type f -name ".*" -not -name ".gitignore" -not -name ".travis.yml" -not -name ".git" -not -name ".*.swp" -not -name ".gnupg"); do
		f=$(basename $file);
		echo $file;
		ln -sfn $file ${HOME}/$f;
	done;
	mkdir -p ${HOME}/.config/ghostty;
	ln -sfn $(pwd)/ghostty/config ${HOME}/.config/ghostty/config
  ln -sfn $(pwd)/ghostty/themes ${HOME}/.config/ghostty/themes
	ln -sfn $(pwd)/ghostty/shaders ${HOME}/.config/ghostty/shaders
	mkdir -p ${HOME}/.config/rex;
	ln -sfn $(pwd)/rex/init.lua ${HOME}/.config/rex/init.lua
}

fix_nu_path() {
  NU_INSTALL_PATH=$(which nu)
  if [ -z "${NU_INSTALL_PATH}" ]; then
    echo "Nu not found in path. Please install Nu and try again"
    exit 1
  fi
  if [ "${NU_INSTALL_PATH}" == "/opt/homebrew/bin/nu" ]; then
    echo "nothing to do..."
  else
    sed -i "s#/opt/homebrew/bin/nu#${NU_INSTALL_PATH}#" ./.tmux.conf
  fi
}


submodules() {
  if [ -d .git ]; then
    git submodule update --init --recursive
  else
    echo "Not a git repo... skipping submodules"
  fi
}

homebrew() {
	test -x ${HOMEBREW_PREFIX}/bin/brew || /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
}

brew_bundle() {
	${HOMEBREW_PREFIX}/bin/brew bundle --verbose
	${HOMEBREW_PREFIX}/bin/brew bundle --verbose --file=Brewfile.cloud
}

brew_bundle_lang() {
  homebrew
	${HOMEBREW_PREFIX}/bin/brew bundle --file=Brewfile.lang
}

brew_bundle_ruby() {
  homebrew
	${HOMEBREW_PREFIX}/bin/brew bundle --file=Brewfile.ruby
}

ruby() {
  brew_bundle_ruby
	rbenv install -s 3.4.5
	rbenv global 3.4.5
	gem install rails --version=6.0.1 --no-document
}

node() {
	curl https://get.volta.sh | bash
	~/.volta/bin/volta install node
	~/.volta/bin/npm install -g typescript eslint prettier;
}

vim() {
  pushd $(pwd)/vimrc;
  sh ./install.sh all
  popd;
}

tmux_plugins() {
	mkdir -p ${HOME}/.tmux/plugins
	ln -sfn $(pwd)/tpm ${HOME}/.tmux/plugins
	ln -sfn $(pwd)/scripts/open-project.sh ${HOME}/.tmux/open-project.sh
	ln -sfn $(pwd)/scripts/preview-pane.sh ${HOME}/.tmux/preview-pane.sh
}

jira() {
	ln -sfn $(pwd)/.jira.d ${HOME}
}

nushell() {
  NU_CONFIG_DIR=$(nu -c '$nu.default-config-dir')
  NU_CONFIG=${NU_CONFIG_DIR}/config.nu
  NU_ENV=${NU_CONFIG_DIR}/env.nu
  mkdir -p "${NU_CONFIG_DIR}"
  mkdir -p ${HOME}/.config
  touch ${HOME}/.config/nu.env.toml
	ln -sfn $(pwd)/nushell/env.nu "${NU_ENV}"
	ln -sfn $(pwd)/nushell/config.nu "${NU_CONFIG}"
	ln -sfn $(pwd)/nushell/scripts "${NU_CONFIG_DIR}/scripts"
	ln -sfn $(pwd)/nushell/modules "${NU_CONFIG_DIR}/modules"
  # Autoload (see nushell/README.md): nushell sources every *.nu in this directory after config.nu,
  # in name order. It is a real directory, not in git: shared modules are links (dotclaude's below,
  # skipped by nushell when ~/.claude is absent), machine-specific modules are files you add.
  mkdir -p "${NU_CONFIG_DIR}/autoload"
  ln -sfn "${HOME}/.claude/nu/shell/autoload.nu" "${NU_CONFIG_DIR}/autoload/00-dotclaude.nu"
}

starship() {
  ln -sfn $(pwd)/starship.toml ${HOME}/.config/starship.toml
}

# Default to running all if no args are given
if [ "$#" -eq 0 ]; then
  set -- all
fi

while (("$#")) ; do
  echo "Running $1"
  $1
  shift
done
