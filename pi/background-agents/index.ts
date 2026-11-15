/**
 * background-agents — non-blocking sub-agents and saved workflows for pi.
 *
 * pi's inline `subagent` tool holds the calling session's turn until the child
 * finishes. A ticket coordinator that delegates every step that way sits idle
 * for hours, and each wait past the prompt-cache TTL makes the next turn rewrite
 * the whole context. This extension gives pi what Claude Code has:
 *
 * - Tool `Agent`      { description, prompt, subagent_type, run_in_background }
 *                     Claude-compatible. In the background it returns at once and
 *                     wakes the session with the result when the child finishes.
 * - Tool `Workflow`   { scriptPath, args, resumeFromRunId }
 *                     Runs the same saved scripts (~/.claude/workflows/*.js) with an
 *                     `agent()` backed by pi processes. Always in the background;
 *                     finished stages are cached per run id for resume.
 * - Tool `AgentJobs`  list | status | wait | cancel | result.
 * - Command `/bg`     list jobs.
 *
 * Agent definitions, model aliases and tool-name mapping come from the shared
 * `../lib/agents.ts`, so the shared Claude agent files work unchanged.
 * Children set PI_BG_AGENTS_CHILD=1 and do not load this extension.
 */

import * as crypto from "node:crypto";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { StringEnum } from "@earendil-works/pi-ai";
import { type ExtensionAPI, getAgentDir } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { type AgentConfig, discoverAgents, resolveModelAlias } from "../lib/agents.ts";
import { type AgentRunResult, addUsage, emptyUsage, runAgentProcess, Semaphore, type UsageStats } from "./run-agent.ts";
import { parseStructured, repairTask, schemaInstruction } from "./structured.ts";
import { runWorkflowSource, type StageCache } from "./workflow-runtime.ts";

const MAX_CONCURRENCY = Number.parseInt(process.env.PI_BG_CONCURRENCY ?? "4", 10);
const AGENT_TIMEOUT_MS = Number.parseInt(process.env.PI_BG_AGENT_TIMEOUT_MIN ?? "60", 10) * 60_000;
const INLINE_RESULT_CHARS = 40_000;
const THINKING_LEVELS = new Set(["off", "minimal", "low", "medium", "high", "xhigh", "max"]);

type JobStatus = "running" | "completed" | "failed" | "cancelled";

interface Job {
	id: string;
	kind: "agent" | "workflow";
	label: string;
	status: JobStatus;
	startedAt: number;
	endedAt?: number;
	usage: UsageStats;
	models: Set<string>;
	abort: AbortController;
	done: Promise<void>;
	activity?: string;
	phase?: string;
	stages: Array<{ label: string; agent: string; status: string }>;
	log: string[];
	dir: string;
	resultFile?: string;
}

interface DispatchDefaults {
	model?: string;
	thinking?: string;
}

const expandHome = (p: string) => (p.startsWith("~") ? path.join(os.homedir(), p.slice(1)) : p);
const shortId = (prefix: string) => `${prefix}-${crypto.randomUUID().slice(0, 8)}`;

function formatDuration(ms: number): string {
	const s = Math.round(ms / 1000);
	return s < 60 ? `${s}s` : `${Math.floor(s / 60)}m${String(s % 60).padStart(2, "0")}s`;
}

function formatUsage(u: UsageStats): string {
	return `${u.turns} turns · ↓${u.output} tok · $${u.cost.toFixed(2)}`;
}

const modelNote = (job: { models: Set<string> }) => (job.models.size ? ` · ${[...job.models].join(", ")}` : "");

function resolveSpec(
	agent: AgentConfig | undefined,
	defaults: DispatchDefaults,
	override?: { model?: string; effort?: string },
): { model?: string; thinking?: string } {
	const model = override?.model ? resolveModelAlias(override.model) : (agent?.model ?? defaults.model);
	const effort = override?.effort && THINKING_LEVELS.has(override.effort) ? override.effort : undefined;
	const inherits = !override?.model && !agent?.model;
	return { model, thinking: effort ?? (inherits ? defaults.thinking : undefined) };
}

export default function (pi: ExtensionAPI) {
	if (process.env.PI_BG_AGENTS_CHILD === "1") return;

	const baseDir = path.join(getAgentDir(), "background-agents");
	const semaphore = new Semaphore(MAX_CONCURRENCY);
	const jobs = new Map<string, Job>();
	let ui: { setStatus(key: string, text: string | undefined): void } | null = null;

	const refreshStatus = () => {
		const running = [...jobs.values()].filter((j) => j.status === "running").length;
		try {
			ui?.setStatus("bg-agents", running > 0 ? `⚙ ${running} background` : undefined);
		} catch {
			/* UI gone */
		}
	};

	// Claude-style SubagentStart/SubagentStop for the claude-compat hooks extension.
	const traced = async (agentType: string, run: () => Promise<AgentRunResult>): Promise<AgentRunResult> => {
		const agent_id = crypto.randomUUID().replace(/-/g, "").slice(0, 17);
		pi.events.emit("claude-compat:subagent", { phase: "start", agent_id, agent_type: agentType });
		try {
			const r = await run();
			pi.events.emit("claude-compat:subagent", { phase: "stop", agent_id, agent_type: agentType, last_assistant_message: r.output });
			return r;
		} catch (e) {
			pi.events.emit("claude-compat:subagent", { phase: "stop", agent_id, agent_type: agentType });
			throw e;
		}
	};

	const wake = (job: Job, text: string) => {
		try {
			pi.sendMessage(
				{ customType: "background-agent", content: text, display: true, details: { id: job.id, status: job.status } },
				{ deliverAs: "followUp", triggerTurn: true },
			);
		} catch {
			/* session is shutting down */
		}
	};

	const finish = (job: Job, status: JobStatus, body: string) => {
		job.status = status;
		job.endedAt = Date.now();
		job.activity = undefined;
		job.resultFile = path.join(job.dir, "result.md");
		fs.writeFileSync(job.resultFile, body);
		fs.writeFileSync(
			path.join(job.dir, "meta.json"),
			JSON.stringify({ id: job.id, kind: job.kind, label: job.label, status, models: [...job.models], usage: job.usage, ms: job.endedAt - job.startedAt }, null, 2),
		);
		refreshStatus();
		const inline = body.length > INLINE_RESULT_CHARS ? `${body.slice(0, INLINE_RESULT_CHARS)}\n\n[truncated, full text in ${job.resultFile}]` : body;
		wake(
			job,
			[
				`Background ${job.kind} ${job.id} (${job.label}) ${status} in ${formatDuration(job.endedAt - job.startedAt)} · ${formatUsage(job.usage)}${modelNote(job)}`,
				"",
				inline,
				"",
				`Full output: ${job.resultFile}`,
			].join("\n"),
		);
	};

	const newJob = (kind: Job["kind"], label: string, id = shortId(kind === "agent" ? "ag" : "wf")): Job => {
		const dir = path.join(baseDir, id);
		fs.mkdirSync(dir, { recursive: true });
		const job: Job = {
			id,
			kind,
			label,
			status: "running",
			startedAt: Date.now(),
			usage: emptyUsage(),
			models: new Set(),
			abort: new AbortController(),
			done: Promise.resolve(),
			stages: [],
			log: [],
			dir,
		};
		jobs.set(id, job);
		refreshStatus();
		return job;
	};

	const dispatchDefaults = (ctx: { model?: { provider: string; id: string }; thinkingLevel?: string }): DispatchDefaults => ({
		model: ctx.model ? `${ctx.model.provider}/${ctx.model.id}` : undefined,
		thinking: ctx.thinkingLevel,
	});

	pi.on("session_start", (_event, ctx) => {
		ui = ctx.hasUI ? (ctx.ui as typeof ui) : null;
		refreshStatus();
	});

	pi.on("session_shutdown", () => {
		for (const job of jobs.values()) if (job.status === "running") job.abort.abort();
	});

	// ---------------------------------------------------------------- Agent

	pi.registerTool({
		name: "Agent",
		label: "Agent",
		description: [
			"Launch a sub-agent with its own context window. Set run_in_background: true to return immediately:",
			"the session is woken with the agent's final report when it finishes, so end your turn instead of waiting.",
			"Foreground (default) blocks until the agent is done. Prefer background for anything longer than a minute,",
			"and launch independent agents in the same turn so they run in parallel.",
			"subagent_type names an agent from ~/.pi/agent/agents (repo-scout, implementer, verifier, ...); omit it for a general-purpose agent.",
		].join(" "),
		promptSnippet: "Launch a sub-agent, optionally in the background (run_in_background) so your turn is not blocked",
		promptGuidelines: [
			"Use Agent with run_in_background: true instead of subagent whenever you delegate work that takes more than a minute or when other work can proceed: the result wakes you as a follow-up message, so end your turn after launching instead of waiting.",
			"Use Agent to launch independent sub-agents in the same turn so they run in parallel; the blocking subagent tool serialises you behind each child.",
		],
		parameters: Type.Object({
			description: Type.String({ description: "Short label (3-6 words) shown in job lists" }),
			prompt: Type.String({ description: "The full task, including every piece of context the agent needs" }),
			subagent_type: Type.Optional(Type.String({ description: "Agent name, e.g. repo-scout" })),
			run_in_background: Type.Optional(Type.Boolean({ description: "Return at once; the result arrives as a follow-up message" })),
			cwd: Type.Optional(Type.String({ description: "Working directory for the agent (default: current)" })),
		}),

		async execute(_id, params, signal, onUpdate, ctx) {
			const agents = discoverAgents(ctx.cwd, "user").agents;
			const def = params.subagent_type ? agents.find((a) => a.name === params.subagent_type) : undefined;
			if (params.subagent_type && !def) {
				const names = agents.map((a) => a.name).join(", ") || "none";
				return { content: [{ type: "text", text: `Unknown subagent_type "${params.subagent_type}". Available: ${names}` }], details: {}, isError: true };
			}
			const spec = resolveSpec(def, dispatchDefaults(ctx));
			const runOptions = {
				cwd: params.cwd ?? ctx.cwd,
				task: params.prompt,
				systemPrompt: def?.systemPrompt,
				model: spec.model,
				thinking: spec.thinking,
				tools: def?.tools,
				timeoutMs: AGENT_TIMEOUT_MS,
			};

			if (!params.run_in_background) {
				const result = await traced(params.subagent_type ?? "general-purpose", () =>
					runAgentProcess({
						...runOptions,
						signal,
						onActivity: (a) => onUpdate?.({ content: [{ type: "text", text: `(${a}...)` }], details: {} }),
					}),
				);
				const text = result.ok ? result.output || "(no output)" : `Agent failed: ${result.error}`;
				return { content: [{ type: "text", text }], details: { usage: result.usage }, isError: !result.ok };
			}

			const job = newJob("agent", params.description);
			job.done = (async () => {
				const result = await semaphore.run(() =>
					traced(params.subagent_type ?? "general-purpose", () =>
						runAgentProcess({
							...runOptions,
							signal: job.abort.signal,
							onActivity: (a) => {
								job.activity = a;
							},
						}),
					),
				);
				addUsage(job.usage, result.usage);
				if (result.model) job.models.add(result.model);
				if (job.abort.signal.aborted && result.aborted) return finish(job, "cancelled", "(cancelled)");
				if (!result.ok) return finish(job, "failed", `FAILED: ${result.error}`);
				finish(job, "completed", result.output || "(no output)");
			})().catch((err) => finish(job, "failed", `FAILED: ${String(err)}`));

			return {
				content: [
					{
						type: "text",
						text: `Started background agent ${job.id} (${params.description}). It will report back as a follow-up message; end your turn now unless you have other independent work.`,
					},
				],
				details: { id: job.id },
			};
		},
	});

	// ------------------------------------------------------------- Workflow

	const loadCache = (file: string): Record<string, unknown> => {
		try {
			return JSON.parse(fs.readFileSync(file, "utf-8")) as Record<string, unknown>;
		} catch {
			return {};
		}
	};

	pi.registerTool({
		name: "Workflow",
		label: "Workflow",
		description: [
			"Run a saved workflow script (e.g. ~/.claude/workflows/plan.js or subtask.js) in the background.",
			"Returns a run id at once; the session is woken with the script's structured result when it finishes, so end your turn.",
			"resumeFromRunId replays finished stages of an earlier run from cache after a crash or a changed answer.",
		].join(" "),
		promptSnippet: "Run a saved workflow script (plan.js, subtask.js) in the background; the result arrives as a follow-up message",
		promptGuidelines: [
			"Use Workflow to run ~/.claude/workflows/*.js scripts; it returns a run id immediately, so record the run id and end your turn until the result message arrives.",
		],
		parameters: Type.Object({
			scriptPath: Type.String({ description: "Absolute path to the workflow script (~ is expanded)" }),
			args: Type.Optional(Type.Any({ description: "The script's `args` object" })),
			resumeFromRunId: Type.Optional(Type.String({ description: "Run id to resume from (finished stages come from cache)" })),
		}),

		async execute(_id, params, _signal, _onUpdate, ctx) {
			const scriptPath = expandHome(params.scriptPath);
			let source: string;
			try {
				source = fs.readFileSync(scriptPath, "utf-8");
			} catch (err) {
				return { content: [{ type: "text", text: `Cannot read ${scriptPath}: ${String(err)}` }], details: {}, isError: true };
			}
			const agents = discoverAgents(ctx.cwd, "user").agents;
			const defaults = dispatchDefaults(ctx);
			const name = path.basename(scriptPath, ".js");
			const runId = params.resumeFromRunId ?? shortId("wf");
			const job = newJob("workflow", name, runId);
			const cacheFile = path.join(job.dir, "stages.json");
			const stored = loadCache(cacheFile);
			const cache: StageCache = {
				get: (key) => stored[key],
				set: (key, value) => {
					stored[key] = value;
					fs.writeFileSync(cacheFile, JSON.stringify(stored));
				},
			};

			const runStage = async (prompt: string, options: { agentType?: string; schema?: unknown; model?: string; effort?: string; label?: string }) => {
				const def = options.agentType ? agents.find((a) => a.name === options.agentType) : undefined;
				if (options.agentType && !def) {
					job.log.push(`unknown agent type ${options.agentType}`);
					return null;
				}
				const spec = resolveSpec(def, defaults, options);
				const task = options.schema ? `${prompt}\n${schemaInstruction(options.schema)}` : prompt;
				const base = { cwd: ctx.cwd, systemPrompt: def?.systemPrompt, model: spec.model, thinking: spec.thinking, tools: def?.tools, timeoutMs: AGENT_TIMEOUT_MS, signal: job.abort.signal };
				const account = (r: AgentRunResult) => {
					addUsage(job.usage, r.usage);
					if (r.model) job.models.add(r.model);
				};
				const result = await semaphore.run(() => traced(options.agentType ?? "general-purpose", () => runAgentProcess({ ...base, task, onActivity: (a) => (job.activity = `${options.label ?? options.agentType}: ${a}`) })));
				account(result);
				if (!result.ok) {
					job.log.push(`${options.label ?? options.agentType} failed: ${result.error}`);
					return null;
				}
				if (!options.schema) return result.output;
				let parsed = parseStructured(result.output, options.schema);
				if (parsed.value === undefined) {
					job.log.push(`${options.label ?? options.agentType}: output not valid, repairing (${parsed.problems.join("; ")})`);
					const repair = await semaphore.run(() =>
						runAgentProcess({ cwd: ctx.cwd, task: repairTask(result.output, options.schema, parsed.problems), model: spec.model, noTools: true, timeoutMs: 10 * 60_000, signal: job.abort.signal }),
					);
					account(repair);
					parsed = repair.ok ? parseStructured(repair.output, options.schema) : parsed;
				}
				return parsed.value ?? null;
			};

			job.done = (async () => {
				try {
					const result = await runWorkflowSource(source, params.args, {
						cache,
						agent: runStage,
						onPhase: (title) => (job.phase = title),
						onLog: (message) => job.log.push(message),
						onStage: ({ options, status }) => {
							const label = options.label ?? options.agentType ?? "agent";
							const entry = job.stages.find((s) => s.label === label);
							if (entry) entry.status = status;
							else job.stages.push({ label, agent: options.agentType ?? "-", status });
						},
					});
					if (job.abort.signal.aborted) return finish(job, "cancelled", "(cancelled)");
					const status = (result as { status?: string } | null)?.status;
					const body = JSON.stringify(result, null, 2);
					const logs = job.log.length ? `\n\nLog:\n${job.log.map((l) => `- ${l}`).join("\n")}` : "";
					finish(job, "completed", `Workflow ${name} run ${runId} returned${status ? ` status ${status}` : ""}:\n\n${body}${logs}`);
				} catch (err) {
					finish(job, job.abort.signal.aborted ? "cancelled" : "failed", `FAILED: ${String(err)}\n\nResume with Workflow({ scriptPath, args, resumeFromRunId: "${runId}" }).`);
				}
			})();

			return {
				content: [
					{
						type: "text",
						text: `Started workflow ${name} in the background, run id ${runId}. Record the run id in your state file. The result arrives as a follow-up message; end your turn now.`,
					},
				],
				details: { runId },
			};
		},
	});

	// ------------------------------------------------------------- AgentJobs

	const describe = (job: Job, detailed: boolean): string => {
		const end = job.endedAt ?? Date.now();
		const head = `${job.id} · ${job.kind} · ${job.label} · ${job.status} · ${formatDuration(end - job.startedAt)} · ${formatUsage(job.usage)}${modelNote(job)}`;
		if (!detailed) return head;
		const lines = [head];
		if (job.phase) lines.push(`phase: ${job.phase}`);
		if (job.activity) lines.push(`now: ${job.activity}`);
		for (const s of job.stages) lines.push(`  ${s.status.padEnd(7)} ${s.label} (${s.agent})`);
		for (const l of job.log.slice(-8)) lines.push(`  log: ${l}`);
		if (job.resultFile) lines.push(`result: ${job.resultFile}`);
		return lines.join("\n");
	};

	pi.registerTool({
		name: "AgentJobs",
		label: "AgentJobs",
		description: "Inspect background agents and workflows started in this session: list, status <id>, wait [id] [timeoutSeconds], cancel <id>, result <id>. Waiting blocks the turn; prefer ending your turn and letting the result wake you.",
		parameters: Type.Object({
			action: StringEnum(["list", "status", "wait", "cancel", "result"] as const),
			id: Type.Optional(Type.String()),
			timeoutSeconds: Type.Optional(Type.Number({ description: "wait: give up after this many seconds (default 600)" })),
		}),

		async execute(_id, params) {
			const text = (t: string, isError = false) => ({ content: [{ type: "text" as const, text: t }], details: {}, isError });
			const job = params.id ? jobs.get(params.id) : undefined;
			if (params.action === "list") {
				return text([...jobs.values()].map((j) => describe(j, false)).join("\n") || "No background jobs in this session.");
			}
			if (!job && params.action !== "wait") return text(`Unknown job id ${params.id ?? "(none)"}`, true);
			switch (params.action) {
				case "status":
					return text(describe(job!, true));
				case "result":
					return text(job!.resultFile && fs.existsSync(job!.resultFile) ? fs.readFileSync(job!.resultFile, "utf-8") : "Still running.");
				case "cancel":
					job!.abort.abort();
					return text(`Cancelling ${job!.id}.`);
				case "wait": {
					const targets = job ? [job] : [...jobs.values()].filter((j) => j.status === "running");
					const timeout = new Promise<string>((resolve) => setTimeout(() => resolve("timeout"), (params.timeoutSeconds ?? 600) * 1000));
					const outcome = await Promise.race([Promise.all(targets.map((j) => j.done)).then(() => "done"), timeout]);
					return text(outcome === "timeout" ? "Timed out; still running:\n" + targets.filter((j) => j.status === "running").map((j) => describe(j, false)).join("\n") : targets.map((j) => describe(j, false)).join("\n") || "Nothing was running.");
				}
			}
			return text("Unknown action", true);
		},
	});

	pi.registerCommand("bg", {
		description: "List background agents and workflows",
		handler: async (_args, ctx) => {
			const lines = [...jobs.values()].map((j) => describe(j, true));
			ctx.ui.notify(lines.join("\n\n") || "No background jobs.", "info");
		},
	});
}
