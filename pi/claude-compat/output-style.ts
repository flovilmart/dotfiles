/**
 * Claude Code output styles for pi. Styles are the markdown files in
 * ~/.claude/output-styles and <cwd>/.claude/output-styles. The active one is
 * appended to the system prompt. Default: `outputStyle` in ~/.claude/settings.json;
 * `/output-style <name|off>` overrides it (kept in ~/.pi/agent/claude-compat.json).
 */
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { type ExtensionAPI, getAgentDir } from "@earendil-works/pi-coding-agent";

interface Style {
	name: string;
	description: string;
	body: string;
}

function parseStyle(file: string): Style | undefined {
	let raw: string;
	try {
		raw = fs.readFileSync(file, "utf8");
	} catch {
		return;
	}
	const m = raw.match(/^---\n([\s\S]*?)\n---\n?([\s\S]*)$/);
	const front = m?.[1] ?? "";
	const body = (m?.[2] ?? raw).trim();
	const field = (k: string) => front.match(new RegExp(`^${k}:\\s*(.*)$`, "m"))?.[1]?.trim();
	return { name: field("name") ?? path.basename(file, ".md"), description: field("description") ?? "", body };
}

function loadStyles(cwd: string): Style[] {
	const dirs = [path.join(os.homedir(), ".claude", "output-styles"), path.join(cwd, ".claude", "output-styles")];
	const styles = new Map<string, Style>();
	for (const dir of dirs) {
		let files: string[] = [];
		try {
			files = fs.readdirSync(dir).filter((f) => f.endsWith(".md"));
		} catch {
			continue;
		}
		for (const f of files) {
			const s = parseStyle(path.join(dir, f));
			if (s) styles.set(s.name, s);
		}
	}
	return [...styles.values()];
}

const stateFile = () => path.join(getAgentDir(), "claude-compat.json");

function readState(): { outputStyle?: string | null } {
	try {
		return JSON.parse(fs.readFileSync(stateFile(), "utf8"));
	} catch {
		return {};
	}
}

function claudeDefault(): string | undefined {
	try {
		return JSON.parse(fs.readFileSync(path.join(os.homedir(), ".claude", "settings.json"), "utf8")).outputStyle;
	} catch {
		return;
	}
}

function activeName(): string | undefined {
	const s = readState();
	if (s.outputStyle === null) return undefined; // explicitly off
	return s.outputStyle ?? claudeDefault();
}

export function registerOutputStyle(pi: ExtensionAPI) {
	pi.on("before_agent_start", async (event, ctx) => {
		const name = activeName();
		if (!name || name === "default") return;
		const style = loadStyles(ctx.cwd).find((s) => s.name === name);
		if (!style) return;
		return { systemPrompt: `${event.systemPrompt}\n\n# Output style: ${style.name}\n\n${style.body}` };
	});

	pi.registerCommand("output-style", {
		description: "Choose a Claude output style (/output-style <name|off>)",
		getArgumentCompletions: (prefix: string) => {
			const items = [{ value: "off", label: "off" }, ...loadStyles(process.cwd()).map((s) => ({ value: s.name, label: s.name, description: s.description }))];
			const f = items.filter((i) => i.value.startsWith(prefix));
			return f.length ? f : null;
		},
		handler: async (args, ctx) => {
			const styles = loadStyles(ctx.cwd);
			const arg = (args ?? "").trim();
			if (!arg) {
				const cur = activeName();
				ctx.ui.notify(`Active: ${cur ?? "off"}. Available: ${styles.map((s) => s.name).join(", ") || "none"}, off`, "info");
				return;
			}
			if (arg === "off" || arg === "default") {
				fs.writeFileSync(stateFile(), JSON.stringify({ ...readState(), outputStyle: null }, null, 2));
				ctx.ui.notify("Output style off", "info");
				return;
			}
			if (!styles.some((s) => s.name === arg)) {
				ctx.ui.notify(`Unknown style "${arg}". Available: ${styles.map((s) => s.name).join(", ") || "none"}`, "error");
				return;
			}
			fs.writeFileSync(stateFile(), JSON.stringify({ ...readState(), outputStyle: arg }, null, 2));
			ctx.ui.notify(`Output style: ${arg} (applies from the next prompt)`, "info");
		},
	});
}
