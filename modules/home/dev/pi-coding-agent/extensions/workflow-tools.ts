/**
 * Workflow Tools Extension
 *
 * Promotes high-miss skills into real tools:
 * - web_search / web_fetch / web_fetch_jina wrap PATH CLIs
 * - repo_browse / repo_ingest wrap PATH CLIs
 * - ast_grep wraps ast-grep for structural code search
 * - Emacs Lisp writes auto-run agent-lisp-paren-aid
 */

import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { Type } from "@sinclair/typebox";
import { mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const MAX_BYTES = 50 * 1024;
const MAX_LINES = 2000;

type ExecResult = { stdout: string; stderr: string; code: number };

function text(content: string, details: Record<string, unknown> = {}) {
	return { content: [{ type: "text" as const, text: content }], details };
}

async function truncateOutput(output: string, label: string) {
	const lines = output.split("\n");
	const byLines = lines.length > MAX_LINES;
	let truncated = byLines ? lines.slice(0, MAX_LINES).join("\n") : output;
	const byBytes = Buffer.byteLength(truncated, "utf8") > MAX_BYTES;
	if (byBytes) truncated = Buffer.from(truncated, "utf8").subarray(0, MAX_BYTES).toString("utf8");

	if (!byLines && !byBytes) return { output, details: { truncated: false } };

	const dir = await mkdtemp(join(tmpdir(), "pi-tool-output-"));
	const fullPath = join(dir, `${label}.txt`);
	await writeFile(fullPath, output, "utf8");

	return {
		output: `${truncated}\n\n[Output truncated. Full output saved to: ${fullPath}]`,
		details: { truncated: true, fullPath },
	};
}

async function run(pi: ExtensionAPI, command: string, args: string[], signal?: AbortSignal, label = command, okCodes = [0]) {
	const result = (await pi.exec(command, args, { signal, timeout: 120_000 })) as ExecResult;
	const combined = [result.stdout, result.stderr].filter(Boolean).join("\n");
	const truncated = await truncateOutput(combined, label);
	if (!okCodes.includes(result.code)) {
		throw new Error(`${command} exited ${result.code}\n${truncated.output}`);
	}
	return text(truncated.output || "No matches.", { command, args, code: result.code, ...truncated.details });
}

function isElispPath(filePath: unknown): filePath is string {
	return typeof filePath === "string" && filePath.replace(/^@/, "").endsWith(".el");
}

export default function workflowTools(pi: ExtensionAPI) {
	pi.registerTool({
		name: "web_search",
		label: "Web Search",
		description: "Search web with self-hosted SearXNG. Use for current, unfamiliar, or time-sensitive information.",
		promptSnippet: "Search web for current or unfamiliar information",
		promptGuidelines: ["Use web_search when current or version-specific information may matter."],
		parameters: Type.Object({ query: Type.String({ description: "Search query. Include current year for recent info." }) }),
		execute: (_id, params, signal) => run(pi, "web-search", [params.query], signal, "web-search"),
	});

	pi.registerTool({
		name: "web_fetch",
		label: "Web Fetch",
		description: "Fetch URL locally with Readability. Privacy-preserving first choice for reading URLs.",
		promptSnippet: "Fetch and extract readable content from a URL locally",
		promptGuidelines: ["Use web_fetch before web_fetch_jina when reading a URL, unless JS rendering is required."],
		parameters: Type.Object({ url: Type.String({ description: "URL to fetch" }) }),
		execute: (_id, params, signal) => run(pi, "web-fetch", [params.url], signal, "web-fetch"),
	});

	pi.registerTool({
		name: "web_fetch_jina",
		label: "Web Fetch Jina",
		description: "Fetch URL through Jina Reader. Use when web_fetch returns trivial output or page needs JS rendering. Sends URL to Jina.",
		promptSnippet: "Fetch JS-rendered or hard-to-extract URL through Jina Reader",
		promptGuidelines: ["Use web_fetch_jina only after web_fetch fails or when JS rendering is required; URLs go to Jina."],
		parameters: Type.Object({ url: Type.String({ description: "URL to fetch through Jina Reader" }) }),
		execute: (_id, params, signal) => run(pi, "web-fetch-jina", [params.url], signal, "web-fetch-jina"),
	});

	pi.registerTool({
		name: "repo_browse",
		label: "Repo Browse",
		description: "Targeted browse/search/read for any git repo. Actions: ls, cat, grep, tree.",
		promptSnippet: "Browse, read, tree, or grep a remote/local git repository",
		promptGuidelines: ["Use repo_browse for GitHub/GitLab/Codeberg source code instead of web_fetch."],
		parameters: Type.Object({
			action: Type.String({ description: "One of: ls, cat, grep, tree" }),
			repo: Type.String({ description: "Git URL or local repo path" }),
			pathOrPattern: Type.Optional(Type.String({ description: "Path for ls/cat/tree, pattern for grep" })),
		}),
		execute: (_id, params, signal) => {
			if (!["ls", "cat", "grep", "tree"].includes(params.action)) throw new Error(`unknown repo_browse action: ${params.action}`);
			const args = [params.action, params.repo];
			if (params.pathOrPattern) args.push(params.pathOrPattern);
			return run(pi, "repo-browse", args, signal, "repo-browse");
		},
	});

	pi.registerTool({
		name: "repo_ingest",
		label: "Repo Ingest",
		description: "Pack a git repo or subset into one AI-friendly plain-text dump. Use for broad repo analysis.",
		promptSnippet: "Pack a git repository into one analysis dump",
		promptGuidelines: ["Use repo_ingest for broad repo understanding; use repo_browse for huge repos or narrow reads."],
		parameters: Type.Object({
			repo: Type.String({ description: "Git URL or local repo path" }),
			include: Type.Optional(Type.String({ description: "Optional repomix include glob" })),
			compress: Type.Optional(Type.Boolean({ description: "Use repomix tree-sitter compression" })),
		}),
		execute: (_id, params, signal) => {
			const args = [params.repo];
			if (params.include) args.push("--include", params.include);
			if (params.compress) args.push("--compress");
			return run(pi, "repo-ingest", args, signal, "repo-ingest");
		},
	});

	pi.registerTool({
		name: "ast_grep",
		label: "AST Grep",
		description: "Structural code search via ast-grep/tree-sitter. Use for definitions, call sites, or syntax-shaped matches; use grep/rg for plain text.",
		promptSnippet: "Search code by AST pattern with ast-grep",
		promptGuidelines: ["Use ast_grep for structural code search: definitions, call sites, imports, exported declarations, or syntax-shaped matches."],
		parameters: Type.Object({
			language: Type.String({ description: "ast-grep language, e.g. typescript, tsx, python, go, rust, nix, yaml, json" }),
			pattern: Type.String({ description: "Structural pattern, e.g. 'function $NAME($$$) {$$$}'" }),
			path: Type.Optional(Type.String({ description: "File or directory to search; defaults to cwd" })),
			json: Type.Optional(Type.Boolean({ description: "Return compact JSON output" })),
		}),
		execute: (_id, params, signal) => {
			const args = ["run", "-l", params.language, "-p", params.pattern];
			if (params.json) args.push("--json=compact");
			if (params.path) args.push(params.path);
			return run(pi, "ast-grep", args, signal, "ast-grep", [0, 1]);
		},
	});

	pi.on("tool_result", async (event, ctx) => {
		if (!["write", "edit"].includes(event.toolName) || event.isError) return;
		const filePath = event.input.path;
		if (!isElispPath(filePath)) return;

		const cleanPath = filePath.replace(/^@/, "");
		const absolutePath = resolve(ctx.cwd, cleanPath);
		const result = (await pi.exec("agent-lisp-paren-aid", [absolutePath], { signal: ctx.signal, timeout: 30_000 })) as ExecResult;
		const check = [result.stdout, result.stderr].filter(Boolean).join("\n").trim();

		if (result.code === 0 && check === "ok") {
			event.content.push({ type: "text", text: "Elisp paren check: ok" });
			return;
		}

		const message = `Elisp paren check failed for ${cleanPath}:\n${check || `agent-lisp-paren-aid exited ${result.code}`}`;
		event.content.push({ type: "text", text: message });
		if (ctx.hasUI) ctx.ui.notify(message, "warning");
		return { content: event.content, isError: true, details: { ...event.details, elispParenCheck: check, elispParenCheckCode: result.code } };
	});
}
