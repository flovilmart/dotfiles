/**
 * claude-compat — make pi behave like Claude Code, driven by ~/.claude.
 *
 * - hooks.ts         Claude hooks (settings.json) on pi events
 * - output-style.ts  ~/.claude/output-styles, /output-style
 * - todo.ts          TodoWrite
 * - web.ts           WebFetch, WebSearch
 * - lsp.ts           LSP (typescript, python)
 * - plugins.ts       enabled Claude plugins: skills, commands, MCP servers
 *
 * Background-agent children (PI_BG_AGENTS_CHILD=1) get the tools only: no hooks,
 * no output style, no plugin resources.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { registerHooks } from "./hooks.ts";
import { registerLsp } from "./lsp.ts";
import { registerOutputStyle } from "./output-style.ts";
import { registerPlugins } from "./plugins.ts";
import { registerTodo } from "./todo.ts";
import { registerWeb } from "./web.ts";

export default function (pi: ExtensionAPI) {
	registerTodo(pi);
	registerWeb(pi);
	registerLsp(pi);
	if (process.env.PI_BG_AGENTS_CHILD === "1") return;
	registerHooks(pi);
	registerOutputStyle(pi);
	registerPlugins(pi);
}
