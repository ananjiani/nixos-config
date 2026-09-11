import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { stripTypeScriptTypes } from "node:module";
import { dirname, join } from "node:path";
import { beforeEach, test } from "node:test";
import { fileURLToPath } from "node:url";

const extDir = join(dirname(fileURLToPath(import.meta.url)), "..", "extensions");
const keyStub = "data:text/javascript,export const Key={ctrlAlt:(k)=>k};";
const notifyStub =
	"data:text/javascript,export function notifyPending(){}export function dismissPending(){}";

async function loadFactory(filename, rewrites) {
	let src = readFileSync(join(extDir, filename), "utf8");
	for (const [from, to] of Object.entries(rewrites)) {
		src = src.replaceAll(`from "${from}"`, `from "${to}"`);
		src = src.replaceAll(`from '${from}'`, `from '${to}'`);
	}
	const js = stripTypeScriptTypes(src);
	return (await import(`data:text/javascript;base64,${Buffer.from(js).toString("base64")}`))
		.default;
}

const autoFactory = await loadFactory("auto-mode.ts", {
	"@earendil-works/pi-tui": keyStub,
});
const confirmFactory = await loadFactory("confirm-destructive.ts", {
	"./lib/notify": notifyStub,
});

function makePi({ autoFlag = false } = {}) {
	const handlers = {};
	const commands = {};
	return {
		handlers,
		commands,
		pi: {
			on: (ev, fn) => {
				(handlers[ev] ??= []).push(fn);
			},
			registerFlag() {},
			registerCommand(name, def) {
				commands[name] = def;
			},
			registerShortcut() {},
			appendEntry() {},
			getFlag: (name) => (name === "auto" ? autoFlag : undefined),
		},
	};
}

function ctx(entries = []) {
	return {
		hasUI: false,
		sessionManager: { getEntries: () => entries },
		ui: {
			theme: { fg: (_k, s) => s },
			setStatus() {},
			notify() {},
		},
	};
}

function modeEntry(mode) {
	return { type: "custom", customType: "auto-mode", data: { mode } };
}

async function emit(handlers, ev, event, c) {
	let last;
	for (const fn of handlers[ev] ?? []) last = await fn(event, c);
	return last;
}

const RM = { toolName: "bash", input: { command: "rm -rf /tmp/x" } };

function ref() {
	return globalThis.__autoModeRef;
}

function bindBoth(opts) {
	const inst = makePi(opts);
	autoFactory(inst.pi);
	confirmFactory(inst.pi);
	return inst;
}

beforeEach(() => {
	const r = ref();
	if (!r) return;
	r.mode = "off";
	delete r.bound;
});

test("child startup keeps parent danger and does not gate rm", async () => {
	const parent = bindBoth();
	await emit(parent.handlers, "session_start", { reason: "startup" }, ctx());
	await parent.commands.auto.handler("danger", ctx());
	assert.equal(ref().mode, "danger");

	const child = bindBoth();
	await emit(child.handlers, "session_start", { reason: "startup" }, ctx());
	assert.equal(ref().mode, "danger");
	assert.equal(await emit(parent.handlers, "tool_call", RM, ctx()), undefined);
	assert.equal(await emit(child.handlers, "tool_call", RM, ctx()), undefined);
});

test("safe still blocks after a child starts", async () => {
	const parent = bindBoth();
	await emit(parent.handlers, "session_start", { reason: "startup" }, ctx());
	await parent.commands.auto.handler("safe", ctx());
	const child = bindBoth();
	await emit(child.handlers, "session_start", { reason: "startup" }, ctx());
	assert.equal(ref().mode, "auto");
	const result = await emit(child.handlers, "tool_call", RM, ctx());
	assert.equal(result?.block, true);
});

test("parent /new and fresh startup restore off", async () => {
	const parent = bindBoth();
	await emit(
		parent.handlers,
		"session_start",
		{ reason: "startup" },
		ctx([modeEntry("danger")]),
	);
	assert.equal(ref().mode, "danger");

	const next = bindBoth();
	await emit(next.handlers, "session_start", { reason: "new" }, ctx());
	assert.equal(ref().mode, "off");
	assert.equal((await emit(next.handlers, "tool_call", RM, ctx()))?.block, true);

	ref().mode = "danger";
	delete ref().bound;
	const fresh = bindBoth();
	await emit(fresh.handlers, "session_start", { reason: "startup" }, ctx());
	assert.equal(ref().mode, "off");
});

test("parent /resume restores stored danger", async () => {
	const inst = bindBoth();
	await emit(inst.handlers, "session_start", { reason: "startup" }, ctx());
	await emit(
		inst.handlers,
		"session_start",
		{ reason: "resume" },
		ctx([modeEntry("danger")]),
	);
	assert.equal(ref().mode, "danger");
	assert.equal(await emit(inst.handlers, "tool_call", RM, ctx()), undefined);
});

test("--auto safe survives a child start", async () => {
	const parent = bindBoth({ autoFlag: true });
	await emit(parent.handlers, "session_start", { reason: "startup" }, ctx());
	assert.equal(ref().mode, "auto");
	const child = bindBoth();
	await emit(child.handlers, "session_start", { reason: "startup" }, ctx());
	assert.equal(ref().mode, "auto");
	assert.equal((await emit(parent.handlers, "tool_call", RM, ctx()))?.block, true);
});
