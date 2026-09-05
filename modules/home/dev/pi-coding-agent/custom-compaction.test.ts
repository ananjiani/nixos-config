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
		provider: id.startsWith("glm") ? "zai" : "opencode-go",
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

afterEach(() => {
	sessionSeq = 0;
});

test("accepted summary keeps usage and kept-entry boundary", async () => {
	const handler = loadHandler();
	const flash = model("deepseek-v4-flash");
	const ctx = ctxFor(async () => assistant("ok summary"), (p, id) => (id === "deepseek-v4-flash" ? flash : undefined));

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
});

test.each(["length", "error", "pending", "deferred", "toolUse"])(
	"%s text is rejected even when nonempty",
	async (stopReason) => {
		const handler = loadHandler();
		const ctx = ctxFor(
			async (m: { id: string }) => m.id === "deepseek-v4-flash"
				? assistant("partial text", stopReason)
				: assistant("glm summary"),
			(_p, id) => model(id),
		);

		expect(await handler(compactEvent(), ctx)).toMatchObject({ compaction: { summary: "glm summary" } });
		expect(ctx.modelRegistry.complete.mock.calls).toHaveLength(2);
	},
);

test("tool-call responses are rejected even with text", async () => {
	const handler = loadHandler();
	const flash = model("deepseek-v4-flash");
	const glm = model("glm-5.3");
	const ctx = ctxFor(
		async (_model: { id: string }) => {
			if ((_model as { id: string }).id === "deepseek-v4-flash") {
				return assistant("also a tool", "stop", {
					content: [
						{ type: "text", text: "also a tool" },
						{ type: "toolCall", name: "bash", id: "1", arguments: {} },
					],
				});
			}
			return assistant("clean glm");
		},
		(_p, id) => (id === "deepseek-v4-flash" ? flash : glm),
	);

	const result = await handler(compactEvent(), ctx);
	expect(result).toMatchObject({ compaction: { summary: "clean glm" } });
});

test("missing model and exceptions fall back; both fail uses native", async () => {
	const handler = loadHandler();
	const glm = model("glm-5.3");

	const missing = ctxFor(async () => assistant("from glm"), (_p, id) => (id === "glm-5.3" ? glm : undefined));
	expect(await handler(compactEvent(), missing)).toMatchObject({ compaction: { summary: "from glm" } });
	expect(missing.modelRegistry.complete.mock.calls).toHaveLength(1);

	const flash = model("deepseek-v4-flash");
	const thrown = ctxFor(
		async (m: { id: string }) => {
			if ((m as { id: string }).id === "deepseek-v4-flash") throw new Error("boom");
			return assistant("after throw");
		},
		(_p, id) => (id === "deepseek-v4-flash" ? flash : glm),
	);
	expect(await handler(compactEvent(), thrown)).toMatchObject({ compaction: { summary: "after throw" } });

	const both = ctxFor(async () => {
		throw new Error("nope");
	}, (_p, id) => (id === "deepseek-v4-flash" ? flash : glm));
	expect(await handler(compactEvent(), both)).toBeUndefined();
	expect(both.modelRegistry.complete.mock.calls).toHaveLength(2);
});

test("cancellation does not start the next model", async () => {
	const handler = loadHandler();
	const flash = model("deepseek-v4-flash");
	const glm = model("glm-5.3");
	const find = (_p: string, id: string) => (id === "deepseek-v4-flash" ? flash : glm);

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

test("request uses no cache, fresh session id, clamped maxTokens, low glm reasoning", async () => {
	const handler = loadHandler();
	const flash = model("deepseek-v4-flash", 100);
	const glm = model("glm-5.3", 20000);
	const signal = new AbortController().signal;
	const ctx = ctxFor(
		async (m: { id: string }) => {
			if ((m as { id: string }).id === "deepseek-v4-flash") return assistant("", "stop");
			return assistant("glm ok");
		},
		(_p, id) => (id === "deepseek-v4-flash" ? flash : glm),
	);

	await handler(compactEvent({ signal }), ctx);

	const calls = ctx.modelRegistry.complete.mock.calls;
	expect(calls).toHaveLength(2);

	const flashOpts = calls[0][2] as Record<string, unknown>;
	const glmOpts = calls[1][2] as Record<string, unknown>;
	expect(flashOpts.cacheRetention).toBe("none");
	expect(glmOpts.cacheRetention).toBe("none");
	expect(flashOpts.sessionId).toBe("sid-1");
	expect(glmOpts.sessionId).toBe("sid-2");
	expect(flashOpts.sessionId).not.toBe(glmOpts.sessionId);
	expect(flashOpts.maxTokens).toBe(100);
	expect(glmOpts.maxTokens).toBe(8192);
	expect(flashOpts.signal).toBe(signal);
	expect(glmOpts.signal).toBe(signal);
	expect(flashOpts.reasoningEffort).toBeUndefined();
	expect(glmOpts.reasoningEffort).toBe("low");
	expect(calls[0][1]).toEqual({ messages: expect.any(Array) });
});

test("prompt keeps constraints, custom instructions, previous summary, and retained history wording", async () => {
	const handler = loadHandler();
	const flash = model("deepseek-v4-flash");
	const ctx = ctxFor(async () => assistant("ok"), () => flash);

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
