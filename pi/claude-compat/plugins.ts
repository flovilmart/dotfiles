/**
 * Claude Code plugins in pi. For every plugin enabled in ~/.claude/settings.json
 * (resolved through ~/.claude/plugins/installed_plugins.json, so version bumps
 * follow automatically):
 *   - skills/        → pi skills        (resources_discover)
 *   - commands/*.md  → pi prompt templates (resources_discover)
 *   - .mcp.json      → pi-mcp-adapter `claudePlugins` in ~/.pi/agent/mcp-adapter.json;
 *                      plugins the adapter rejects (non-kebab name, flat file) are added to
 *                      ~/.config/mcp/mcp.json. Written at load; /reload applies a change.
 * LSP plugins (typescript-lsp, pyright-lsp) have no files; the LSP tool covers them.
 */
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { type ExtensionAPI, getAgentDir } from "@earendil-works/pi-coding-agent";

interface Plugin {
	key: string;
	root: string;
}

const claudeDir = path.join(os.homedir(), ".claude");
const readJson = (f: string): any => {
	try {
		return JSON.parse(fs.readFileSync(f, "utf8"));
	} catch {
		return undefined;
	}
};

export function enabledPlugins(): Plugin[] {
	const enabled = readJson(path.join(claudeDir, "settings.json"))?.enabledPlugins ?? {};
	const installed = readJson(path.join(claudeDir, "plugins", "installed_plugins.json"))?.plugins ?? {};
	const out: Plugin[] = [];
	for (const [key, on] of Object.entries(enabled)) {
		if (!on) continue;
		const entries = installed[key] as Array<{ installPath?: string; scope?: string }> | undefined;
		const root = entries?.find((e) => e.scope === "user")?.installPath ?? entries?.[0]?.installPath;
		if (root && fs.existsSync(root)) out.push({ key, root });
	}
	return out;
}

/** Servers declared by a plugin: `{ "mcpServers": {...} }` or a flat `{ name: {...} }` map. */
function pluginServers(p: Plugin): Record<string, unknown> {
	const raw = readJson(path.join(p.root, ".mcp.json"));
	if (!raw || typeof raw !== "object") return {};
	return raw.mcpServers ?? raw;
}

/** The adapter's plugin loader needs a kebab-case manifest name and the wrapped form. */
function bundleable(p: Plugin): boolean {
	const raw = readJson(path.join(p.root, ".mcp.json"));
	if (!raw?.mcpServers) return false;
	const name = readJson(path.join(p.root, ".claude-plugin", "plugin.json"))?.name;
	return name === undefined || /^[a-z0-9]+(-[a-z0-9]+)*$/.test(name);
}

/** Plugins the loader rejects: add their servers to the global MCP file, never overriding one already there. */
function syncDirectServers(plugins: Plugin[]): boolean {
	const file = path.join(os.homedir(), ".config", "mcp", "mcp.json");
	const current = readJson(file) ?? {};
	const servers: Record<string, unknown> = { ...(current.mcpServers ?? {}) };
	let changed = false;
	for (const p of plugins.filter((x) => !bundleable(x))) {
		for (const [name, def] of Object.entries(pluginServers(p))) {
			if (!(name in servers)) {
				servers[name] = def;
				changed = true;
			}
		}
	}
	if (!changed) return false;
	fs.mkdirSync(path.dirname(file), { recursive: true });
	fs.writeFileSync(file, `${JSON.stringify({ ...current, mcpServers: servers }, null, 2)}\n`);
	return true;
}

function syncAdapterConfig(plugins: Plugin[]): boolean {
	const file = path.join(getAgentDir(), "mcp-adapter.json");
	const current = readJson(file) ?? {};
	const wanted = plugins.filter(bundleable).map((p) => ({ path: p.root, mcp: true }));
	// Keep entries the user added by hand (outside ~/.claude/plugins); replace ours.
	const manual = ((current.claudePlugins ?? []) as Array<{ path: string }>).filter((e) => !e.path.startsWith(path.join(claudeDir, "plugins") + path.sep));
	const next = [...manual, ...wanted];
	if (JSON.stringify(current.claudePlugins ?? []) === JSON.stringify(next)) return false;
	fs.writeFileSync(file, `${JSON.stringify({ ...current, claudePlugins: next }, null, 2)}\n`);
	return true;
}

export function registerPlugins(pi: ExtensionAPI) {
	let changed = false;
	try {
		const plugins = enabledPlugins();
		changed = syncAdapterConfig(plugins);
		changed = syncDirectServers(plugins) || changed;
	} catch {
		/* read-only config dir: skip */
	}

	pi.on("session_start", async (event, ctx) => {
		if (changed && event.reason === "startup" && ctx.hasUI) {
			ctx.ui.notify("Claude plugin MCP servers updated in mcp-adapter.json. Run /reload to load them.", "info");
		}
	});

	pi.on("resources_discover", async () => {
		const plugins = enabledPlugins();
		const skillPaths = plugins.map((p) => path.join(p.root, "skills")).filter((d) => fs.existsSync(d));
		const promptPaths = plugins.map((p) => path.join(p.root, "commands")).filter((d) => fs.existsSync(d));
		return { skillPaths, promptPaths };
	});
}
