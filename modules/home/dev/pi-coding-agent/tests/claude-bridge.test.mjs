import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import { test } from "node:test";

const source = readFileSync(new URL("../../pi-coding-agent.nix", import.meta.url), "utf8");
const wrapper = source.match(/claudeBridgeExecutable = pkgs.writeShellScript "claude-bridge-isolated" ''\n([\s\S]*?)\n  '';/)[1];

function scratch(fn) {
	const dir = mkdtempSync(join(tmpdir(), "claude-bridge-test-"));
	try { return fn(dir); } finally { rmSync(dir, { recursive: true, force: true }); }
}

test("wrapper strips provider overrides and preserves SDK arguments", () => scratch((dir) => {
	const capture = join(dir, "capture.mjs");
	writeFileSync(capture, 'console.log(JSON.stringify({args: process.argv.slice(2), env: process.env}));');
	const script = wrapper.replaceAll("''${", "${")
		.replace("${pkgs.claude-code}/bin/claude", `"${process.execPath}" "${capture}"`);
	const clean = { PATH: process.env.PATH, HOME: dir, KEEP: "unchanged" };
	for (const dirty of [false, true]) {
		const env = { ...clean };
		if (dirty) Object.assign(env, {
			ANTHROPIC_API_KEY: "fake-key", ANTHROPIC_AUTH_TOKEN: "fake-token",
			ANTHROPIC_BASE_URL: "https://proxy.invalid", ANTHROPIC_DEFAULT_OPUS_MODEL: "glm",
			ANTHROPIC_FUTURE_OVERRIDE: "fake", CLAUDE_CODE_USE_BEDROCK: "1",
			CLAUDE_CODE_USE_VERTEX: "1", CLAUDE_CODE_USE_FOUNDRY: "1",
			API_TIMEOUT_MS: "3000000", ENABLE_TOOL_SEARCH: "false",
		});
		const result = spawnSync("bash", ["-c", script, "bridge", "--model", "claude-opus-5-5[1m]", "a b"], { env, encoding: "utf8" });
		assert.equal(result.status, 0, result.stderr);
		const child = JSON.parse(result.stdout);
		assert.deepEqual(child.args, ["--setting-sources", "", "--model", "claude-opus-5-5[1m]", "a b"]);
		assert.equal(child.env.KEEP, "unchanged");
		assert.equal(child.env.CLAUDE_CODE_DISABLE_AUTO_MEMORY, "1");
		assert.equal(Object.keys(child.env).some((name) => name.startsWith("ANTHROPIC_")), false);
		for (const name of ["CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_VERTEX", "CLAUDE_CODE_USE_FOUNDRY", "API_TIMEOUT_MS", "ENABLE_TOOL_SEARCH"])
			assert.equal(child.env[name], undefined);
	}
}));

test("defaults select the Claude bridge Opus 5.5 at medium thinking", () => {
	const settings = source.match(/piSettings = \{[\s\S]*?defaultThinkingLevel = "[a-z]+";/)[0];
	assert.match(settings, /defaultProvider = "claude-bridge";/);
	assert.match(settings, /defaultModel = "claude-opus-5-5";/);
	assert.match(settings, /defaultThinkingLevel = "medium";/);
});

test("config suppresses startup writes and uses Max plan", () => {
	assert.match(source, /piClaudeBridgeConfig =[\s\S]*?plan = "max";/);
	assert.match(source, /piClaudeBridgeConfig =[\s\S]*?startupNoticeShown = "2026-10-09";/);
	assert.doesNotMatch(source, /piPatchClaudeBridge/);
});

test("enabled models include Opus 5.5; Z.ai and removed Opus 5 absent", () => {
	const models = source.match(/enabledModels =[\s\S]*?]/)[0];
	assert.match(models, /"claude-bridge\/claude-opus-5-5"/);
	assert.doesNotMatch(models, /"claude-bridge\/claude-opus-5"/);
	assert.doesNotMatch(models, /zai\/glm-5\.3/);
});
