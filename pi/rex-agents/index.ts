/**
 * rex-agents — launch pi sub-agents into Rex panes and list/focus them.
 *
 * Unlike the inline `subagent` extension (isolated child process, output
 * streamed into the current session), this runs each agent as its own
 * interactive `pi` session in a Rex pane you can tab to and keep talking to —
 * the Claude-Code-style "parallel agents you can switch between".
 *
 * - Tool `spawn_agent`      — the model can dispatch an agent into a pane.
 * - Command `/agent <name> <task>` — launch one directly.
 * - Command `/agents` / Ctrl+Shift+A — overlay listing active agent panes;
 *   Enter focuses the pane.
 *
 * Agent definitions and their resolved model/tools come from the shared
 * `../subagent/agents.ts` loader, so model aliases, `inherit`, and Claude tool
 * names are handled identically to the inline sub-agents.
 */

import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { StringEnum } from "@earendil-works/pi-ai";
import { CustomEditor, DynamicBorder, type ExtensionAPI, type ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Container, Key, matchesKey, type SelectItem, SelectList, Text } from "@earendil-works/pi-tui";
import { Type } from "typebox";
import { type AgentConfig, discoverAgents } from "../subagent/agents.ts";

// Fallback when `rex` isn't on PATH in the shell pi spawns (Rex Beta on macOS).
const REX_APP_BIN = "/Applications/Rex Beta.app/Contents/Helpers/Rex Server.rex/Contents/MacOS/rex";

interface LaunchedAgent {
	name: string;
	task: string;
	model: string;
	blockId: string | undefined;
	session: string;
	startedAt: number;
}

const launched: LaunchedAgent[] = [];
let rexBinCache: string | null = null;

async function rexBin(pi: ExtensionAPI): Promise<string> {
	if (rexBinCache) return rexBinCache;
	try {
		const r = await pi.exec("rex", ["--version"], { timeout: 4000 });
		if (r.code === 0) {
			rexBinCache = "rex";
			return rexBinCache;
		}
	} catch {
		// not on PATH; fall back to the app binary
	}
	rexBinCache = REX_APP_BIN;
	return rexBinCache;
}

async function rex(pi: ExtensionAPI, args: string[], timeout = 10000) {
	const bin = await rexBin(pi);
	return pi.exec(bin, args, { timeout });
}

function rexContext(): { session: string; block: string } | null {
	const session = process.env.REX_SESSION;
	const block = process.env.REX_BLOCK;
	if (!session || !block) return null;
	return { session, block };
}

function findAgent(ctx: ExtensionContext, name: string): AgentConfig | undefined {
	const { agents } = discoverAgents(ctx.cwd, "user");
	return agents.find((a) => a.name === name);
}

function agentNames(ctx: ExtensionContext): string[] {
	return discoverAgents(ctx.cwd, "user").agents.map((a) => a.name);
}

/** Pull every id-like string out of `rex block ls --json` for liveness checks. */
function collectIds(node: unknown, out: Set<string>): void {
	if (Array.isArray(node)) {
		for (const v of node) collectIds(v, out);
	} else if (node && typeof node === "object") {
		for (const [k, v] of Object.entries(node)) {
			if ((k === "id" || k === "block_id" || k === "blockId") && typeof v === "string") out.add(v);
			else collectIds(v, out);
		}
	}
}

async function livingBlocks(pi: ExtensionAPI, session: string): Promise<Set<string>> {
	const ids = new Set<string>();
	try {
		const r = await rex(pi, ["block", "ls", "-s", session, "--json", "--short=false"]);
		if (r.code === 0 && r.stdout.trim()) collectIds(JSON.parse(r.stdout), ids);
	} catch {
		// treat as unknown; callers keep entries rather than dropping them
	}
	return ids;
}

async function launchAgent(
	pi: ExtensionAPI,
	ctx: ExtensionContext,
	agentName: string,
	task: string,
	opts?: { split?: string; ratio?: number },
): Promise<string | undefined> {
	const rc = rexContext();
	if (!rc) {
		ctx.ui.notify("Not inside a Rex session (REX_SESSION unset). Run pi inside Rex.", "error");
		return undefined;
	}
	const agent = findAgent(ctx, agentName);
	if (!agent) {
		ctx.ui.notify(`Unknown agent "${agentName}". Available: ${agentNames(ctx).join(", ") || "none"}`, "error");
		return undefined;
	}

	const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "pi-rex-agent-"));
	const sysPath = path.join(tmpDir, "system.md");
	fs.writeFileSync(sysPath, agent.systemPrompt ?? "", { encoding: "utf-8", mode: 0o600 });

	const piArgs: string[] = ["--name", agentName];
	if (agent.model) piArgs.push("--model", agent.model);
	if (agent.tools && agent.tools.length > 0) piArgs.push("--tools", agent.tools.join(","));
	if ((agent.systemPrompt ?? "").trim()) piArgs.push("--append-system-prompt", sysPath);
	piArgs.push(`Task: ${task}`);

	const rexArgs = [
		"split",
		"-s",
		rc.session,
		"-b",
		rc.block,
		"--split",
		opts?.split ?? "right",
		"--ratio",
		String(opts?.ratio ?? 45),
		"--label",
		agentName,
		"--focus=false",
		"--keep-open",
		"--json",
		"--",
		"pi",
		...piArgs,
	];

	const res = await rex(pi, rexArgs, 15000);
	if (res.code !== 0) {
		ctx.ui.notify(`rex split failed: ${(res.stderr || res.stdout || "").trim().slice(0, 200)}`, "error");
		return undefined;
	}

	let blockId: string | undefined;
	try {
		const j = JSON.parse(res.stdout) as { block_ids?: string[]; blockIds?: string[] };
		blockId = j.block_ids?.[0] ?? j.blockIds?.[0];
	} catch {
		// pane still launched; we just can't track/focus it
	}

	launched.push({
		name: agentName,
		task,
		model: agent.model ?? "(inherited)",
		blockId,
		session: rc.session,
		startedAt: Date.now(),
	});
	updateStatus(ctx);
	return blockId;
}

function formatAge(ms: number): string {
	const s = Math.max(0, Math.round((Date.now() - ms) / 1000));
	if (s < 60) return `${s}s`;
	const m = Math.round(s / 60);
	if (m < 60) return `${m}m`;
	return `${Math.round(m / 60)}h`;
}

function updateStatus(ctx: ExtensionContext): void {
	const n = launched.length;
	if (n === 0) ctx.ui.setStatus("rex-agents", undefined);
	else ctx.ui.setStatus("rex-agents", ctx.ui.theme.fg("accent", `agents:${n}`));
}

async function showAgentsOverlay(pi: ExtensionAPI, ctx: ExtensionContext): Promise<void> {
	const rc = rexContext();
	if (launched.length === 0) {
		ctx.ui.notify("No agents launched yet. Use /agent <name> <task> or the spawn_agent tool.", "info");
		return;
	}

	const alive = rc ? await livingBlocks(pi, rc.session) : new Set<string>();
	const items: SelectItem[] = launched.map((a, i) => {
		const running = a.blockId ? alive.has(a.blockId) : false;
		const dot = running ? "●" : "○";
		const state = running ? "running" : "ended";
		return {
			value: String(i),
			label: `${dot} ${a.name}`,
			description: `${state} • ${a.model} • ${formatAge(a.startedAt)} • ${a.task.slice(0, 48)}`,
		};
	});

	const result = await ctx.ui.custom<string | null>(
		(tui, theme, _kb, done) => {
			const container = new Container();
			container.addChild(new DynamicBorder((s: string) => theme.fg("accent", s)));
			container.addChild(new Text(theme.fg("accent", theme.bold("Active agents")), 1, 0));
			const list = new SelectList(items, Math.min(items.length, 12), {
				selectedPrefix: (t) => theme.fg("accent", t),
				selectedText: (t) => theme.fg("accent", t),
				description: (t) => theme.fg("muted", t),
				scrollInfo: (t) => theme.fg("dim", t),
				noMatch: (t) => theme.fg("warning", t),
			});
			list.onSelect = (item) => done(item.value);
			list.onCancel = () => done(null);
			container.addChild(list);
			container.addChild(new Text(theme.fg("dim", "↑↓ navigate • enter focus pane • esc close"), 1, 0));
			container.addChild(new DynamicBorder((s: string) => theme.fg("accent", s)));
			return {
				render: (w: number) => container.render(w),
				invalidate: () => container.invalidate(),
				handleInput: (data: string) => {
					list.handleInput(data);
					tui.requestRender();
				},
			};
		},
		{ overlay: true },
	);

	if (result === null) return;
	const agent = launched[Number(result)];
	if (!agent) return;
	if (!rc) {
		ctx.ui.notify("Not inside a Rex session; cannot focus the pane.", "error");
		return;
	}
	if (!agent.blockId || !alive.has(agent.blockId)) {
		ctx.ui.notify(`"${agent.name}" pane is no longer running.`, "warning");
		return;
	}
	const r = await rex(pi, ["focus", "-s", agent.session, agent.blockId]);
	if (r.code !== 0) ctx.ui.notify(`Couldn't focus pane: ${(r.stderr || r.stdout).trim().slice(0, 160)}`, "error");
}

/**
 * Editor that opens the agents overlay on `left` — but only when the input is
 * empty and at least one agent has been launched. Any other time (text present,
 * or no agents) `left` is ordinary cursor movement, so editing is never
 * disrupted. This mirrors the Claude-Code left-arrow-on-empty gesture.
 */
class LeftArrowAgentsEditor extends CustomEditor {
	constructor(
		tui: ConstructorParameters<typeof CustomEditor>[0],
		theme: ConstructorParameters<typeof CustomEditor>[1],
		keybindings: ConstructorParameters<typeof CustomEditor>[2],
		private readonly onLeftOnEmpty: () => void,
	) {
		super(tui, theme, keybindings);
	}

	handleInput(data: string): void {
		if (matchesKey(data, "left") && this.getText() === "" && launched.length > 0) {
			this.onLeftOnEmpty();
			return;
		}
		super.handleInput(data);
	}
}

export default function rexAgentsExtension(pi: ExtensionAPI) {
	pi.on("session_start", (_event, ctx) => {
		ctx.ui.setEditorComponent(
			(tui, theme, keybindings) =>
				new LeftArrowAgentsEditor(tui, theme, keybindings, () => {
					void showAgentsOverlay(pi, ctx);
				}),
		);
	});

	pi.registerTool({
		name: "spawn_agent",
		label: "Spawn agent pane",
		description:
			"Launch a specialized sub-agent as its own interactive pi session in a Rex pane. " +
			"Use for parallel, long-running, or interactive work the user may want to watch or steer. " +
			"For quick isolated one-shot delegation that returns text inline, prefer the subagent tool instead.",
		promptGuidelines: [
			"Use spawn_agent when the user wants an agent running in a separate pane they can switch to.",
		],
		parameters: Type.Object({
			agent: Type.String({ description: "Agent name, e.g. implementer, repo-scout, security-reviewer" }),
			task: Type.String({ description: "The task for the agent" }),
			split: Type.Optional(StringEnum(["right", "left", "above", "below"] as const)),
			ratio: Type.Optional(Type.Number({ description: "New pane size, 1-99 percent", minimum: 1, maximum: 99 })),
		}),
		async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
			const blockId = await launchAgent(pi, ctx, params.agent, params.task, {
				split: params.split,
				ratio: params.ratio,
			});
			if (!blockId) {
				return { content: [{ type: "text", text: `Failed to launch "${params.agent}".` }] };
			}
			return {
				content: [{ type: "text", text: `Launched "${params.agent}" in a Rex pane (block ${blockId}).` }],
				details: { agent: params.agent, blockId },
			};
		},
	});

	pi.registerCommand("agent", {
		description: "Launch a sub-agent in a Rex pane: /agent <name> <task>",
		handler: async (args, ctx) => {
			const trimmed = (args ?? "").trim();
			const sp = trimmed.indexOf(" ");
			if (sp === -1) {
				ctx.ui.notify(`Usage: /agent <name> <task>. Agents: ${agentNames(ctx).join(", ") || "none"}`, "warning");
				return;
			}
			const name = trimmed.slice(0, sp);
			const task = trimmed.slice(sp + 1).trim();
			if (!task) {
				ctx.ui.notify("Provide a task: /agent <name> <task>", "warning");
				return;
			}
			await launchAgent(pi, ctx, name, task);
		},
	});

	pi.registerCommand("agents", {
		description: "List active agent panes and focus one",
		handler: async (_args, ctx) => {
			await showAgentsOverlay(pi, ctx);
		},
	});

	pi.registerShortcut(Key.ctrlShift("a"), {
		description: "List active agent panes",
		handler: async (ctx) => {
			await showAgentsOverlay(pi, ctx);
		},
	});
}
