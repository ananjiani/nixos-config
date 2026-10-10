/**
 * Regression tests for custom compaction. Run with:
 *   bun test modules/home/dev/pi-coding-agent/custom-compaction.test.ts
 *
 * Lives outside extensions/ so Pi does not auto-load it.
 */

import { afterEach, expect, mock, test } from "bun:test";

mock.module("@earendil-works/pi-coding-agent", () => ({
	convertToLlm: (messages: unknown) => messages,
	serializeConversation: (messages: Array<{ content?: Array<{ text?: string }> }>) =>
		(messages ?? []).map((m) => m.content?.[0]?.text ?? "").join("\n"),
}));

let sessionSeq = 0;
mock.module("@earendil-works/pi-ai", () => ({
	uuidv7: () => `sid-${++sessionSeq}`,
}));

const { default: customCompaction } = await import("./extensions/custom-compaction.ts");

const FLASH_PROVIDER = "opencode-go";
const FLASH_MODEL = "deepseek-v4-flash";

const usage = {
	input: 1,
	output: 2,
	cacheRead: 0,
	cacheWrite: 0,
	totalTokens: 3,
	cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
};

function model(id: string, maxTokens = 16000) {
	return {
		provider: FLASH_PROVIDER,
		api: "openai-completions",
		id,
		name: id,
		input: ["text"],
		cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
		contextWindow: 100000,
		maxTokens,
	};
}

function assistant(text: string, stopReason = "stop", extra: Record<string, unknown> = {}) {
	return {
		role: "assistant",
		content: extra.content ?? [{ type: "text", text }],
		stopReason,
		usage,
		timestamp: Date.now(),
		...extra,
	};
}

function loadHandler() {
	let handler: ((event: unknown, ctx: unknown) => Promise<unknown>) | undefined;
	customCompaction({
		on(event: string, fn: (event: unknown, ctx: unknown) => Promise<unknown>) {
			if (event === "session_before_compact") handler = fn;
		},
	} as never);
	if (!handler) throw new Error("handler not registered");
	return handler;
}

function compactEvent(overrides: Record<string, unknown> = {}) {
	return {
		customInstructions: "Focus on auth errors",
		signal: new AbortController().signal,
		branchEntries: [],
		preparation: {
			messagesToSummarize: [
				{ role: "user", content: [{ type: "text", text: "please remember this" }], timestamp: 1 },
			],
			turnPrefixMessages: [
				{ role: "assistant", content: [{ type: "text", text: "working on it" }], timestamp: 2 },
			],
			tokensBefore: 42,
			firstKeptEntryId: "entry-1",
			previousSummary: "old summary",
		},
		...overrides,
	};
}

function ctxFor(
	complete: (...args: unknown[]) => unknown,
	find: (provider: string, modelId: string) => unknown,
) {
	return {
		ui: { notify: mock(() => {}) },
		modelRegistry: { find: mock(find), complete: mock(complete) },
	};
}

// Every find call must resolve only opencode-go/deepseek-v4-flash, including
// error paths. Returns `result` so callers can simulate a missing model.
function findFlash(result: unknown) {
	return (provider: string, modelId: string) => {
		expect(provider).toBe(FLASH_PROVIDER);
		expect(modelId).toBe(FLASH_MODEL);
		return result;
	};
}

afterEach(() => {
	sessionSeq = 0;
});

test("accepted summary keeps usage and kept-entry boundary", async () => {
	const handler = loadHandler();
	const flash = model(FLASH_MODEL);
	const ctx = ctxFor(async () => assistant("ok summary"), findFlash(flash));

	const result = await handler(compactEvent(), ctx);

	expect(result).toEqual({
		compaction: {
			summary: "ok summary",
			firstKeptEntryId: "entry-1",
			tokensBefore: 42,
			usage,
		},
	});
	expect(ctx.modelRegistry.complete.mock.calls).toHaveLength(1);
	expect(ctx.modelRegistry.find.mock.calls).toEqual([[FLASH_PROVIDER, FLASH_MODEL]]);
});

test.each(["length", "error", "pending", "deferred", "toolUse"])(
	"%s text is rejected even when nonempty",
	async (stopReason) => {
		const handler = loadHandler();
		const ctx = ctxFor(
			async () => assistant("partial text", stopReason),
			findFlash(model(FLASH_MODEL)),
		);

		expect(await handler(compactEvent(), ctx)).toBeUndefined();
		expect(ctx.modelRegistry.complete.mock.calls).toHaveLength(1);
		expect(ctx.modelRegistry.find.mock.calls).toEqual([[FLASH_PROVIDER, FLASH_MODEL]]);
	},
);

test("tool-call responses are rejected even with text", async () => {
	const handler = loadHandler();
	const ctx = ctxFor(
		async () =>
			assistant("also a tool", "stop", {
				content: [
					{ type: "text", text: "also a tool" },
					{ type: "toolCall", name: "bash", id: "1", arguments: {} },
				],
			}),
		findFlash(model(FLASH_MODEL)),
	);

	expect(await handler(compactEvent(), ctx)).toBeUndefined();
	expect(ctx.modelRegistry.complete.mock.calls).toHaveLength(1);
});

test("missing model, exceptions, and empty text use native compaction", async () => {
	const handler = loadHandler();

	const missing = ctxFor(async () => assistant("unused"), findFlash(undefined));
	expect(await handler(compactEvent(), missing)).toBeUndefined();
	expect(missing.modelRegistry.complete.mock.calls).toHaveLength(0);
	expect(missing.modelRegistry.find.mock.calls).toEqual([[FLASH_PROVIDER, FLASH_MODEL]]);

	const thrown = ctxFor(async () => {
		throw new Error("boom");
	}, findFlash(model(FLASH_MODEL)));
	expect(await handler(compactEvent(), thrown)).toBeUndefined();
	expect(thrown.modelRegistry.complete.mock.calls).toHaveLength(1);
	expect(thrown.modelRegistry.find.mock.calls).toEqual([[FLASH_PROVIDER, FLASH_MODEL]]);

	const empty = ctxFor(async () => assistant(""), findFlash(model(FLASH_MODEL)));
	expect(await handler(compactEvent(), empty)).toBeUndefined();
	expect(empty.modelRegistry.complete.mock.calls).toHaveLength(1);
	expect(empty.modelRegistry.find.mock.calls).toEqual([[FLASH_PROVIDER, FLASH_MODEL]]);
});

test("cancellation cancels compaction without another model call", async () => {
	const handler = loadHandler();
	const find = findFlash(model(FLASH_MODEL));

	const aborted = ctxFor(async () => assistant("partial abort", "aborted"), find);
	expect(await handler(compactEvent(), aborted)).toEqual({ cancel: true });
	expect(aborted.modelRegistry.complete.mock.calls).toHaveLength(1);

	const abortErr = ctxFor(async () => {
		const err = new Error("aborted");
		err.name = "AbortError";
		throw err;
	}, find);
	expect(await handler(compactEvent(), abortErr)).toEqual({ cancel: true });
	expect(abortErr.modelRegistry.complete.mock.calls).toHaveLength(1);

	const controller = new AbortController();
	controller.abort();
	const pre = ctxFor(async () => assistant("should not run"), find);
	expect(await handler(compactEvent({ signal: controller.signal }), pre)).toEqual({ cancel: true });
	expect(pre.modelRegistry.complete.mock.calls).toHaveLength(0);
});

test("request options use no cache, fresh session ids, clamped maxTokens, and no reasoning overrides", async () => {
	const handler = loadHandler();
	const signal = new AbortController().signal;

	const small = ctxFor(async () => assistant("small ok"), findFlash(model(FLASH_MODEL, 100)));
	await handler(compactEvent({ signal }), small);
	const smallOpts = small.modelRegistry.complete.mock.calls[0][2] as Record<string, unknown>;
	expect(smallOpts.cacheRetention).toBe("none");
	expect(smallOpts.sessionId).toBe("sid-1");
	expect(smallOpts.maxTokens).toBe(100);
	expect(smallOpts.signal).toBe(signal);
	expect(smallOpts.reasoningEffort).toBeUndefined();
	expect(small.modelRegistry.complete.mock.calls[0][1]).toEqual({ messages: expect.any(Array) });

	// Repeated accepted compaction gets a fresh session id and default clamp.
	const big = ctxFor(async () => assistant("big ok"), findFlash(model(FLASH_MODEL, 20000)));
	await handler(compactEvent({ signal }), big);
	const bigOpts = big.modelRegistry.complete.mock.calls[0][2] as Record<string, unknown>;
	expect(bigOpts.cacheRetention).toBe("none");
	expect(bigOpts.sessionId).toBe("sid-2");
	expect(bigOpts.sessionId).not.toBe(smallOpts.sessionId);
	expect(bigOpts.maxTokens).toBe(8192);
	expect(bigOpts.signal).toBe(signal);
	expect(bigOpts.reasoningEffort).toBeUndefined();
});

test("prompt keeps constraints, custom instructions, previous summary, and retained history wording", async () => {
	const handler = loadHandler();
	const ctx = ctxFor(async () => assistant("ok"), findFlash(model(FLASH_MODEL)));

	await handler(compactEvent(), ctx);

	const prompt = (ctx.modelRegistry.complete.mock.calls[0][1] as { messages: Array<{ content: Array<{ text: string }> }> })
		.messages[0].content[0].text;
	expect(prompt).toContain("constraints and preferences");
	expect(prompt).toContain("exact paths");
	expect(prompt).toContain("distinguish completed work from planned");
	expect(prompt).toContain("Focus on auth errors");
	expect(prompt).toContain("old summary");
	expect(prompt).toContain("please remember this");
	expect(prompt).toContain("working on it");
	expect(prompt).toContain("Recent turns stay in context");
	expect(prompt).not.toContain("replaces the full history");
	expect(prompt).not.toContain("replace the ENTIRE conversation history");
});
