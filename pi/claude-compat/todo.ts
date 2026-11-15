/**
 * TodoWrite for pi, same schema as Claude Code. State rides in tool result
 * details, so branching and resuming restore it. The list shows as a widget.
 */
import { StringEnum } from "@earendil-works/pi-ai";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

interface Todo {
	content: string;
	status: "pending" | "in_progress" | "completed";
	activeForm: string;
}

const MARK = { pending: "☐", in_progress: "◐", completed: "☑" } as const;

export function registerTodo(pi: ExtensionAPI) {
	let todos: Todo[] = [];

	const render = (ctx: ExtensionContext) => {
		if (!ctx.hasUI) return;
		const open = todos.some((t) => t.status !== "completed");
		ctx.ui.setWidget(
			"todos",
			open ? todos.map((t) => `${MARK[t.status]} ${t.status === "in_progress" ? t.activeForm : t.content}`) : undefined,
			{ placement: "belowEditor" },
		);
	};

	const restore = (ctx: ExtensionContext) => {
		todos = [];
		for (const entry of ctx.sessionManager.getBranch()) {
			if (entry.type !== "message") continue;
			const msg = entry.message;
			if (msg.role === "toolResult" && msg.toolName === "TodoWrite") {
				const d = msg.details as { todos?: Todo[] } | undefined;
				if (d?.todos) todos = d.todos;
			}
		}
		render(ctx);
	};
	pi.on("session_start", async (_e, ctx) => restore(ctx));
	pi.on("session_tree", async (_e, ctx) => restore(ctx));

	pi.registerTool({
		name: "TodoWrite",
		label: "TodoWrite",
		description:
			"Create and update the task list for the current session. Send the complete list every time. " +
			"Use it for work with 3 or more steps. Keep exactly one task in_progress. Mark a task completed as soon as it is done.",
		promptSnippet: "Track multi-step work in a task list",
		promptGuidelines: ["Use TodoWrite to plan and track tasks that need 3 or more steps, and update it as each step finishes."],
		parameters: Type.Object({
			todos: Type.Array(
				Type.Object({
					content: Type.String({ minLength: 1, description: "Imperative form, e.g. 'Run tests'" }),
					status: StringEnum(["pending", "in_progress", "completed"] as const),
					activeForm: Type.String({ minLength: 1, description: "Present continuous form, e.g. 'Running tests'" }),
				}),
			),
		}),
		async execute(_id, params, _signal, _onUpdate, ctx) {
			todos = params.todos as Todo[];
			render(ctx);
			return {
				content: [{ type: "text", text: "Todos updated. Continue with the current task list." }],
				details: { todos },
			};
		},
	});

	pi.registerCommand("todos", {
		description: "Show the task list",
		handler: async (_a, ctx) => {
			ctx.ui.notify(todos.length ? todos.map((t) => `${MARK[t.status]} ${t.content}`).join("\n") : "No todos", "info");
		},
	});
}
