import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import test from 'node:test'
import { runWorkflowSource } from '../workflow-runtime.ts'
import { parseStructured, repairTask } from '../structured.ts'

const wf = (name) => fs.readFileSync(path.join(os.homedir(), '.claude/workflows', name), 'utf8')
const planArgs = { ticket: 'T-1', worktree: '/tmp/wt', spec: 'spec', profile: 'profile', baseBranch: 'b', branchPattern: '{linear_branch}-s{n}-{slug}', maxRounds: 2 }

const PLAN = { status: 'OK', flag: '', slices: [{ n: 1 }], report: 'plan' }
const APPROVE = { verdict: 'APPROVE', blocking: [], should: [], report: 'ok' }
const REVISE = { verdict: 'REVISE', blocking: [{ finding: 'x' }], should: [], report: 'no' }

function scripted(replies) {
  const calls = []
  const agent = async (prompt, o) => {
    calls.push(o.label)
    return replies[o.agentType].shift()
  }
  return { agent, calls }
}

test('plan.js approves through the pi runtime', async () => {
  const { agent, calls } = scripted({ 'slice-planner': [PLAN], 'design-challenger': [APPROVE] })
  const result = await runWorkflowSource(wf('plan.js'), planArgs, { agent })
  assert.equal(result.status, 'APPROVED')
  assert.deepEqual(calls, ['plan', 'challenge r1'])
})

test('plan.js revises once then approves', async () => {
  const { agent, calls } = scripted({ 'slice-planner': [PLAN, PLAN], 'design-challenger': [REVISE, APPROVE] })
  const result = await runWorkflowSource(wf('plan.js'), planArgs, { agent })
  assert.equal(result.status, 'APPROVED')
  assert.equal(result.rounds, 1)
  assert.deepEqual(calls, ['plan', 'challenge r1', 'revise r1', 'challenge r2'])
})

test('a null agent result fails the run like Claude does', async () => {
  const { agent } = scripted({ 'slice-planner': [null] })
  const result = await runWorkflowSource(wf('plan.js'), planArgs, { agent })
  assert.equal(result.status, 'FAILED')
})

test('resume replays finished stages from the cache', async () => {
  const store = {}
  const cache = { get: (k) => store[k], set: (k, v) => { store[k] = v } }
  const first = scripted({ 'slice-planner': [PLAN], 'design-challenger': [null] })
  await runWorkflowSource(wf('plan.js'), planArgs, { agent: first.agent, cache })
  const second = scripted({ 'slice-planner': [], 'design-challenger': [APPROVE] })
  const result = await runWorkflowSource(wf('plan.js'), planArgs, { agent: second.agent, cache })
  assert.equal(result.status, 'APPROVED')
  assert.deepEqual(second.calls, ['challenge r1'])
})

test('subtask.js runs under the runtime globals (parallel, phase, log)', async () => {
  const PASS = {
    implementer: { status: 'DONE', commits: [], uncertain: [], report: 'done' },
    'code-challenger': { verdict: 'APPROVE', blocking: [], should: [], nits: [], report: 'ok' },
    verifier: { result: 'PASS', changedLines: 100, report: 'pass' },
    'security-reviewer': { verdict: 'PASS', blocking: [], should: [], report: 'pass' },
    'smoke-tester': { result: 'PASS', report: 'pass' },
  }
  const agent = async (_p, o) => PASS[o.agentType]
  const args = { ticket: 'T-1', branch: 'b', base: 'main', worktree: '/tmp/wt', slice: { n: 1 }, spec: 's', profile: 'p', flag: '', security: true, smoke: true, maxRounds: 2, maxLines: 800 }
  const result = await runWorkflowSource(wf('subtask.js'), args, { agent, onPhase() {}, onLog() {} })
  assert.equal(result.status, 'READY')
})

const SCHEMA = { type: 'object', required: ['verdict'], properties: { verdict: { type: 'string', enum: ['APPROVE', 'REVISE'] } } }

test('structured output: fenced block, trailing prose ignored, last block wins', () => {
  const text = 'a\n```json\n{"verdict":"REVISE"}\n```\nthen\n```json\n{"verdict":"APPROVE","x":{"y":"}"}}\n```'
  assert.deepEqual(parseStructured(text, SCHEMA).value, { verdict: 'APPROVE', x: { y: '}' } })
})

test('structured output: bare object, missing key and bad enum are rejected', () => {
  assert.equal(parseStructured('done {"verdict":"APPROVE"}', SCHEMA).value.verdict, 'APPROVE')
  assert.equal(parseStructured('{"other":1}', SCHEMA).value, undefined)
  assert.match(parseStructured('{"verdict":"MAYBE"}', SCHEMA).problems.join(), /verdict must be one of/)
  assert.match(parseStructured('no json', SCHEMA).problems[0], /no JSON/)
  assert.match(repairTask('report', SCHEMA, ['x']), /REPORT\nreport/)
})
