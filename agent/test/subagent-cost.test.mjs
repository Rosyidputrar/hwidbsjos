// Subagent cost: pi's own per-request cost (usage.cost) moves the total as
// each request ends, and the record names the model and thinking level.
// Uses a scripted fake session; no network.
import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, rmSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { build } from "esbuild";

const here = dirname(fileURLToPath(import.meta.url));
mkdirSync(join(here, "..", "build"), { recursive: true });
const out = mkdtempSync(join(here, "..", "build", "subagent-test-"));
async function bundle(name) {
	const outfile = join(out, `${name}.mjs`);
	await build({ entryPoints: [join(here, "..", "src", `${name}.ts`)], outfile, bundle: true, platform: "node", format: "esm", packages: "external", logLevel: "error" });
	return import(pathToFileURL(outfile).href);
}
const { SubagentManager } = await bundle("subagent");

/** A session that replays [steps] (assistant messages) when prompted. */
function fakeSession(steps, model = { provider: "mock", id: "claude-opus-5.5", name: "Claude Opus 5.5" }) {
	let listener;
	const totals = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 };
	return {
		model,
		thinkingLevel: "high",
		subscribe(fn) {
			listener = fn;
			return () => {};
		},
		async prompt() {
			listener({ type: "agent_start" });
			for (const m of steps) {
				for (const k of Object.keys(totals)) totals[k] += m.usage[k] ?? 0;
				listener({ type: "message_end", message: { role: "assistant", model: model.id, ...m } });
			}
			listener({ type: "agent_end" });
			// pi's run boundary: the session is idle only from here on.
			listener({ type: "agent_settled", aborted: false });
		},
		getSessionStats: () => ({ tokens: { ...totals } }),
		getLastAssistantText: () => "Laporan",
		abort() {},
		dispose() {},
	};
}

function manager(session) {
	const sent = [];
	const m = new SubagentManager({
		send: (r) => sent.push(r),
		wireEvent: (e) => e,
		createSession: async () => session,
		limits: () => ({ costLimit: 0, minutesLimit: 0, approvalMode: "auto" }),
	});
	return { m, sent };
}

const parent = { sessionFile: "chat.jsonl", title: "t", cwd: "/tmp", modelId: "claude-opus-5.5" };

test("cost adds up per request from usage.cost; model and thinking level recorded", async () => {
	const session = fakeSession([
		{ usage: { input: 100, output: 50, cacheRead: 0, cacheWrite: 0, cost: { total: 0.1 } } },
		{ usage: { input: 800, output: 2788, cacheRead: 82472, cacheWrite: 41, cost: { total: 0.344404 } } },
		// A failed request: pi records no cost for it.
		{ stopReason: "error", errorMessage: "upstream", usage: { input: 500, output: 0, cost: { total: 0 } } },
	]);
	const { m, sent } = manager(session);
	const rec = m.start(parent, "Tugas", "read");
	const done = await m.waitFor(rec.id);
	assert.equal(done.model, "claude-opus-5.5");
	assert.equal(done.modelName, "Claude Opus 5.5");
	assert.equal(done.thinkingLevel, "high");
	assert.equal(done.requests, 3);
	assert.ok(Math.abs(done.cost - (0.1 + 0.344404)) < 1e-6, `cost ${done.cost}`);
	assert.equal(done.cacheReadTokens, 82472);
	// The card saw the cost grow step by step, not only at the end.
	const live = sent.filter((r) => r.type === "subagent_status" && r.cost !== null).map((r) => r.cost);
	assert.ok(live.length >= 2 && live[0] < live.at(-1), `live cost ${live}`);
	assert.ok(sent.some((r) => r.type === "subagent_status" && r.thinkingLevel === "high" && r.model === "claude-opus-5.5"));
});

test("an unknown model keeps cost unknown instead of a made-up number", async () => {
	const session = fakeSession([{ usage: { input: 10, output: 10 } }], { provider: "custom", id: "my-local-llm", name: "Local" });
	const { m } = manager(session);
	const done = await m.waitFor(m.start({ ...parent, modelId: "my-local-llm" }, "Tugas", "read").id);
	assert.equal(done.cost, null);
	assert.equal(done.requests, 1);
});

test("the cost limit stops tiny steps once their summed cost crosses it", async () => {
	const steps = Array.from({ length: 30 }, () => ({ usage: { input: 50, output: 10, cost: { total: 0.05 } } }));
	const session = fakeSession(steps);
	const sent = [];
	const m = new SubagentManager({
		send: (r) => sent.push(r),
		wireEvent: (e) => e,
		createSession: async () => session,
		limits: () => ({ costLimit: 1, minutesLimit: 0, approvalMode: "auto" }),
	});
	const done = await m.waitFor(m.start(parent, "Tugas", "read").id);
	// 30 steps at $0.05 = $1.50; the run must stop at the $1 limit.
	assert.ok(done.cost >= 1, `cost ${done.cost}`);
	assert.equal(done.status, "stopped");
	assert.equal(done.stopCode, "cost");
});

test("cleanup", () => rmSync(out, { recursive: true, force: true }));
