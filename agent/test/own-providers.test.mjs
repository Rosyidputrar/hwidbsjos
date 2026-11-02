// The view of pi's ModelRuntime that shows only the person's own endpoints (own-providers.ts).
import { test } from "node:test";
import assert from "node:assert/strict";
import { bundle } from "./helpers.mjs";

const { onlyOwnProviders, BUILTIN_OFF, BUILTIN_PROVIDERS } = await bundle("own-providers");

/** Stands in for ModelRuntime: its methods use `this`, as the real ones do, so a lost receiver would show. */
class FakeRuntime {
	constructor() {
		this.models = [
			{ provider: "anthropic", id: "claude" },
			{ provider: "openai", id: "gpt" },
			{ provider: "custom-a", id: "a1" },
			{ provider: "custom-a", id: "a2" },
			{ provider: "custom-b", id: "b1" },
		];
		this.configured = new Set(["anthropic", "custom-a", "custom-b"]);
		this.sent = [];
		this.logins = [];
	}
	getProviders() { return [...new Set(this.models.map((m) => m.provider))].map((id) => ({ id, name: id })); }
	getProvider(id) { return this.getProviders().find((p) => p.id === id); }
	getModels(id) { return this.models.filter((m) => !id || m.provider === id); }
	getModel(p, id) { return this.models.find((m) => m.provider === p && m.id === id); }
	getModelOfType(type, p, id) { return this.getModel(p, id); }
	async getAvailable(id) { return this.models.filter((m) => this.configured.has(m.provider) && (!id || m.provider === id)); }
	getAvailableSnapshot() { return this.models.filter((m) => this.configured.has(m.provider)); }
	hasConfiguredAuth(id) { return this.configured.has(id); }
	isUsingOAuth(id) { return id === "anthropic"; }
	async login(id, type) { this.logins.push([id, type]); return { id }; }
	streamSimple(model) { this.sent.push(model.id); return { stream: true }; }
	async completeSimple(model) { this.sent.push(model.id); return { text: "ok" }; }
	async refresh() { return { refreshed: true }; }
}

const own = new Set(["custom-a", "custom-b"]);
const view = () => {
	const real = new FakeRuntime();
	return { real, v: onlyOwnProviders(real, () => own) };
};

test("the built-in providers are off in this build", () => {
	assert.equal(BUILTIN_PROVIDERS, false);
});

test("providers and models: only the endpoints' own are listed, however they are asked for", async () => {
	const { v } = view();
	assert.deepEqual(v.getProviders().map((p) => p.id), ["custom-a", "custom-b"]);
	assert.deepEqual(v.getModels().map((m) => m.id), ["a1", "a2", "b1"]);
	assert.deepEqual(v.getModels("custom-a").map((m) => m.id), ["a1", "a2"]);
	assert.deepEqual(v.getModels("anthropic"), [], "a built-in provider's models are not there when asked for by name either");
	assert.deepEqual((await v.getAvailable()).map((m) => m.id), ["a1", "a2", "b1"]);
	assert.deepEqual(await v.getAvailable("openai"), []);
	assert.deepEqual(v.getAvailableSnapshot().map((m) => m.id), ["a1", "a2", "b1"], "what pi picks a first model from");
});

test("one provider or model by id: known only when it is the person's", () => {
	const { v } = view();
	assert.equal(v.getProvider("custom-a").id, "custom-a");
	assert.equal(v.getProvider("anthropic"), undefined);
	assert.equal(v.getModel("custom-b", "b1").id, "b1");
	assert.equal(v.getModel("anthropic", "claude"), undefined, "a chat saved with a built-in model does not get it back");
	assert.equal(v.getModelOfType("text", "openai", "gpt"), undefined);
	assert.equal(v.getModelOfType("text", "custom-a", "a1").id, "a1");
	assert.equal(v.hasConfiguredAuth("anthropic"), false, "a key or old sign-in for a built-in provider counts for nothing");
	assert.equal(v.hasConfiguredAuth("custom-a"), true);
	assert.equal(v.isUsingOAuth("anthropic"), false);
});

test("signing in to a built-in provider is refused with the reason; an endpoint's is passed on", async () => {
	const { real, v } = view();
	await assert.rejects(v.login("anthropic", "api_key"), { message: BUILTIN_OFF });
	assert.deepEqual(real.logins, []);
	await v.login("custom-a", "api_key");
	assert.deepEqual(real.logins, [["custom-a", "api_key"]]);
});

test("a request with a built-in model is refused even if a chat or run still holds it; an endpoint's goes through", async () => {
	const { real, v } = view();
	assert.throws(() => v.streamSimple({ provider: "anthropic", id: "claude" }), { message: BUILTIN_OFF });
	await assert.rejects(async () => v.completeSimple({ provider: "openai", id: "gpt" }), { message: BUILTIN_OFF });
	assert.deepEqual(real.sent, [], "nothing was sent");
	assert.deepEqual(v.streamSimple({ provider: "custom-b", id: "b1" }), { stream: true });
	assert.deepEqual(await v.completeSimple({ provider: "custom-a", id: "a1" }), { text: "ok" });
	assert.deepEqual(real.sent, ["b1", "a1"]);
});

test("methods keep their receiver, and the person's endpoints are read each time", async () => {
	const real = new FakeRuntime();
	const mine = new Set(["custom-a"]);
	const v = onlyOwnProviders(real, () => mine);
	assert.deepEqual(await v.refresh(), { refreshed: true }, "untouched methods pass through");
	assert.deepEqual(v.getModels().map((m) => m.id), ["a1", "a2"]);
	mine.add("custom-b");
	assert.deepEqual(v.getModels().map((m) => m.id), ["a1", "a2", "b1"], "an endpoint added later shows at once");
	mine.delete("custom-a");
	assert.deepEqual(v.getModels().map((m) => m.id), ["b1"], "and one removed goes at once");
});
