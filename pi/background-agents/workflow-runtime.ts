/**
 * Runs a saved workflow script (the Claude Code `Workflow` format) against any
 * `agent()` implementation.
 *
 * A script is the body of an async function with the globals `args`, `agent`,
 * `parallel`, `phase` and `log`; `export const meta` is the only module syntax
 * it uses. Finished `agent()` calls can be cached by the caller so a run can be
 * resumed after a crash.
 */

import * as crypto from "node:crypto";

export interface AgentCallOptions {
	agentType?: string;
	schema?: unknown;
	model?: string;
	effort?: string;
	phase?: string;
	label?: string;
}

export interface StageCache {
	get(key: string): unknown | undefined;
	set(key: string, value: unknown): void;
}

export interface WorkflowHooks {
	agent(prompt: string, options: AgentCallOptions): Promise<unknown>;
	onPhase?(title: string): void;
	onLog?(message: string): void;
	onStage?(event: { key: string; options: AgentCallOptions; status: "start" | "done" | "cached" | "failed" }): void;
	cache?: StageCache;
}

const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor as new (
	...params: string[]
) => (...values: unknown[]) => Promise<unknown>;

export function stageKey(index: number, prompt: string, options: AgentCallOptions): string {
	const hash = crypto.createHash("sha1").update(prompt).digest("hex").slice(0, 12);
	return `${index}:${options.agentType ?? "-"}:${options.label ?? "-"}:${hash}`;
}

export async function runWorkflowSource(source: string, args: unknown, hooks: WorkflowHooks): Promise<unknown> {
	const body = source.replace(/^export const meta/m, "const meta");
	let index = 0;

	const agent = async (prompt: string, options: AgentCallOptions = {}) => {
		const key = stageKey(index++, prompt, options);
		const cached = hooks.cache?.get(key);
		if (cached !== undefined) {
			hooks.onStage?.({ key, options, status: "cached" });
			return cached;
		}
		hooks.onStage?.({ key, options, status: "start" });
		const value = await hooks.agent(prompt, options);
		if (value === null || value === undefined) {
			hooks.onStage?.({ key, options, status: "failed" });
			return null;
		}
		hooks.cache?.set(key, value);
		hooks.onStage?.({ key, options, status: "done" });
		return value;
	};
	const parallel = (fns: Array<() => Promise<unknown>>) => Promise.all(fns.map((f) => f()));
	const phase = (title: string) => hooks.onPhase?.(title);
	const log = (message: string) => hooks.onLog?.(message);

	const fn = new AsyncFunction("args", "agent", "parallel", "phase", "log", body);
	return fn(args, agent, parallel, phase, log);
}
