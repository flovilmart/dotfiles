/** Structured output for workflow agents: ask for JSON, parse it, check the required keys. */

export function schemaInstruction(schema: unknown): string {
	return [
		"",
		"OUTPUT FORMAT",
		"End your final message with exactly one fenced ```json block holding a single JSON object that conforms to the JSON Schema below. Put nothing after the block. Every key listed in `required` must be present; use the enum values verbatim.",
		"```json-schema",
		JSON.stringify(schema, null, 2),
		"```",
	].join("\n");
}

function balancedObjects(text: string): string[] {
	const found: string[] = [];
	for (let start = text.indexOf("{"); start !== -1; start = text.indexOf("{", start + 1)) {
		let depth = 0;
		let inString = false;
		let escaped = false;
		for (let i = start; i < text.length; i++) {
			const c = text[i];
			if (inString) {
				if (escaped) escaped = false;
				else if (c === "\\") escaped = true;
				else if (c === '"') inString = false;
				continue;
			}
			if (c === '"') inString = true;
			else if (c === "{") depth++;
			else if (c === "}" && --depth === 0) {
				found.push(text.slice(start, i + 1));
				break;
			}
		}
	}
	return found;
}

function candidates(text: string): string[] {
	const fenced = [...text.matchAll(/```json\s*\n([\s\S]*?)```/g)].map((m) => m[1].trim());
	const objects = balancedObjects(text).reverse();
	return [...fenced.reverse(), ...objects];
}

export function missingRequired(value: unknown, schema: unknown): string[] {
	const required = (schema as { required?: string[] } | null)?.required ?? [];
	if (typeof value !== "object" || value === null || Array.isArray(value)) return ["(not an object)"];
	return required.filter((key) => !(key in (value as Record<string, unknown>)));
}

export function enumViolations(value: unknown, schema: unknown): string[] {
	const props = (schema as { properties?: Record<string, { enum?: unknown[] }> } | null)?.properties ?? {};
	if (typeof value !== "object" || value === null) return [];
	const record = value as Record<string, unknown>;
	return Object.entries(props)
		.filter(([key, def]) => def.enum && key in record && !def.enum.includes(record[key]))
		.map(([key, def]) => `${key} must be one of ${JSON.stringify(def.enum)}`);
}

export function parseStructured(text: string, schema: unknown): { value?: unknown; problems: string[] } {
	let problems = ["no JSON object found"];
	for (const raw of candidates(text)) {
		let parsed: unknown;
		try {
			parsed = JSON.parse(raw);
		} catch {
			problems = ["JSON did not parse"];
			continue;
		}
		const issues = [...missingRequired(parsed, schema), ...enumViolations(parsed, schema)];
		if (issues.length === 0) return { value: parsed, problems: [] };
		problems = issues;
	}
	return { problems };
}

export function repairTask(previous: string, schema: unknown, problems: string[]): string {
	return [
		"Convert the report below into the JSON object described by the schema. Use only facts that are in the report; if a required field has no basis in the report, use an empty value of its type (and for a verdict or status, the most cautious valid value).",
		`Problems with the previous attempt: ${problems.join("; ")}`,
		schemaInstruction(schema),
		"",
		"REPORT",
		previous.slice(-60_000),
	].join("\n");
}
