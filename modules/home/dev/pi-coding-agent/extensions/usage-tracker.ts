/**
 * Usage Tracker Extension - account-level quota monitoring for Kimi and GLM providers.
 *
 * Queries provider billing/quota APIs and shows:
 * - Account-level remaining quota (prompts, tokens, MCP calls)
 * - Plan tier and reset times
 * - Per-session token/cost accumulation
 * - Real-time rate limit headers from responses
 *
 * Providers:
 * - kimi-coding: api.kimi.com/coding/v1/usages
 * - zai:         api.z.ai/api/monitor/usage/quota/limit

 */

import type { AssistantMessage } from "@mariozechner/pi-ai";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface SessionUsage {
	inputTokens: number;
	outputTokens: number;
	cost: number;
	turns: number;
}

interface KimiUsage {
	plan: string;
	limit: number;
	used: number;
	remaining: number;
	resetTime: string;
	windows: Array<{
		duration: number;
		timeUnit: string;
		limit: number;
		used: number;
		remaining: number;
		resetTime: string;
	}>;
	parallelLimit: number;
	totalQuotaLimit: number;
	totalQuotaRemaining: number;
	lastFetched: number;
	error?: string;
}

interface ZaiLimit {
	type: string;
	used?: number;
	currentValue?: number;
	remaining?: number;
	percentage: number;
	nextResetTime: number;
	details?: Array<{ model: string; usage: number }>;
}

interface ZaiUsage {
	plan: string;
	limits: ZaiLimit[];
	lastFetched: number;
	error?: string;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function readApiKey(provider: string): string | undefined {
	try {
		const fs = require("node:fs");
		const path = require("node:path");
		const home = process.env.HOME || process.env.USERPROFILE || "";
		const modelsPath = path.join(home, ".pi/agent/models.json");
		const raw = fs.readFileSync(modelsPath, "utf-8");
		const models = JSON.parse(raw);
		const entry = models?.providers?.[provider]?.apiKey;
		if (!entry) return undefined;
		// Handle shell command prefix "!"
		if (typeof entry === "string" && entry.startsWith("!")) {
			const { execSync } = require("node:child_process");
			return execSync(entry.slice(1).trim(), { encoding: "utf-8" }).trim();
		}
		return entry;
	} catch {
		return undefined;
	}
}

async function fetchJSON(url: string, headers: Record<string, string>, signal?: AbortSignal) {
	const response = await fetch(url, { headers, signal });
	if (!response.ok) {
		const text = await response.text();
		throw new Error(`HTTP ${response.status}: ${text.slice(0, 200)}`);
	}
	return response.json() as Promise<any>;
}

const fmt = (n: number) => (n < 1000 ? `${n}` : `${(n / 1000).toFixed(1)}k`);

function formatResetTime(resetTime: string | number): string {
	const date = typeof resetTime === "number"
		? (resetTime > 1e12 ? new Date(resetTime) : new Date(resetTime * 1000))
		: new Date(resetTime);
	if (isNaN(date.getTime())) return String(resetTime);
	const now = Date.now();
	const diff = date.getTime() - now;
	if (diff <= 0) return "now";
	if (diff < 60_000) return `in ${Math.ceil(diff / 1000)}s`;
	if (diff < 3_600_000) return `in ${Math.ceil(diff / 60_000)}m`;
	if (diff < 86_400_000) return `in ${Math.ceil(diff / 3_600_000)}h`;
	return date.toLocaleString();
}

function pctBar(pct: number, width = 10): string {
	const filled = Math.round((Math.min(pct, 100) / 100) * width);
	return `[${"█".repeat(filled)}${"░".repeat(width - filled)}] ${pct}% used`;
}

// ---------------------------------------------------------------------------
// Provider fetchers
// ---------------------------------------------------------------------------

async function fetchKimiUsage(signal?: AbortSignal): Promise<KimiUsage> {
	const apiKey = readApiKey("kimi-coding");
	if (!apiKey) return { plan: "?", limit: 0, used: 0, remaining: 0, resetTime: "", windows: [], parallelLimit: 0, totalQuotaLimit: 0, totalQuotaRemaining: 0, lastFetched: Date.now(), error: "No API key found" };

	try {
		const data = await fetchJSON("https://api.kimi.com/coding/v1/usages", {
			Authorization: `Bearer ${apiKey}`,
		}, signal);

		const usage = data.usage ?? {};
		const limits = (data.limits ?? []).map((l: any) => ({
			duration: l.window?.duration ?? 0,
			timeUnit: l.window?.timeUnit ?? "",
			limit: parseInt(l.detail?.limit ?? "0", 10),
			used: parseInt(l.detail?.used ?? "0", 10),
			remaining: parseInt(l.detail?.remaining ?? "0", 10),
			resetTime: l.detail?.resetTime ?? "",
		}));

		return {
			plan: data.subType ?? data.user?.membership?.level ?? "?",
			limit: parseInt(usage.limit ?? "0", 10),
			used: parseInt(usage.used ?? "0", 10),
			remaining: parseInt(usage.remaining ?? "0", 10),
			resetTime: usage.resetTime ?? "",
			windows: limits,
			parallelLimit: parseInt(data.parallel?.limit ?? "0", 10),
			totalQuotaLimit: parseInt(data.totalQuota?.limit ?? "0", 10),
			totalQuotaRemaining: parseInt(data.totalQuota?.remaining ?? "0", 10),
			lastFetched: Date.now(),
		};
	} catch (e: any) {
		return { plan: "?", limit: 0, used: 0, remaining: 0, resetTime: "", windows: [], parallelLimit: 0, totalQuotaLimit: 0, totalQuotaRemaining: 0, lastFetched: Date.now(), error: e.message };
	}
}

async function fetchZaiUsage(signal?: AbortSignal): Promise<ZaiUsage> {
	const apiKey = readApiKey("zai");
	if (!apiKey) return { plan: "?", limits: [], lastFetched: Date.now(), error: "No API key found" };

	try {
		const data = await fetchJSON("https://api.z.ai/api/monitor/usage/quota/limit", {
			Authorization: `Bearer ${apiKey}`,
		}, signal);

		const limits = (data.data?.limits ?? []).map((l: any) => ({
			type: l.type,
			used: l.usage,
			currentValue: l.currentValue,
			remaining: l.remaining,
			percentage: l.percentage,
			nextResetTime: l.nextResetTime,
			details: (l.usageDetails ?? []).map((d: any) => ({
				model: d.modelCode,
				usage: d.usage,
			})),
		}));

		return {
			plan: data.data?.level ?? "?",
			limits,
			lastFetched: Date.now(),
		};
	} catch (e: any) {
		return { plan: "?", limits: [], lastFetched: Date.now(), error: e.message };
	}
}

// ---------------------------------------------------------------------------
// Extension
// ---------------------------------------------------------------------------

export default function (pi: ExtensionAPI) {
	const sessionUsage: SessionUsage = { inputTokens: 0, outputTokens: 0, cost: 0, turns: 0 };
	let showInStatus = true;

	// Cached account data
	let kimiData: KimiUsage | null = null;
	let zaiData: ZaiUsage | null = null;
	let fetching = false;

	// -----------------------------------------------------------------------
	// Account data fetch
	// -----------------------------------------------------------------------

	async function refreshAccountUsage(ctx: any, signal?: AbortSignal) {
		if (fetching) return;
		fetching = true;
		try {
			const [kimi, zai] = await Promise.all([
				fetchKimiUsage(signal),
				fetchZaiUsage(signal),
			]);
			kimiData = kimi;
			zaiData = zai;
			updateStatus(ctx);
		} finally {
			fetching = false;
		}
	}

	// -----------------------------------------------------------------------
	// Session token tracking
	// -----------------------------------------------------------------------

	pi.on("session_start", async (_event, ctx) => {
		sessionUsage.inputTokens = 0;
		sessionUsage.outputTokens = 0;
		sessionUsage.cost = 0;
		sessionUsage.turns = 0;

		for (const entry of ctx.sessionManager.getBranch()) {
			if (entry.type === "message" && entry.message.role === "assistant") {
				const m = entry.message as AssistantMessage;
				sessionUsage.inputTokens += m.usage.input;
				sessionUsage.outputTokens += m.usage.output;
				sessionUsage.cost += m.usage.cost.total;
				sessionUsage.turns++;
			}
		}
		// Fetch account data on session start
		await refreshAccountUsage(ctx);
	});

	pi.on("turn_end", async (_event, ctx) => {
		const msg = _event.message;
		if (msg?.role === "assistant") {
			const m = msg as AssistantMessage;
			sessionUsage.inputTokens += m.usage.input;
			sessionUsage.outputTokens += m.usage.output;
			sessionUsage.cost += m.usage.cost.total;
			sessionUsage.turns++;
		}
		updateStatus(ctx);
	});

	// -----------------------------------------------------------------------
	// Rate limit headers from live responses
	// -----------------------------------------------------------------------

	pi.on("after_provider_response", async (event, ctx) => {
		const model = ctx.model;
		if (!model) return;
		const provider = model.provider;

		if (event.status === 429) {
			const retryAfter = event.headers["retry-after"];
			const msg = retryAfter
				? `${provider} rate limited — retry after ${retryAfter}s`
				: `${provider} rate limited (429)`;
			ctx.ui.notify(`🚫 ${msg}`, "error");
			// Refresh account data on rate limit to see updated quotas
			await refreshAccountUsage(ctx, ctx.signal);
		}
	});

	// -----------------------------------------------------------------------
	// Status bar
	// -----------------------------------------------------------------------

	function getProviderQuota(provider: string): { label: string; pct: number; remaining: number; limit: number } | null {
		if (provider === "kimi-coding" && kimiData && !kimiData.error) {
			const usedPct = kimiData.limit > 0 ? Math.round((kimiData.used / kimiData.limit) * 100) : 0;
			return { label: "kimi", pct: usedPct, remaining: kimiData.remaining, limit: kimiData.limit };
		}
		if (provider === "zai" && zaiData && !zaiData.error && zaiData.limits.length > 0) {
			const l = zaiData.limits[0];
			return { label: "zai", pct: l.percentage, remaining: l.remaining ?? 0, limit: (l.used ?? 0) + (l.remaining ?? 0) };
		}
		// Fallback: try the other provider
		if (zaiData && !zaiData.error && zaiData.limits.length > 0) {
			const l = zaiData.limits[0];
			return { label: "zai", pct: l.percentage, remaining: l.remaining ?? 0, limit: (l.used ?? 0) + (l.remaining ?? 0) };
		}
		if (kimiData && !kimiData.error) {
			const usedPct = kimiData.limit > 0 ? Math.round((kimiData.used / kimiData.limit) * 100) : 0;
			return { label: "kimi", pct: usedPct, remaining: kimiData.remaining, limit: kimiData.limit };
		}
		return null;
	}

	function updateStatus(ctx: { ui: any; model?: any }) {
		if (!showInStatus) return;

		const provider = ctx.model?.provider ?? "";
		const quota = getProviderQuota(provider);
		let status = `📊 $${sessionUsage.cost.toFixed(3)}`;

		if (quota) {
			status += ` │ ${quota.label}: ${quota.pct}% used`;
		}

		ctx.ui.setStatus("usage", status);
	}

	// -----------------------------------------------------------------------
	// /usage command
	// -----------------------------------------------------------------------

	pi.registerCommand("usage", {
		description: "Show account-level quota for Kimi and GLM providers",
		handler: async (_args, ctx) => {
			// Refresh before showing
			await refreshAccountUsage(ctx, ctx.signal);

			const lines: string[] = [];

			// Session summary
			lines.push(
				"📊 Session",
				`  Turns: ${sessionUsage.turns}  Input: ${fmt(sessionUsage.inputTokens)}  Output: ${fmt(sessionUsage.outputTokens)}  Cost: $${sessionUsage.cost.toFixed(4)}`,
				"",
			);

			// Kimi
			lines.push("🌙 Kimi Coding");
			if (!kimiData) {
				lines.push("  No data — fetch failed");
			} else if (kimiData.error) {
				lines.push(`  ❌ ${kimiData.error}`);
			} else {
				const usedPct = kimiData.limit > 0 ? Math.round((kimiData.used / kimiData.limit) * 100) : 0;
				const totalQuotaLine = kimiData.totalQuotaLimit > 0
					? `   Lifetime: ${kimiData.totalQuotaRemaining}/${kimiData.totalQuotaLimit} remaining`
					: "";
				lines.push(
					`  Plan: ${kimiData.plan}   Concurrency: ${kimiData.parallelLimit}`,
				);
				if (totalQuotaLine) lines.push(totalQuotaLine);
				lines.push(
					`  Monthly: ${pctBar(usedPct)}  resets ${formatResetTime(kimiData.resetTime)}`,
				);
				for (const w of kimiData.windows) {
					const wUsedPct = w.limit > 0 ? Math.round((w.used / w.limit) * 100) : 0;
					const dur = w.duration > 60 ? `${w.duration / 60}h` : `${w.duration}m`;
					lines.push(`  Window (${dur}): ${pctBar(wUsedPct)}  resets ${formatResetTime(w.resetTime)}`);
				}
			}
			lines.push("");

			// Z.AI
			lines.push("🤖 Z.AI / GLM");
			if (!zaiData) {
				lines.push("  No data — fetch failed");
			} else if (zaiData.error) {
				lines.push(`  ❌ ${zaiData.error}`);
			} else {
				lines.push(`  Plan: ${zaiData.plan}`);
				for (const l of zaiData.limits) {
					const label = l.type === "TIME_LIMIT" ? "5h window" : "Weekly tokens";
					const usedPct = l.percentage;
					const total = (l.used ?? 0) + (l.remaining ?? 0);
					const remaining = l.remaining !== undefined ? `${l.remaining}/${total} remaining` : "";
					const parts = [`  ${label}: ${pctBar(usedPct)}`];
					if (remaining) parts.push(remaining);
					parts.push(`resets ${formatResetTime(l.nextResetTime)}`);
					lines.push(parts.join("  "));
					if (l.details && l.details.length > 0) {
						for (const d of l.details) {
							lines.push(`    ${d.model}: ${d.usage}`);
						}
					}
				}
			}
			lines.push("");


			ctx.ui.notify(lines.join("\n"), "info");
		},
	});

	// -----------------------------------------------------------------------
	// /usage-toggle command
	// -----------------------------------------------------------------------

	pi.registerCommand("usage-toggle", {
		description: "Toggle usage stats in status bar",
		handler: async (_args, ctx) => {
			showInStatus = !showInStatus;
			if (showInStatus) {
				updateStatus(ctx);
				ctx.ui.notify("Usage stats: enabled", "info");
			} else {
				ctx.ui.setStatus("usage", undefined as any);
				ctx.ui.notify("Usage stats: disabled", "info");
			}
		},
	});
}
