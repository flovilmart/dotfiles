/**
 * WebFetch and WebSearch for pi.
 * WebFetch: GET a URL, return readable text (HTML stripped). Claude summarises the
 *   page with a small model; here the page text is returned with the prompt and
 *   the calling model reads it.
 * WebSearch: Brave Search API when BRAVE_API_KEY is set, else DuckDuckGo HTML.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

const MAX_CHARS = 60_000;
const UA = "Mozilla/5.0 (compatible; pi-claude-compat)";

const decode = (s: string) =>
	s
		.replace(/&amp;/g, "&")
		.replace(/&lt;/g, "<")
		.replace(/&gt;/g, ">")
		.replace(/&quot;/g, '"')
		.replace(/&#39;|&apos;/g, "'")
		.replace(/&nbsp;/g, " ")
		.replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(Number(n)));

function htmlToText(html: string): string {
	return decode(
		html
			.replace(/<(script|style|noscript|svg|head)[\s\S]*?<\/\1>/gi, "")
			.replace(/<a\s[^>]*href="([^"#][^"]*)"[^>]*>([\s\S]*?)<\/a>/gi, "[$2]($1)")
			.replace(/<\/(p|div|h[1-6]|li|tr|br|section|article)>|<br\s*\/?>/gi, "\n")
			.replace(/<li[^>]*>/gi, "- ")
			.replace(/<[^>]+>/g, ""),
	)
		.replace(/[ \t]+/g, " ")
		.replace(/\n\s*\n\s*\n+/g, "\n\n")
		.trim();
}

const host = (u: string) => {
	try {
		return new URL(u).hostname.replace(/^www\./, "");
	} catch {
		return "";
	}
};

interface Hit {
	title: string;
	url: string;
	snippet: string;
}

async function braveSearch(query: string, key: string, signal?: AbortSignal): Promise<Hit[]> {
	const r = await fetch(`https://api.search.brave.com/res/v1/web/search?q=${encodeURIComponent(query)}&count=15`, {
		headers: { "X-Subscription-Token": key, Accept: "application/json" },
		signal,
	});
	if (!r.ok) throw new Error(`Brave search failed: HTTP ${r.status}`);
	const j = (await r.json()) as { web?: { results?: Array<{ title: string; url: string; description: string }> } };
	return (j.web?.results ?? []).map((x) => ({ title: decode(x.title.replace(/<[^>]+>/g, "")), url: x.url, snippet: decode((x.description ?? "").replace(/<[^>]+>/g, "")) }));
}

async function ddgSearch(query: string, signal?: AbortSignal): Promise<Hit[]> {
	const r = await fetch("https://html.duckduckgo.com/html/", {
		method: "POST",
		headers: { "User-Agent": UA, "Content-Type": "application/x-www-form-urlencoded" },
		body: `q=${encodeURIComponent(query)}`,
		signal,
	});
	if (!r.ok) throw new Error(`DuckDuckGo search failed: HTTP ${r.status}`);
	const html = await r.text();
	const hits: Hit[] = [];
	const re = /<a[^>]*class="result__a"[^>]*href="([^"]+)"[^>]*>([\s\S]*?)<\/a>[\s\S]*?(?:class="result__snippet"[^>]*>([\s\S]*?)<\/a>)?/g;
	for (let m = re.exec(html); m; m = re.exec(html)) {
		let url = decode(m[1]);
		const redirect = url.match(/[?&]uddg=([^&]+)/);
		if (redirect) url = decodeURIComponent(redirect[1]);
		if (url.startsWith("//")) url = `https:${url}`;
		hits.push({ title: decode(m[2].replace(/<[^>]+>/g, "")).trim(), url, snippet: decode((m[3] ?? "").replace(/<[^>]+>/g, "")).trim() });
	}
	return hits;
}

export function registerWeb(pi: ExtensionAPI) {
	pi.registerTool({
		name: "WebFetch",
		label: "WebFetch",
		description:
			"Fetch a URL and return its content as text (HTML converted). `prompt` says what to look for; read the returned text and answer it. " +
			"Fails on pages that need sign-in. HTTP URLs are upgraded to HTTPS.",
		promptSnippet: "Fetch a web page as text",
		parameters: Type.Object({
			url: Type.String({ description: "Fully formed URL" }),
			prompt: Type.String({ description: "What to extract from the page" }),
		}),
		async execute(_id, params, signal) {
			const url = params.url.replace(/^http:\/\//, "https://");
			const r = await fetch(url, { headers: { "User-Agent": UA, Accept: "text/html,text/markdown,text/plain,application/json,*/*" }, redirect: "follow", signal });
			if (!r.ok) return { content: [{ type: "text", text: `HTTP ${r.status} ${r.statusText} for ${r.url}` }], details: {}, isError: true };
			const type = r.headers.get("content-type") ?? "";
			const body = await r.text();
			let text = /html/i.test(type) ? htmlToText(body) : body;
			const truncated = text.length > MAX_CHARS;
			if (truncated) text = `${text.slice(0, MAX_CHARS)}\n\n[truncated at ${MAX_CHARS} characters]`;
			const note = r.url !== url && host(r.url) !== host(url) ? `NOTE: redirected to a different host: ${r.url}. Fetch it again to follow.\n\n` : "";
			return { content: [{ type: "text", text: `${note}Request: ${params.prompt}\nURL: ${r.url}\n\n${text}` }], details: { url: r.url, truncated } };
		},
	});

	pi.registerTool({
		name: "WebSearch",
		label: "WebSearch",
		description: "Search the web and return titles, URLs and snippets. Use for current information. Cite sources with their URLs in the answer.",
		promptSnippet: "Search the web",
		parameters: Type.Object({
			query: Type.String({ minLength: 2 }),
			allowed_domains: Type.Optional(Type.Array(Type.String(), { description: "Only include results from these domains" })),
			blocked_domains: Type.Optional(Type.Array(Type.String(), { description: "Never include results from these domains" })),
		}),
		async execute(_id, params, signal) {
			const key = process.env.BRAVE_API_KEY;
			let hits = key ? await braveSearch(params.query, key, signal) : await ddgSearch(params.query, signal);
			const inDomain = (h: string, d: string) => h === d || h.endsWith(`.${d}`);
			if (params.allowed_domains?.length) hits = hits.filter((x) => params.allowed_domains!.some((d) => inDomain(host(x.url), d)));
			if (params.blocked_domains?.length) hits = hits.filter((x) => !params.blocked_domains!.some((d) => inDomain(host(x.url), d)));
			const text = hits.length ? hits.slice(0, 10).map((h, i) => `${i + 1}. ${h.title}\n   ${h.url}\n   ${h.snippet}`).join("\n\n") : "No results.";
			return { content: [{ type: "text", text: `Search results for "${params.query}":\n\n${text}` }], details: { count: hits.length } };
		},
	});
}
