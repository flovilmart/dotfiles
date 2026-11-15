/**
 * Agent discovery and configuration.
 *
 * Vendored from pi's `subagent` example (examples/extensions/subagent/agents.ts)
 * with one change: a `model` of `inherit` (or empty) is treated as "omit", so the
 * subagent inherits the dispatching session's model. Claude Code agent files use
 * the literal `model: inherit` sentinel; pi's example would otherwise pass it as a
 * model pattern and fail with "No models matching inherit".
 *
 * Shared by every pi extension in this repo (`../lib/agents.ts`). install.sh also links it
 * into ~/.pi/agent/extensions/subagent/ for the package's symlinked index.ts, which
 * imports "./agents.ts".
 */

import * as fs from "node:fs";
import * as path from "node:path";
import { CONFIG_DIR_NAME, getAgentDir, parseFrontmatter } from "@earendil-works/pi-coding-agent";

export type AgentScope = "user" | "project" | "both";

export interface AgentConfig {
	name: string;
	description: string;
	tools?: string[];
	model?: string;
	systemPrompt: string;
	source: "user" | "project";
	filePath: string;
}

export interface AgentDiscoveryResult {
	agents: AgentConfig[];
	projectAgentsDir: string | null;
}

type AgentFrontmatter = {
	name?: unknown;
	description?: unknown;
	tools?: unknown;
	model?: unknown;
};

/**
 * Map Claude Code tool names to pi's. Claude agent files use capitalized names
 * (`Read`, `Grep`, `Bash`, `Glob`); pi's tools are lowercase (`read`, `grep`,
 * `bash`, `find`, ...). Unknown-but-harmless Claude tools map to `null` and are
 * dropped: skills load automatically in pi, and sub-agent dispatch is this
 * extension itself. Anything unrecognized passes through lowercased; pi ignores
 * names it doesn't know.
 */
const TOOL_NAME_MAP: Record<string, string | null> = {
	read: "read",
	grep: "grep",
	bash: "bash",
	edit: "edit",
	write: "write",
	ls: "ls",
	find: "find",
	glob: "find",
	skill: null,
	task: null,
	todowrite: "TodoWrite", // claude-compat extension
	webfetch: "WebFetch",
	websearch: "WebSearch",
	lsp: "LSP",
};

function parseToolList(value: unknown): string[] | undefined {
	const raw = Array.isArray(value) ? value : typeof value === "string" ? value.split(",") : [];
	const tools = raw
		.filter((t): t is string => typeof t === "string")
		.map((t) => t.trim().toLowerCase())
		.filter(Boolean)
		.map((t) => (t in TOOL_NAME_MAP ? TOOL_NAME_MAP[t] : t))
		.filter((t): t is string => Boolean(t));
	const unique = Array.from(new Set(tools));
	return unique.length > 0 ? unique : undefined;
}

/**
 * Map Claude Code's bare model aliases to pi's qualified IDs. Claude agent files
 * say `opus`/`sonnet`/`haiku`; pi can't resolve those bare and errors with
 * "Use /login", so pin them to current flagship IDs. This keeps the shared agent
 * files working in both tools. Update these when a newer flagship ships.
 */
const MODEL_ALIAS_MAP: Record<string, string> = {
	opus: "anthropic/claude-opus-5-5",
	sonnet: "anthropic/claude-sonnet-5-5",
	haiku: "anthropic/claude-haiku-5-5",
};

/**
 * Normalize a frontmatter `model` value. `inherit` and empty strings mean "use
 * the dispatching session's model", expressed by leaving `model` undefined. Bare
 * Claude aliases map to qualified pi IDs; anything else passes through verbatim.
 */
export function resolveModelAlias(value: string): string {
	return MODEL_ALIAS_MAP[value.trim().toLowerCase()] ?? value.trim();
}

function parseModel(value: unknown): string | undefined {
	if (typeof value !== "string") return undefined;
	const model = value.trim();
	if (model === "" || model === "inherit") return undefined;
	return MODEL_ALIAS_MAP[model.toLowerCase()] ?? model;
}

function loadAgentsFromDir(dir: string, source: "user" | "project"): AgentConfig[] {
	const agents: AgentConfig[] = [];

	if (!fs.existsSync(dir)) {
		return agents;
	}

	let entries: fs.Dirent[];
	try {
		entries = fs.readdirSync(dir, { withFileTypes: true });
	} catch {
		return agents;
	}

	for (const entry of entries) {
		if (!entry.name.endsWith(".md")) continue;
		if (!entry.isFile() && !entry.isSymbolicLink()) continue;

		const filePath = path.join(dir, entry.name);
		let content: string;
		try {
			content = fs.readFileSync(filePath, "utf-8");
		} catch {
			continue;
		}

		const { frontmatter, body } = parseFrontmatter<AgentFrontmatter>(content);

		if (typeof frontmatter.name !== "string" || typeof frontmatter.description !== "string") {
			continue;
		}

		agents.push({
			name: frontmatter.name,
			description: frontmatter.description,
			tools: parseToolList(frontmatter.tools),
			model: parseModel(frontmatter.model),
			systemPrompt: body,
			source,
			filePath,
		});
	}

	return agents;
}

function isDirectory(p: string): boolean {
	try {
		return fs.statSync(p).isDirectory();
	} catch {
		return false;
	}
}

function findNearestProjectAgentsDir(cwd: string): string | null {
	let currentDir = cwd;
	while (true) {
		const candidate = path.join(currentDir, CONFIG_DIR_NAME, "agents");
		if (isDirectory(candidate)) return candidate;

		const parentDir = path.dirname(currentDir);
		if (parentDir === currentDir) return null;
		currentDir = parentDir;
	}
}

export function discoverAgents(cwd: string, scope: AgentScope): AgentDiscoveryResult {
	const userDir = path.join(getAgentDir(), "agents");
	const projectAgentsDir = findNearestProjectAgentsDir(cwd);

	const userAgents = scope === "project" ? [] : loadAgentsFromDir(userDir, "user");
	const projectAgents = scope === "user" || !projectAgentsDir ? [] : loadAgentsFromDir(projectAgentsDir, "project");

	const agentMap = new Map<string, AgentConfig>();

	if (scope === "both") {
		for (const agent of userAgents) agentMap.set(agent.name, agent);
		for (const agent of projectAgents) agentMap.set(agent.name, agent);
	} else if (scope === "user") {
		for (const agent of userAgents) agentMap.set(agent.name, agent);
	} else {
		for (const agent of projectAgents) agentMap.set(agent.name, agent);
	}

	return { agents: Array.from(agentMap.values()), projectAgentsDir };
}

export function formatAgentList(agents: AgentConfig[], maxItems: number): { text: string; remaining: number } {
	if (agents.length === 0) return { text: "none", remaining: 0 };
	const listed = agents.slice(0, maxItems);
	const remaining = agents.length - listed.length;
	return {
		text: listed.map((a) => `${a.name} (${a.source}): ${a.description}`).join("; "),
		remaining,
	};
}
