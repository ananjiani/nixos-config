/**
 * Usage Tracker Extension - account-level quota monitoring for multiple providers.
 *
 * Queries provider billing/quota APIs and shows:
 * - Account-level remaining quota (prompts, tokens, MCP calls)
 * - Plan tier and reset times
 * - Per-session token/cost accumulation
 * - Real-time rate limit headers from responses
 *
 * Providers:
 * - kimi-coding:  api.kimi.com/coding/v1/usages
 * - zai:          api.z.ai/api/monitor/usage/quota/limit
 *   (TOKENS_LIMIT = 5h rolling token quota, TIME_LIMIT = monthly MCP tool quota)
 * - opencode-go:  dashboard scraping + model probing fallback
 *   (OpenCode Go tracking adapted from timm-u/pi-usage, MIT © 2026 timm-u)
 */

import type { AssistantMessage } from "@mariozechner/pi-ai";
import { getModels } from "@mariozechner/pi-ai";
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
	used?: number; // actual usage (from currentValue in API)
	limit?: number; // quota limit (from "usage" field in API — misleading name)
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

// --- OpenCode Go types (adapted from timm-u/pi-usage) ---

type GoModelStatus = "available" | "rate_limited" | "credits_error" | "error" | "no_key";
type GoProbeApi = "openai-completions" | "anthropic-messages";

interface GoCheckModel {
	id: string;
	api: GoProbeApi;
	endpoint: string;
	costRank: number;
}

interface OpenCodeGoUsage {
	available: boolean;
	status: GoModelStatus;
	workingModel?: string;
	rateLimitedModel?: string;
	checkedModels?: number;
	totalModels?: number;
	quotaConfigured?: boolean;
	quotaSource?: string;
	rollingUsedPercent?: number;
	weeklyUsedPercent?: number;
	weeklyResetAfterSeconds?: number;
	weeklyResetAt?: number;
	monthlyUsedPercent?: number;
	monthlyResetAfterSeconds?: number;
	monthlyResetAt?: number;
	rollingResetAfterSeconds?: number;
	rollingResetAt?: number;
	quotaError?: string;
	errorMessage?: string;
	error?: string;
	lastFetched: number;
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const CHECK_TIMEOUT_MS = 15_000;
const GO_BASE_URL = "https://opencode.ai/zen/go/v1";
const GO_DASHBOARD_PREFIX = "https://opencode.ai/workspace";

// Fallback Go model list (cheapest first). Supplemented by getModels("opencode-go").
const HARDCODED_GO_MODELS: GoCheckModel[] = [
	{ id: "qwen3.5-plus", api: "openai-completions", endpoint: `${GO_BASE_URL}/chat/completions`, costRank: 1 },
	{ id: "minimax-m2.5", api: "openai-completions", endpoint: `${GO_BASE_URL}/chat/completions`, costRank: 2 },
	{ id: "minimax-m2.7", api: "openai-completions", endpoint: `${GO_BASE_URL}/chat/completions`, costRank: 3 },
	{ id: "qwen3.6-plus", api: "openai-completions", endpoint: `${GO_BASE_URL}/chat/completions`, costRank: 4 },
	{ id: "deepseek-v4-flash", api: "openai-completions", endpoint: `${GO_BASE_URL}/chat/completions`, costRank: 5 },
	{ id: "kimi-k2-5", api: "openai-completions", endpoint: `${GO_BASE_URL}/chat/completions`, costRank: 6 },
	{ id: "glm-5", api: "openai-completions", endpoint: `${GO_BASE_URL}/chat/completions`, costRank: 7 },
	{ id: "kimi-k2-6", api: "openai-completions", endpoint: `${GO_BASE_URL}/chat/completions`, costRank: 8 },
	{ id: "mimo-v2-5", api: "openai-completions", endpoint: `${GO_BASE_URL}/chat/completions`, costRank: 9 },
	{ id: "glm-5.1", api: "openai-completions", endpoint: `${GO_BASE_URL}/chat/completions`, costRank: 10 },
	{ id: "mimo-v2-5-pro", api: "openai-completions", endpoint: `${GO_BASE_URL}/chat/completions`, costRank: 11 },
	{ id: "deepseek-v4-pro", api: "openai-completions", endpoint: `${GO_BASE_URL}/chat/completions`, costRank: 12 },
];

// ---------------------------------------------------------------------------
// Helpers (shared)
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
	return `in ${(diff / 86_400_000).toFixed(1)}d`;
}

function formatDuration(seconds: number): string {
	if (seconds <= 0) return "now";
	if (seconds < 60) return `${Math.round(seconds)}s`;
	if (seconds < 3600) return `${Math.round(seconds / 60)}m`;
	if (seconds < 86400) return `${(seconds / 3600).toFixed(1)}h`;
	return `${(seconds / 86400).toFixed(1)}d`;
}

function pctBar(pct: number, width = 10): string {
	const filled = Math.round((Math.min(pct, 100) / 100) * width);
	return `[${"█".repeat(filled)}${"░".repeat(width - filled)}] ${pct}% used`;
}

function clampPercent(pct: number): number {
	if (!Number.isFinite(pct)) return 0;
	return Math.max(0, Math.min(100, pct));
}

// ---------------------------------------------------------------------------
// Provider fetchers: Kimi
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

// ---------------------------------------------------------------------------
// Provider fetchers: ZAI
// ---------------------------------------------------------------------------

async function fetchZaiUsage(signal?: AbortSignal): Promise<ZaiUsage> {
	const apiKey = readApiKey("zai");
	if (!apiKey) return { plan: "?", limits: [], lastFetched: Date.now(), error: "No API key found" };

	try {
		const data = await fetchJSON("https://api.z.ai/api/monitor/usage/quota/limit", {
			Authorization: `Bearer ${apiKey}`,
		}, signal);

		const limits = (data.data?.limits ?? []).map((l: any) => ({
			type: l.type,
			used: l.currentValue ?? undefined, // actual usage counter
			limit: l.usage ?? undefined, // quota limit (API field is misleadingly named "usage")
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
// Provider fetchers: OpenCode Go (adapted from timm-u/pi-usage, MIT)
// ---------------------------------------------------------------------------

/**
 * Resolve the OpenCode Go API key. Checks models.json providers first
 * (our vault-agent !cat pattern), then OPENCODE_API_KEY env var.
 */
function getOpencodeGoApiKey(): string | undefined {
	const fromModels = readApiKey("opencode-go");
	if (fromModels) return fromModels;
	return process.env.OPENCODE_API_KEY;
}

/**
 * Get Go models to probe. Merges pi's built-in model registry with the
 * hardcoded fallback list, sorted by cost (cheapest first).
 */
function getGoCheckModels(): GoCheckModel[] {
	const byId = new Map<string, GoCheckModel>();
	for (const m of HARDCODED_GO_MODELS) {
		byId.set(m.id, m);
	}
	// Supplement from pi's built-in model registry
	try {
		for (const model of getModels("opencode-go")) {
			if (byId.has(model.id)) continue;
			const costRank = model.cost.input + model.cost.output + model.cost.cacheRead + model.cost.cacheWrite;
			byId.set(model.id, {
				id: model.id,
				api: "openai-completions",
				endpoint: `${GO_BASE_URL}/chat/completions`,
				costRank,
			});
		}
	} catch { /* getModels may fail if registry not loaded */ }
	return Array.from(byId.values()).sort((a, b) => a.costRank - b.costRank);
}

/**
 * Read error message from an HTTP response body.
 */
async function readErrorMessage(response: Response, fallback: string): Promise<string> {
	try {
		const body = await response.text();
		const parsed = JSON.parse(body);
		return parsed?.error?.message ?? parsed?.message ?? parsed?.detail ?? fallback;
	} catch {
		return fallback;
	}
}

/**
 * Check if an error message indicates a per-model issue (not a global quota error).
 */
function isPerModelUnavailable(status: number, message: string): boolean {
	if (status === 400 || status === 404 || status === 422) return true;
	return /model.*(disabled|not.*found|unsupported|unavailable)|disabled.*model/i.test(message);
}

/**
 * Check if an error message indicates a global Go plan quota limit.
 */
function isGlobalGoLimit(message: string): boolean {
	if (/error from provider/i.test(message)) return false;
	return /insufficient.*(credit|balance|fund)|balance.*insufficient|credits? exhausted|opencode.*(quota|limit)|go.*(quota|limit)|subscription.*(quota|limit)/i.test(message);
}

/**
 * Send a minimal probe request to a single Go model.
 * Uses openai-completions protocol (OpenCode Go's standard).
 */
async function probeGoModel(apiKey: string, model: GoCheckModel, signal: AbortSignal): Promise<Response> {
	return fetch(model.endpoint, {
		method: "POST",
		headers: {
			"Authorization": `Bearer ${apiKey}`,
			"Content-Type": "application/json",
		},
		body: JSON.stringify({
			model: model.id,
			messages: [{ role: "user", content: "hi" }],
			max_tokens: 1,
		}),
		signal,
	});
}

/**
 * Probe Go models to determine availability. Tries cheapest models first,
 * stops at the first success or definitive global error.
 */
async function probeGoModels(apiKey: string): Promise<OpenCodeGoUsage> {
	const models = getGoCheckModels();
	let checkedModels = 0;
	let lastRateLimit: { model: string; message: string } | undefined;

	try {
		for (const model of models) {
			const controller = new AbortController();
			const timeout = setTimeout(() => controller.abort(), CHECK_TIMEOUT_MS);
			checkedModels++;

			let response: Response;
			try {
				response = await probeGoModel(apiKey, model, controller.signal);
			} finally {
				clearTimeout(timeout);
			}

			if (response.ok) {
				try { await response.text(); } catch { /* ignore */ }
				return {
					available: true,
					status: "available",
					workingModel: model.id,
					checkedModels,
					totalModels: models.length,
					lastFetched: Date.now(),
				};
			}

			if (response.status === 429) {
				const errorMsg = await readErrorMessage(response, "Rate limited");
				lastRateLimit = { model: model.id, message: errorMsg };
				if (isGlobalGoLimit(errorMsg)) {
					return {
						available: false,
						status: "rate_limited",
						rateLimitedModel: model.id,
						checkedModels,
						totalModels: models.length,
						errorMessage: errorMsg,
						lastFetched: Date.now(),
					};
				}
				continue; // Per-window rate limit on this model, try next
			}

			if (response.status === 401 || response.status === 403) {
				const errorMsg = await readErrorMessage(response, "Authentication error");
				const status: GoModelStatus = /credit|balance|quota|insufficient/i.test(errorMsg)
					? "credits_error" : "error";
				return {
					available: false,
					status,
					checkedModels,
					totalModels: models.length,
					errorMessage: errorMsg,
					lastFetched: Date.now(),
				};
			}

			const errorMsg = await readErrorMessage(response, `HTTP ${response.status}`);
			if (isPerModelUnavailable(response.status, errorMsg)) continue;

			return {
				available: false,
				status: "error",
				checkedModels,
				totalModels: models.length,
				errorMessage: `${model.id}: ${errorMsg}`,
				lastFetched: Date.now(),
			};
		}

		// All models probed, none succeeded
		if (lastRateLimit) {
			return {
				available: false,
				status: "rate_limited",
				rateLimitedModel: lastRateLimit.model,
				checkedModels,
				totalModels: models.length,
				errorMessage: lastRateLimit.message,
				lastFetched: Date.now(),
			};
		}

		return {
			available: false,
			status: "error",
			checkedModels,
			totalModels: models.length,
			errorMessage: "No Go models available",
			lastFetched: Date.now(),
		};
	} catch (e: unknown) {
		return {
			available: false,
			status: "error",
			checkedModels,
			totalModels: models.length,
			error: e instanceof Error ? e.message : String(e),
			lastFetched: Date.now(),
		};
	}
}

/**
 * Parse a single usage window from the OpenCode Go dashboard HTML.
 * The dashboard embeds data like: rollingUsage:$R[1]={usagePercent:20,resetInSec:1234,...}
 */
function parseGoUsageWindow(
	html: string,
	key: "rolling" | "weekly" | "monthly",
): { usedPercent: number; resetAfterSeconds: number; resetAt: number } | undefined {
	const objectMatch = new RegExp(`${key}Usage:\\$R\\[\\d+\\]=\\{([^}]*)\\}`).exec(html);
	const body = objectMatch?.[1];
	if (!body) return undefined;

	const usageMatch = /usagePercent:(\d+(?:\.\d+)?)/.exec(body);
	if (!usageMatch) return undefined;

	const usedPercent = clampPercent(Number(usageMatch[1]));
	const resetMatch = /resetInSec:(\d+(?:\.\d+)?)/.exec(body);
	const resetAfterSeconds = resetMatch ? Math.max(0, Math.round(Number(resetMatch[1]))) : 0;

	return {
		usedPercent,
		resetAfterSeconds,
		resetAt: resetAfterSeconds > 0 ? Math.round(Date.now() / 1000) + resetAfterSeconds : 0,
	};
}

/**
 * Scrape the OpenCode Go dashboard for quota percentages.
 *
 * Resolution order for workspace ID + auth cookie:
 * 1. /run/secrets/opencode_go_workspace_id + opencode_go_auth_cookie
 *    (vault-agent rendered, auto-rotates with lease renewal)
 * 2. OPENCODE_GO_WORKSPACE_ID + OPENCODE_GO_AUTH_COOKIE env vars
 *    (for manual testing / non-NixOS hosts)
 */
async function fetchGoDashboardQuota(): Promise<{
	rollingUsedPercent?: number;
	weeklyUsedPercent?: number;
	monthlyUsedPercent?: number;
	rollingResetAt?: number;
	weeklyResetAt?: number;
	monthlyResetAt?: number;
	rollingResetAfterSeconds?: number;
	weeklyResetAfterSeconds?: number;
	monthlyResetAfterSeconds?: number;
	error?: string;
} | null> {
	const fs = require("node:fs");
	const path = require("node:path");

	// Read a /run/secrets file, returning undefined on any error.
	const readSecret = (name) => {
		try {
			return fs.readFileSync(path.join("/run/secrets", name), "utf-8").trim() || undefined;
		} catch { return undefined; }
	};

	const workspaceId = readSecret("opencode_go_workspace_id") || process.env.OPENCODE_GO_WORKSPACE_ID?.trim();
	const authCookie = readSecret("opencode_go_auth_cookie") || process.env.OPENCODE_GO_AUTH_COOKIE?.trim();
	if (!workspaceId || !authCookie) return null;

	try {
		const controller = new AbortController();
		const timeout = setTimeout(() => controller.abort(), CHECK_TIMEOUT_MS);
		const response = await fetch(
			`${GO_DASHBOARD_PREFIX}/${encodeURIComponent(workspaceId)}/go`,
			{
				headers: {
					"Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
					"Cookie": `auth=${authCookie}`,
					"User-Agent": "pi-usage-tracker",
				},
				signal: controller.signal,
			},
		);
		clearTimeout(timeout);

		if (!response.ok) {
			return { error: `Dashboard HTTP ${response.status}` };
		}

		const html = await response.text();
		const rolling = parseGoUsageWindow(html, "rolling");
		const weekly = parseGoUsageWindow(html, "weekly");
		const monthly = parseGoUsageWindow(html, "monthly");

		if (!rolling && !weekly && !monthly) {
			return { error: "No quota data in dashboard" };
		}

		return {
			rollingUsedPercent: rolling?.usedPercent,
			rollingResetAt: rolling?.resetAt,
			rollingResetAfterSeconds: rolling?.resetAfterSeconds,
			weeklyUsedPercent: weekly?.usedPercent,
			weeklyResetAt: weekly?.resetAt,
			weeklyResetAfterSeconds: weekly?.resetAfterSeconds,
			monthlyUsedPercent: monthly?.usedPercent,
			monthlyResetAt: monthly?.resetAt,
			monthlyResetAfterSeconds: monthly?.resetAfterSeconds,
		};
	} catch (e: unknown) {
		return { error: e instanceof Error ? e.message : String(e) };
	}
}

/**
 * Fetch OpenCode Go usage: try dashboard quota first, fall back to model probing.
 */
async function fetchOpencodeGoUsage(signal?: AbortSignal): Promise<OpenCodeGoUsage> {
	const apiKey = getOpencodeGoApiKey();
	if (!apiKey) {
		return { available: false, status: "no_key", lastFetched: Date.now() };
	}

	// Try dashboard scraping first (gives exact percentages)
	const dashboard = await fetchGoDashboardQuota();

	if (dashboard?.rollingUsedPercent !== undefined || dashboard?.weeklyUsedPercent !== undefined || dashboard?.monthlyUsedPercent !== undefined) {
		const quotaExhausted =
			(dashboard.rollingUsedPercent !== undefined && dashboard.rollingUsedPercent >= 100) ||
			(dashboard.weeklyUsedPercent !== undefined && dashboard.weeklyUsedPercent >= 100) ||
			(dashboard.monthlyUsedPercent !== undefined && dashboard.monthlyUsedPercent >= 100);
		return {
			available: !quotaExhausted,
			status: quotaExhausted ? "rate_limited" : "available",
			quotaConfigured: true,
			quotaSource: "dashboard",
			rollingUsedPercent: dashboard.rollingUsedPercent,
			rollingResetAt: dashboard.rollingResetAt,
			rollingResetAfterSeconds: dashboard.rollingResetAfterSeconds,
			weeklyUsedPercent: dashboard.weeklyUsedPercent,
			weeklyResetAt: dashboard.weeklyResetAt,
			weeklyResetAfterSeconds: dashboard.weeklyResetAfterSeconds,
			monthlyUsedPercent: dashboard.monthlyUsedPercent,
			monthlyResetAt: dashboard.monthlyResetAt,
			monthlyResetAfterSeconds: dashboard.monthlyResetAfterSeconds,
			lastFetched: Date.now(),
		};
	}

	// Fall back to model probing
	const result = await probeGoModels(apiKey);
	return {
		...result,
		quotaConfigured: dashboard !== null,
		quotaError: dashboard?.error,
	};
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
	let goData: OpenCodeGoUsage | null = null;
	let fetching = false;

	// -----------------------------------------------------------------------
	// Account data fetch
	// -----------------------------------------------------------------------

	async function refreshAccountUsage(ctx: any, signal?: AbortSignal) {
		if (fetching) return;
		fetching = true;
		try {
			const [kimi, zai, go] = await Promise.all([
				fetchKimiUsage(signal),
				fetchZaiUsage(signal),
				fetchOpencodeGoUsage(signal),
			]);
			kimiData = kimi;
			zaiData = zai;
			goData = go;
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
			const l = zaiData.limits.find(x => x.type === "TOKENS_LIMIT") ?? zaiData.limits[0];
			return { label: "zai", pct: l.percentage, remaining: l.remaining ?? 0, limit: l.limit ?? 0 };
		}
		if (provider === "opencode-go" && goData && goData.status !== "no_key") {
			const pct = goData.weeklyUsedPercent ?? (goData.available ? 0 : 100);
			return { label: "go", pct, remaining: 0, limit: 0 };
		}
		// Fallback: try other providers
		if (goData && goData.status !== "no_key") {
			const pct = goData.weeklyUsedPercent ?? (goData.available ? 0 : 100);
			return { label: "go", pct, remaining: 0, limit: 0 };
		}
		if (zaiData && !zaiData.error && zaiData.limits.length > 0) {
			const l = zaiData.limits.find(x => x.type === "TOKENS_LIMIT") ?? zaiData.limits[0];
			return { label: "zai", pct: l.percentage, remaining: l.remaining ?? 0, limit: l.limit ?? 0 };
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
		description: "Show account-level quota for all providers",
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
					const label = l.type === "TIME_LIMIT" ? "MCP monthly" : "5h tokens";
					const usedPct = l.percentage;
					const parts = [`  ${label}: ${pctBar(usedPct)}`];
					if (l.limit !== undefined && l.remaining !== undefined) {
						parts.push(`${l.remaining}/${l.limit} remaining`);
					}
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

			// OpenCode Go
			lines.push("🚀 OpenCode Go");
			if (!goData) {
				lines.push("  Not configured — set OPENCODE_API_KEY or add to models.json");
			} else if (goData.status === "no_key") {
				lines.push("  Not configured — set OPENCODE_API_KEY or add to models.json");
			} else {
				const statusIcons: Record<GoModelStatus, string> = {
					available: "✓",
					rate_limited: "⏳",
					credits_error: "✗",
					error: "⚠",
					no_key: "—",
				};
				const statusLabels: Record<GoModelStatus, string> = {
					available: "available",
					rate_limited: "rate limited",
					credits_error: "credits exhausted",
					error: "error",
					no_key: "no key",
				};
				const icon = statusIcons[goData.status];
				const label = statusLabels[goData.status];
				lines.push(`  ${icon} Status: ${label}`);

				// Dashboard quota windows (when configured)
				if (goData.rollingUsedPercent !== undefined) {
					const pct = goData.rollingUsedPercent;
					lines.push(`  Rolling: ${pctBar(pct)}  resets ${goData.rollingResetAt ? formatResetTime(goData.rollingResetAt) : "unknown"}`);
				}
				if (goData.weeklyUsedPercent !== undefined) {
					const pct = goData.weeklyUsedPercent;
					lines.push(`  Weekly:  ${pctBar(pct)}  resets ${goData.weeklyResetAt ? formatResetTime(goData.weeklyResetAt) : "unknown"}`);
				}
				if (goData.monthlyUsedPercent !== undefined) {
					const pct = goData.monthlyUsedPercent;
					lines.push(`  Monthly: ${pctBar(pct)}  resets ${goData.monthlyResetAt ? formatResetTime(goData.monthlyResetAt) : "unknown"}`);
				}

				// Model probe results (fallback or supplementary)
				if (goData.workingModel) {
					lines.push(`  Working: ${goData.workingModel}`);
				}
				if (goData.rateLimitedModel) {
					lines.push(`  Limited: ${goData.rateLimitedModel}`);
				}
				if (goData.checkedModels && goData.totalModels) {
					lines.push(`  Probed:  ${goData.checkedModels}/${goData.totalModels} models`);
				}
				if (goData.quotaError) {
					lines.push(`  Quota:   ${goData.quotaError}`);
				}
				if (goData.errorMessage) {
					lines.push(`  Error:   ${goData.errorMessage.substring(0, 100)}`);
				}
				if (goData.error) {
					lines.push(`  Error:   ${goData.error.substring(0, 100)}`);
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
