/** Spawns one `pi` process as a sub-agent (JSON event stream) and collects its result. */

import { spawn } from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";

export interface UsageStats {
	input: number;
	output: number;
	cacheRead: number;
	cacheWrite: number;
	cost: number;
	turns: number;
}

export interface AgentRunOptions {
	cwd: string;
	task: string;
	systemPrompt?: string;
	model?: string;
	thinking?: string;
	tools?: string[];
	noTools?: boolean;
	signal?: AbortSignal;
	timeoutMs?: number;
	onActivity?: (summary: string) => void;
}

export interface AgentRunResult {
	ok: boolean;
	output: string;
	exitCode: number;
	stopReason?: string;
	error?: string;
	aborted: boolean;
	timedOut: boolean;
	model?: string;
	usage: UsageStats;
	durationMs: number;
}

export const emptyUsage = (): UsageStats => ({ input: 0, output: 0, cacheRead: 0, cacheWrite: 0, cost: 0, turns: 0 });

export function addUsage(into: UsageStats, add: UsageStats): void {
	into.input += add.input;
	into.output += add.output;
	into.cacheRead += add.cacheRead;
	into.cacheWrite += add.cacheWrite;
	into.cost += add.cost;
	into.turns += add.turns;
}

function piInvocation(args: string[]): { command: string; args: string[] } {
	const script = process.argv[1];
	if (script && !script.startsWith("/$bunfs/root/") && fs.existsSync(script)) {
		return { command: process.execPath, args: [script, ...args] };
	}
	const exec = path.basename(process.execPath).toLowerCase();
	if (/^(node|bun)(\.exe)?$/.test(exec)) return { command: "pi", args };
	return { command: process.execPath, args };
}

type Part = { type: string; text?: string; name?: string; arguments?: Record<string, unknown> };
type Msg = { role: string; content?: Part[]; usage?: Record<string, any>; model?: string; stopReason?: string; errorMessage?: string };

function lastAssistantText(messages: Msg[]): string {
	for (let i = messages.length - 1; i >= 0; i--) {
		const m = messages[i];
		if (m.role !== "assistant") continue;
		const text = (m.content ?? []).filter((p) => p.type === "text").map((p) => p.text ?? "").join("\n").trim();
		if (text) return text;
	}
	return "";
}

export async function runAgentProcess(options: AgentRunOptions): Promise<AgentRunResult> {
	const started = Date.now();
	const args = ["--mode", "json", "-p", "--no-session"];
	if (options.model) args.push("--model", options.model);
	if (options.thinking) args.push("--thinking", options.thinking);
	if (options.noTools) args.push("--no-tools");
	else if (options.tools && options.tools.length > 0) args.push("--tools", options.tools.join(","));

	let tmpDir: string | null = null;
	if (options.systemPrompt?.trim()) {
		tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "pi-bg-agent-"));
		const file = path.join(tmpDir, "system-prompt.md");
		fs.writeFileSync(file, options.systemPrompt, { encoding: "utf-8", mode: 0o600 });
		args.push("--append-system-prompt", file);
	}
	args.push(`Task: ${options.task}`);

	const messages: Msg[] = [];
	const usage = emptyUsage();
	let stderr = "";
	let model: string | undefined = options.model;
	let stopReason: string | undefined;
	let errorMessage: string | undefined;
	let aborted = false;
	let timedOut = false;

	const exitCode = await new Promise<number>((resolve) => {
		const inv = piInvocation(args);
		const proc = spawn(inv.command, inv.args, {
			cwd: options.cwd,
			shell: false,
			stdio: ["ignore", "pipe", "pipe"],
			env: { ...process.env, PI_BG_AGENTS_CHILD: "1" },
		});
		let buffer = "";

		const handle = (line: string) => {
			if (!line.trim()) return;
			let event: any;
			try {
				event = JSON.parse(line);
			} catch {
				return;
			}
			if (event.type === "message_end" && event.message) {
				const msg = event.message as Msg;
				messages.push(msg);
				if (msg.role === "assistant") {
					usage.turns++;
					usage.input += msg.usage?.input || 0;
					usage.output += msg.usage?.output || 0;
					usage.cacheRead += msg.usage?.cacheRead || 0;
					usage.cacheWrite += msg.usage?.cacheWrite || 0;
					usage.cost += msg.usage?.cost?.total || 0;
					model ??= msg.model;
					if (msg.stopReason) stopReason = msg.stopReason;
					if (msg.errorMessage) errorMessage = msg.errorMessage;
					const call = (msg.content ?? []).filter((p) => p.type === "toolCall").pop();
					options.onActivity?.(call ? `${call.name}` : "thinking");
				}
			}
		};

		proc.stdout.on("data", (d) => {
			buffer += d.toString();
			const lines = buffer.split("\n");
			buffer = lines.pop() || "";
			for (const l of lines) handle(l);
		});
		proc.stderr.on("data", (d) => {
			stderr += d.toString();
		});
		proc.on("close", (code) => {
			if (buffer.trim()) handle(buffer);
			resolve(code ?? 0);
		});
		proc.on("error", (err) => {
			stderr += String(err);
			resolve(1);
		});

		const kill = () => {
			proc.kill("SIGTERM");
			setTimeout(() => {
				if (proc.exitCode === null) proc.kill("SIGKILL");
			}, 5000);
		};
		if (options.signal) {
			const onAbort = () => {
				aborted = true;
				kill();
			};
			if (options.signal.aborted) onAbort();
			else options.signal.addEventListener("abort", onAbort, { once: true });
		}
		if (options.timeoutMs) {
			const timer = setTimeout(() => {
				timedOut = true;
				kill();
			}, options.timeoutMs);
			proc.on("close", () => clearTimeout(timer));
		}
	});

	if (tmpDir) fs.rmSync(tmpDir, { recursive: true, force: true });

	const output = lastAssistantText(messages);
	const failed = exitCode !== 0 || stopReason === "error" || stopReason === "aborted" || aborted || timedOut;
	return {
		ok: !failed,
		output,
		exitCode,
		stopReason,
		error: failed ? errorMessage || stderr.trim().slice(-2000) || output || "(no output)" : undefined,
		aborted,
		timedOut,
		model,
		usage,
		durationMs: Date.now() - started,
	};
}

export class Semaphore {
	private waiting: Array<() => void> = [];
	private active = 0;
	constructor(private readonly limit: number) {}
	async run<T>(fn: () => Promise<T>): Promise<T> {
		if (this.active >= this.limit) await new Promise<void>((resolve) => this.waiting.push(resolve));
		this.active++;
		try {
			return await fn();
		} finally {
			this.active--;
			this.waiting.shift()?.();
		}
	}
}
