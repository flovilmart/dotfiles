/**
 * LSP tool for pi, like Claude Code's typescript-lsp and pyright-lsp plugins.
 * One minimal stdio JSON-RPC client per (server, project root), started on first
 * use. TypeScript/JavaScript: typescript-language-server. Python: pyright-langserver.
 */
import { type ChildProcessWithoutNullStreams, spawn } from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";
import { pathToFileURL, fileURLToPath } from "node:url";
import { StringEnum } from "@earendil-works/pi-ai";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

interface ServerDef {
	id: string;
	cmd: string[];
	exts: string[];
	rootMarkers: string[];
	languageId: (ext: string) => string;
}

const SERVERS: ServerDef[] = [
	{
		id: "typescript",
		cmd: ["typescript-language-server", "--stdio"],
		exts: [".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs", ".mts", ".cts"],
		rootMarkers: ["tsconfig.json", "jsconfig.json", "package.json"],
		languageId: (e) => ({ ".ts": "typescript", ".mts": "typescript", ".cts": "typescript", ".tsx": "typescriptreact", ".jsx": "javascriptreact" })[e] ?? "javascript",
	},
	{
		id: "pyright",
		cmd: ["pyright-langserver", "--stdio"],
		exts: [".py", ".pyi"],
		rootMarkers: ["pyrightconfig.json", "pyproject.toml", "setup.py", "requirements.txt"],
		languageId: () => "python",
	},
];

function findRoot(file: string, markers: string[], fallback: string): string {
	let dir = path.dirname(file);
	let found: string | undefined;
	for (;;) {
		if (markers.some((m) => fs.existsSync(path.join(dir, m)))) found = dir; // keep outermost: monorepo root
		if (fs.existsSync(path.join(dir, ".git"))) return found ?? dir;
		const up = path.dirname(dir);
		if (up === dir) return found ?? fallback;
		dir = up;
	}
}

class LspClient {
	private proc: ChildProcessWithoutNullStreams;
	private buf = Buffer.alloc(0);
	private nextId = 1;
	private pending = new Map<number, { resolve: (v: unknown) => void; reject: (e: Error) => void }>();
	private opened = new Map<string, { version: number; text: string }>();
	ready: Promise<void>;
	dead = false;

	constructor(
		readonly def: ServerDef,
		readonly root: string,
	) {
		this.proc = spawn(def.cmd[0], def.cmd.slice(1), { cwd: root, stdio: ["pipe", "pipe", "pipe"] });
		this.proc.stdout.on("data", (d: Buffer) => this.onData(d));
		this.proc.stderr.on("data", () => {});
		const fail = (why: string) => {
			this.dead = true;
			for (const p of this.pending.values()) p.reject(new Error(why));
			this.pending.clear();
		};
		this.proc.on("error", (e) => fail(`${def.cmd[0]} failed to start: ${e.message}`));
		this.proc.on("exit", () => fail(`${def.cmd[0]} exited`));
		this.ready = this.init();
	}

	private async init() {
		await this.request("initialize", {
			processId: process.pid,
			rootUri: pathToFileURL(this.root).href,
			workspaceFolders: [{ uri: pathToFileURL(this.root).href, name: path.basename(this.root) }],
			capabilities: {
				workspace: { workspaceFolders: true, configuration: true, symbol: {} },
				textDocument: {
					synchronization: {},
					hover: { contentFormat: ["markdown", "plaintext"] },
					definition: { linkSupport: false },
					implementation: {},
					references: {},
					documentSymbol: { hierarchicalDocumentSymbolSupport: true },
					callHierarchy: {},
				},
			},
		});
		this.notify("initialized", {});
	}

	private send(msg: unknown) {
		const body = Buffer.from(JSON.stringify(msg));
		this.proc.stdin.write(`Content-Length: ${body.length}\r\n\r\n`);
		this.proc.stdin.write(body);
	}

	private onData(d: Buffer) {
		this.buf = Buffer.concat([this.buf, d]);
		for (;;) {
			const sep = this.buf.indexOf("\r\n\r\n");
			if (sep < 0) return;
			const len = Number(this.buf.subarray(0, sep).toString().match(/Content-Length:\s*(\d+)/i)?.[1]);
			if (!len || this.buf.length < sep + 4 + len) return;
			const msg = JSON.parse(this.buf.subarray(sep + 4, sep + 4 + len).toString());
			this.buf = this.buf.subarray(sep + 4 + len);
			this.onMessage(msg);
		}
	}

	private onMessage(msg: { id?: number; method?: string; result?: unknown; error?: { message: string }; params?: { items?: unknown[] } }) {
		if (msg.method && msg.id !== undefined) {
			// Server request: answer the ones that block servers.
			const result = msg.method === "workspace/configuration" ? (msg.params?.items ?? []).map(() => null) : null;
			this.send({ jsonrpc: "2.0", id: msg.id, result });
			return;
		}
		if (msg.id !== undefined) {
			const p = this.pending.get(msg.id);
			if (!p) return;
			this.pending.delete(msg.id);
			msg.error ? p.reject(new Error(msg.error.message)) : p.resolve(msg.result);
		}
	}

	request(method: string, params: unknown, timeoutMs = 30_000): Promise<unknown> {
		if (this.dead) return Promise.reject(new Error(`${this.def.cmd[0]} is not running`));
		const id = this.nextId++;
		return new Promise((resolve, reject) => {
			const t = setTimeout(() => {
				this.pending.delete(id);
				reject(new Error(`${method} timed out`));
			}, timeoutMs);
			this.pending.set(id, {
				resolve: (v) => (clearTimeout(t), resolve(v)),
				reject: (e) => (clearTimeout(t), reject(e)),
			});
			this.send({ jsonrpc: "2.0", id, method, params });
		});
	}

	notify(method: string, params: unknown) {
		if (!this.dead) this.send({ jsonrpc: "2.0", method, params });
	}

	async open(file: string, ext: string) {
		const text = fs.readFileSync(file, "utf8");
		const uri = pathToFileURL(file).href;
		const prev = this.opened.get(uri);
		if (!prev) {
			this.opened.set(uri, { version: 1, text });
			this.notify("textDocument/didOpen", { textDocument: { uri, languageId: this.def.languageId(ext), version: 1, text } });
		} else if (prev.text !== text) {
			const version = prev.version + 1;
			this.opened.set(uri, { version, text });
			this.notify("textDocument/didChange", { textDocument: { uri, version }, contentChanges: [{ text }] });
		}
		return uri;
	}

	stop() {
		try {
			this.notify("exit", {});
			this.proc.kill();
		} catch {
			/* gone */
		}
	}
}

type Loc = { uri?: string; targetUri?: string; range?: Range; targetSelectionRange?: Range; targetRange?: Range };
type Range = { start: { line: number; character: number }; end: unknown };
type Sym = { name: string; kind: number; range?: Range; selectionRange?: Range; children?: Sym[]; location?: Loc; containerName?: string };

const KINDS = ["", "File", "Module", "Namespace", "Package", "Class", "Method", "Property", "Field", "Constructor", "Enum", "Interface", "Function", "Variable", "Constant", "String", "Number", "Boolean", "Array", "Object", "Key", "Null", "EnumMember", "Struct", "Event", "Operator", "TypeParameter"];

const rel = (uri: string, cwd: string) => {
	try {
		const p = fileURLToPath(uri);
		return p.startsWith(cwd) ? path.relative(cwd, p) : p;
	} catch {
		return uri;
	}
};

function fmtLocs(res: unknown, cwd: string): string {
	const list = (Array.isArray(res) ? res : res ? [res] : []) as Loc[];
	if (!list.length) return "No results found.";
	return list
		.map((l) => {
			const uri = l.uri ?? l.targetUri ?? "";
			const r = l.range ?? l.targetSelectionRange ?? l.targetRange;
			return `${rel(uri, cwd)}:${(r?.start.line ?? 0) + 1}:${(r?.start.character ?? 0) + 1}`;
		})
		.join("\n");
}

function fmtSymbols(syms: Sym[], cwd: string, depth = 0): string[] {
	return syms.flatMap((s) => {
		const r = s.selectionRange ?? s.range ?? s.location?.range;
		const where = s.location?.uri ? `${rel(s.location.uri, cwd)}:` : "";
		const head = `${"  ".repeat(depth)}${s.name} (${KINDS[s.kind] ?? s.kind}) ${where}${r ? `line ${r.start.line + 1}` : ""}${s.containerName ? ` in ${s.containerName}` : ""}`;
		return [head, ...fmtSymbols(s.children ?? [], cwd, depth + 1)];
	});
}

function fmtHover(res: unknown): string {
	const c = (res as { contents?: unknown } | null)?.contents;
	if (!c) return "No hover information available.";
	const one = (x: unknown): string => (typeof x === "string" ? x : Array.isArray(x) ? x.map(one).join("\n\n") : ((x as { value?: string })?.value ?? ""));
	return one(c) || "No hover information available.";
}

export function registerLsp(pi: ExtensionAPI) {
	const clients = new Map<string, LspClient>();

	pi.on("session_shutdown", async () => {
		for (const c of clients.values()) c.stop();
		clients.clear();
	});

	pi.registerTool({
		name: "LSP",
		label: "LSP",
		description:
			"Code intelligence through language servers (TypeScript/JavaScript, Python). Positions are 1-based line and character, as shown by the read tool. " +
			"Operations: goToDefinition, findReferences, hover, documentSymbol, workspaceSymbol (query in `query`), goToImplementation, incomingCalls, outgoingCalls.",
		promptSnippet: "Definitions, references, hover and symbols through language servers",
		promptGuidelines: ["Use LSP for goToDefinition and findReferences on TypeScript, JavaScript and Python code before relying on text search."],
		parameters: Type.Object({
			operation: StringEnum(["goToDefinition", "findReferences", "hover", "documentSymbol", "workspaceSymbol", "goToImplementation", "incomingCalls", "outgoingCalls"] as const),
			filePath: Type.String({ description: "File to query (absolute or relative to cwd). For workspaceSymbol it selects the project." }),
			line: Type.Optional(Type.Number({ description: "1-based line" })),
			character: Type.Optional(Type.Number({ description: "1-based character" })),
			query: Type.Optional(Type.String({ description: "Symbol query for workspaceSymbol" })),
		}),
		async execute(_id, params, _signal, _onUpdate, ctx) {
			const err = (text: string) => ({ content: [{ type: "text" as const, text }], details: {}, isError: true });
			const file = path.resolve(ctx.cwd, params.filePath);
			if (!fs.existsSync(file)) return err(`File not found: ${file}`);
			const ext = path.extname(file);
			const def = SERVERS.find((s) => s.exts.includes(ext));
			if (!def) return err(`No language server for ${ext || "this file"}. Supported: ${SERVERS.flatMap((s) => s.exts).join(" ")}`);
			const root = findRoot(file, def.rootMarkers, ctx.cwd);
			const key = `${def.id}:${root}`;
			let client = clients.get(key);
			if (!client || client.dead) {
				client = new LspClient(def, root);
				clients.set(key, client);
			}
			try {
				await client.ready;
				const uri = await client.open(file, ext);
				const textDocument = { uri };
				const op = params.operation;
				if (op === "workspaceSymbol") {
					const res = (await client.request("workspace/symbol", { query: params.query ?? "" })) as Sym[] | null;
					return { content: [{ type: "text", text: res?.length ? fmtSymbols(res.slice(0, 100), ctx.cwd).join("\n") : "No symbols found." }], details: {} };
				}
				if (op === "documentSymbol") {
					const res = (await client.request("textDocument/documentSymbol", { textDocument })) as Sym[] | null;
					return { content: [{ type: "text", text: res?.length ? fmtSymbols(res, ctx.cwd).join("\n") : "No symbols found." }], details: {} };
				}
				if (!params.line || !params.character) return err(`${op} needs line and character (1-based).`);
				const position = { line: params.line - 1, character: params.character - 1 };
				let text: string;
				switch (op) {
					case "goToDefinition":
						text = fmtLocs(await client.request("textDocument/definition", { textDocument, position }), ctx.cwd);
						break;
					case "goToImplementation":
						text = fmtLocs(await client.request("textDocument/implementation", { textDocument, position }), ctx.cwd);
						break;
					case "findReferences":
						text = fmtLocs(await client.request("textDocument/references", { textDocument, position, context: { includeDeclaration: true } }), ctx.cwd);
						break;
					case "hover":
						text = fmtHover(await client.request("textDocument/hover", { textDocument, position }));
						break;
					default: {
						const items = (await client.request("textDocument/prepareCallHierarchy", { textDocument, position })) as unknown[] | null;
						if (!items?.length) {
							text = "No call hierarchy item at this position.";
							break;
						}
						const method = op === "incomingCalls" ? "callHierarchy/incomingCalls" : "callHierarchy/outgoingCalls";
						const calls = ((await client.request(method, { item: items[0] })) as Array<{ from?: Sym & { uri: string }; to?: Sym & { uri: string } }> | null) ?? [];
						text = calls.length
							? calls
									.map((c) => {
										const s = (c.from ?? c.to)!;
										return `${s.name} ${rel(s.uri, ctx.cwd)}:${(s.selectionRange?.start.line ?? 0) + 1}`;
									})
									.join("\n")
							: "No calls found.";
					}
				}
				return { content: [{ type: "text", text }], details: {} };
			} catch (e) {
				return err(`LSP ${params.operation} failed: ${e instanceof Error ? e.message : String(e)}`);
			}
		},
	});
}
