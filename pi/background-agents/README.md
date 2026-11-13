# background-agents (pi only)

Non-blocking sub-agents and saved workflows for pi. Claude Code is unaffected: nothing shared under `~/.claude` changes.

| Tool | Purpose |
| --- | --- |
| `Agent` | Claude-compatible `{ description, prompt, subagent_type, run_in_background }`. In the background it returns at once; the session is woken with the report when the child finishes. |
| `Workflow` | `{ scriptPath, args, resumeFromRunId }`. Runs `~/.claude/workflows/*.js` unchanged (`args`, `agent`, `parallel`, `phase`, `log`). Always background. Finished stages are cached per run id. |
| `AgentJobs` | `list`, `status <id>`, `wait [id]`, `cancel <id>`, `result <id>`. |
| `/bg` | list jobs |

Why: pi's inline `subagent` tool blocks the caller's turn, and every wait longer than the prompt-cache TTL makes the next turn rewrite the whole context. Measured on two coordinator sessions: 36 and 146 minutes blocked in `subagent`.

Details
- Agents, model aliases (`sonnet`, `opus`, per-agent pi overrides) and tool names come from `../lib/agents.ts`.
- Structured output (`schema`): the agent is asked for one fenced JSON block, which is parsed and checked for required keys and enums; one tool-less repair pass runs if it does not parse. A stage that still fails returns `null`, which the scripts treat as `FAILED`.
- At most `PI_BG_CONCURRENCY` (4) children run at once; each is killed after `PI_BG_AGENT_TIMEOUT_MIN` (60) minutes.
- Results and stage caches live in `~/.pi/agent/background-agents/<id>/` (`result.md`, `meta.json`, `stages.json`).
- Children set `PI_BG_AGENTS_CHILD=1` and do not load this extension, so they cannot recurse.
- Jobs are killed on `session_shutdown`. After a restart, resume a workflow with `resumeFromRunId`.

Install: `install.sh` links every `pi/<name>/` folder into `~/.pi/agent/extensions/<name>`.
Test: `node --test pi/background-agents/test/runtime.test.mjs`
