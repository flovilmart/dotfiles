/**
 * Claude Code hooks for pi. Reads `hooks` from ~/.claude/settings.json (and the
 * project's .claude/settings.json + settings.local.json) and runs them on the
 * matching pi events, with Claude's stdin JSON. Same scripts, same log.jsonl.
 *
 * Mapped: SessionStart, SessionEnd, UserPromptSubmit, PreToolUse (exit 2 or a
 * deny decision blocks), PostToolUse, Stop, SubagentStart, SubagentStop.
 * Subagent events come from background-agents over pi.events.
 * Skipped: commands with `--agent claude` (registers the session with rex as a
 * Claude session; wrong for pi).
 */
import { spawn } from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

interface HookCmd {
	type?: string;
	command?: string;
	timeout?: number;
}
interface HookGroup {
	matcher?: string;
	hooks?: HookCmd[];
}
type HookConfig = Record<string, HookGroup[]>;

const TOOL_NAMES: Record<string, string> = { bash: "Bash", read: "Read", edit: "Edit", write: "Write", grep: "Grep", find: "Glob", ls: "LS" };
const claudeToolName = (n: string) => TOOL_NAMES[n] ?? n;

function claudeToolInput(tool: string, input: Record<string, unknown>): Record<string, unknown> {
	if (["read", "edit", "write"].includes(tool) && input && "path" in input) {
		const { path: p, ...rest } = input;
		return { file_path: p, ...rest };
	}
	return input;
}

function readHooks(file: string): HookConfig {
	try {
		const parsed = JSON.parse(fs.readFileSync(file, "utf8"));
		return parsed?.hooks && typeof parsed.hooks === "object" ? parsed.hooks : {};
	} catch {
		return {};
	}
}

function loadHooks(cwd: string): HookConfig {
	const merged: HookConfig = {};
	const files = [
		path.join(os.homedir(), ".claude", "settings.json"),
		path.join(cwd, ".claude", "settings.json"),
		path.join(cwd, ".claude", "settings.local.json"),
	];
	for (const f of files) {
		for (const [event, groups] of Object.entries(readHooks(f))) {
			if (Array.isArray(groups)) (merged[event] ??= []).push(...groups);
		}
	}
	return merged;
}

const expandHome = (c: string) => c.replace(/^~(?=\/)/, os.homedir()).replace(/(\s)~(?=\/)/g, `$1${os.homedir()}`);

function matches(matcher: string | undefined, name: string | undefined): boolean {
	if (!matcher || matcher === "*") return true;
	if (!name) return false;
	try {
		return new RegExp(`^(?:${matcher})$`).test(name);
	} catch {
		return matcher === name;
	}
}

interface RunResult {
	code: number;
	stdout: string;
	stderr: string;
}

function runCommand(command: string, input: unknown, cwd: string, timeoutSec: number): Promise<RunResult> {
	return new Promise((resolve) => {
		const proc = spawn("/bin/sh", ["-c", expandHome(command)], {
			cwd,
			env: { ...process.env, CLAUDE_PROJECT_DIR: cwd },
			stdio: ["pipe", "pipe", "pipe"],
		});
		let stdout = "";
		let stderr = "";
		const timer = setTimeout(() => proc.kill("SIGKILL"), timeoutSec * 1000);
		proc.stdout.on("data", (d) => (stdout += d));
		proc.stderr.on("data", (d) => (stderr += d));
		proc.on("error", () => {
			clearTimeout(timer);
			resolve({ code: 1, stdout, stderr });
		});
		proc.on("close", (code) => {
			clearTimeout(timer);
			resolve({ code: code ?? 1, stdout, stderr });
		});
		proc.stdin.on("error", () => {});
		proc.stdin.end(JSON.stringify(input));
	});
}

export function registerHooks(pi: ExtensionAPI) {
	const base = (ctx: ExtensionContext, event: string) => ({
		session_id: ctx.sessionManager.getSessionId?.() ?? "pi",
		transcript_path: ctx.sessionManager.getSessionFile?.() ?? "",
		cwd: ctx.cwd,
		hook_event_name: event,
	});

	async function fire(event: string, ctx: ExtensionContext, extra: Record<string, unknown>, toolName?: string): Promise<RunResult | undefined> {
		const groups = loadHooks(ctx.cwd)[event];
		if (!groups?.length) return;
		const input = { ...base(ctx, event), ...extra };
		for (const group of groups) {
			if (!matches(group.matcher, toolName)) continue;
			for (const h of group.hooks ?? []) {
				if (h.type && h.type !== "command") continue;
				if (!h.command || h.command.includes("--agent claude")) continue;
				const r = await runCommand(h.command, input, ctx.cwd, h.timeout ?? 60);
				if (event === "PreToolUse") {
					let denied = r.code === 2;
					let reason = r.stderr.trim();
					try {
						const out = JSON.parse(r.stdout);
						const d = out?.hookSpecificOutput?.permissionDecision ?? out?.decision;
						if (d === "deny" || d === "block") {
							denied = true;
							reason = out?.hookSpecificOutput?.permissionDecisionReason ?? out?.reason ?? reason;
						}
					} catch {
						/* not JSON */
					}
					if (denied) return { ...r, code: 2, stderr: reason || "Blocked by hook" };
				}
			}
		}
	}

	pi.on("session_start", async (event, ctx) => {
		const source = event.reason === "startup" ? "startup" : event.reason === "resume" ? "resume" : event.reason === "reload" ? "startup" : "clear";
		await fire("SessionStart", ctx, { source });
	});
	pi.on("session_shutdown", async (_event, ctx) => {
		await fire("SessionEnd", ctx, { reason: "other" });
	});
	pi.on("input", async (event, ctx) => {
		if (event.source !== "interactive") return;
		await fire("UserPromptSubmit", ctx, { prompt: event.text });
	});
	pi.on("tool_call", async (event, ctx) => {
		const r = await fire(
			"PreToolUse",
			ctx,
			{ tool_name: claudeToolName(event.toolName), tool_input: claudeToolInput(event.toolName, event.input as Record<string, unknown>), tool_use_id: event.toolCallId },
			claudeToolName(event.toolName),
		);
		if (r?.code === 2) return { block: true, reason: r.stderr };
	});
	pi.on("tool_result", async (event, ctx) => {
		await fire(
			"PostToolUse",
			ctx,
			{
				tool_name: claudeToolName(event.toolName),
				tool_input: claudeToolInput(event.toolName, event.input as Record<string, unknown>),
				tool_response: { content: event.content, is_error: event.isError },
				tool_use_id: event.toolCallId,
			},
			claudeToolName(event.toolName),
		);
	});
	pi.on("agent_settled", async (_event, ctx) => {
		await fire("Stop", ctx, { stop_hook_active: false });
	});

	// Subagent lifecycle, emitted by background-agents.
	let lastCtx: ExtensionContext | undefined;
	pi.on("session_start", (_e, ctx) => void (lastCtx = ctx));
	pi.events.on("claude-compat:subagent", (data: unknown) => {
		const d = data as { phase: "start" | "stop"; agent_id: string; agent_type: string; last_assistant_message?: string };
		if (!lastCtx) return;
		const { phase, ...rest } = d;
		void fire(phase === "start" ? "SubagentStart" : "SubagentStop", lastCtx, rest);
	});
}
