# Nushell setup

`./install.sh nushell` links this directory into nushell's config dir
(`nu -c '$nu.default-config-dir'`, `~/.config/nushell` on Linux, `~/Library/Application Support/nushell` on macOS).
Three layers, loaded in this order:

| Layer | What | Where | In git |
|-------|------|-------|--------|
| Shared | `env.nu`, `config.nu`, `scripts/`, `modules/` | this directory, linked | yes |
| dotclaude | the agent workflow's shell commands, e.g. `linear login`, `linear issues` | `autoload/00-dotclaude.nu` → `~/.claude/nu/shell/autoload.nu` | in dotclaude |
| This machine | anything only this machine needs | your own `*.nu` files in `autoload/`; env vars in `~/.config/nu.env.toml` | no |

Nushell sources every `*.nu` file in the user autoload directory (`$nu.user-autoload-dirs`)
after `config.nu`, in name order, in interactive sessions. So:

- **Machine-specific modules:** drop a file such as `autoload/50-work.nu` (see
  `local.example.nu`). It loads after `00-dotclaude.nu`, so it can add to or override shared commands.
  Nothing there is tracked, so work-only paths, aliases and secrets lookups stay on that machine.
- **Machine-specific environment:** `~/.config/nu.env.toml` (an `[env]` table), loaded by `env.nu`.
- **dotclaude missing** (submodule not checked out): nushell skips an autoload link whose target
  doesn't exist, so the shell still starts, just without the `linear` command.

Autoload runs for interactive shells only; scripts (`nu script.nu`, `nu -c`) `use` what they need.
