// Preloaded into a test host (node --import) by the app's Dart tests (test/support/daemon.dart): sends the
// test provider's chat completions to a test model at RYNEX_TEST_ROUTER (an OpenAI-compatible base URL), and
// answers the provider's other endpoints with a 404 so they never reach the test model. The host still talks
// to the test provider's canonical base URL; only fetch underneath it is pointed elsewhere.
const ROUTER = "https://mock.router.test/v1";
const target = process.env.RYNEX_TEST_ROUTER;
const realFetch = globalThis.fetch;

globalThis.fetch = async (input, init) => {
	const url = typeof input === "string" ? input : input instanceof URL ? input.href : input.url;
	if (!target || !url.startsWith(ROUTER)) return realFetch(input, init);
	const path = url.slice(ROUTER.length);
	if (!path.startsWith("/chat/completions")) return new Response('{"error":"not found"}', { status: 404 });
	return realFetch(`${target.replace(/\/+$/, "")}${path}`, init);
};
