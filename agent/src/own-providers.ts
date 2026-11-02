/**
 * Only the endpoints the person added.
 *
 * pi knows dozens of built-in providers (sign in with an account, a catalogue of API keys) and, given a key in the
 * environment or an old sign-in on disk, offers their models as if they were set up here. For now Rynex is used with
 * the endpoints added in Settings → Models & providers and nothing else, so the ModelRuntime the host hands to pi is a
 * view of the real one that only shows those: their providers, their models, their credentials. Everything pi does
 * with a model goes through that runtime (choosing the one a chat opens with, restoring a saved choice, listing what
 * can be picked, sending the request), so a model of a built-in provider can neither be listed, picked, restored from
 * an old chat, nor used by a background run, a subagent or a fallback.
 *
 * To bring the built-in providers back, set BUILTIN_PROVIDERS to true: nothing else is removed.
 */

/** Whether pi's built-in providers are usable. Off: only the endpoints the person added. */
export const BUILTIN_PROVIDERS = false;

/** What a refused request says. */
export const BUILTIN_OFF = "Built-in providers are turned off. Add an endpoint in Settings → Models & providers and pick one of its models.";

const WHOLE_LISTS = new Set(["getModels", "getAllModels", "getModelsOfType", "getAvailable", "getAllAvailable", "getAvailableOfType", "getAvailableSnapshot"]);
const BY_PROVIDER_ID = new Set(["getProvider", "getModel", "getModelOfType", "hasConfiguredAuth", "isUsingOAuth", "isUsingSubscription", "getProviderAuthStatus", "getRegisteredProviderConfig"]);
const SENDS = new Set(["stream", "complete", "streamSimple", "completeSimple", "streamDeferred", "fetchDeferred", "cancelDeferred", "generateImages", "classify"]);
const SIGN_IN = new Set(["login", "setRuntimeApiKey"]);

/**
 * [runtime] seen through [own]: the ids of the providers that may be used (read each time, the person adds and removes
 * endpoints while the host runs). Methods keep working on the real runtime; only what they show or accept is narrowed.
 */
export function onlyOwnProviders<T extends object>(runtime: T, own: () => ReadonlySet<string>): T {
	const allowed = (id: unknown) => typeof id === "string" && own().has(id);
	const onlyAllowed = <M extends { provider: string }>(list: readonly M[]) => list.filter((m) => allowed(m.provider));
	return new Proxy(runtime, {
		get(target, prop) {
			const value = Reflect.get(target, prop, target);
			if (typeof value !== "function" || typeof prop !== "string") return value;
			const call = (...args: unknown[]) => (value as (...a: unknown[]) => unknown).apply(target, args);

			if (prop === "getProviders") return () => (call() as { id: string }[]).filter((p) => allowed(p.id));

			// Lists of models, whatever arguments narrow them: what is left is filtered by the provider of each model, so
			// asking for a built-in provider's models gets an empty list.
			if (WHOLE_LISTS.has(prop)) {
				return (...args: unknown[]) => {
					const out = call(...args);
					return out instanceof Promise ? out.then((list) => onlyAllowed(list as { provider: string }[])) : onlyAllowed(out as { provider: string }[]);
				};
			}

			// One provider, or one model of it, by id: unknown to the view when it is not an endpoint of the person.
			if (BY_PROVIDER_ID.has(prop)) {
				return (...args: unknown[]) => {
					// getModelOfType(type, providerId, modelId) has the type first; the others start with the provider.
					const id = prop === "getModelOfType" ? args[1] : args[0];
					if (allowed(id)) return call(...args);
					return prop === "hasConfiguredAuth" || prop === "isUsingOAuth" || prop === "isUsingSubscription" ? false : undefined;
				};
			}

			// Signing in, or giving a built-in provider a key.
			if (SIGN_IN.has(prop)) {
				return (id: unknown, ...rest: unknown[]) => (allowed(id) ? call(id, ...rest) : Promise.reject(new Error(BUILTIN_OFF)));
			}

			// Sending a request with a model that is not one of theirs: refused, even if a chat or run still holds it.
			if (SENDS.has(prop)) {
				return (model: unknown, ...rest: unknown[]) => {
					const provider = (model as { provider?: unknown } | null | undefined)?.provider;
					if (provider !== undefined && !allowed(provider)) throw new Error(BUILTIN_OFF);
					return call(model, ...rest);
				};
			}

			return call;
		},
	});
}
