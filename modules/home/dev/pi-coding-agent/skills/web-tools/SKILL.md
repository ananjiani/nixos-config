---
name: web-tools
description: Proactively search the web or fetch URL content when information may be outdated, unfamiliar, or time-sensitive — do NOT wait for the user to explicitly ask. Search WITHOUT asking permission first when you encounter unfamiliar APIs/libraries, version-specific questions, error messages you can't resolve from local context, recent releases or changelogs, or anything that could have changed since your knowledge cutoff. Also use when the user explicitly asks to search, look something up, or read a URL.
---

# Web Tools

Three bash commands on PATH. No MCPs, no built-in web tools — just call these directly via the bash tool.

## When to use each

| Task | Tool |
|---|---|
| "Search for / look up / find X on the web" | `web-search` |
| "Read / summarize / fetch https://..." (privacy-preserving) | `web-fetch` |
| "Read https://..." but `web-fetch` returned trivial output (JS-rendered SPA, auth-walled, soft-404) | `web-fetch-jina` |

## web-search

Self-hosted SearXNG at `searxng.lan` (LAN-only, private, free, no rate limit). First choice for any search.

```bash
web-search <query...>
```

Returns top 10 results as markdown blocks (title / URL / snippet).

## web-fetch

Local Readability + html2text extraction. Fetches the URL on-box, extracts the main article body using Mozilla's Readability (same algorithm as Firefox Reader Mode), converts to markdown. **The URL is never sent to a third party** — only the `curl` request goes out, routed through Mullvad.

```bash
web-fetch <url>
```

Privacy trade-off: handles static HTML only. For JS-rendered pages (React/Vue SPAs, sites that require client-side rendering), this will return trivial output. When that happens, `web-fetch` prints a hint to stderr:

```
[web-fetch] only N chars extracted — try web-fetch-jina for JS-rendered or auth-walled pages
```

## web-fetch-jina

Jina Reader (`r.jina.ai`) fallback. Server-side Readability with a headless browser — handles SPAs and dynamically-generated content.

```bash
web-fetch-jina <url>
```

**Privacy cost: every URL fetched here is logged by Jina's servers.** Prefer `web-fetch` when privacy matters; use this only when local extraction produces trivial output or when you specifically need JS rendering.

Set `JINA_API_KEY` in env for higher rate limits (forwarded as Bearer auth).

## Decision flow

1. You need current information → `web-search`
   **Always include the current year (2026) in queries about recent information** — e.g. `web-search nixpkgs unfree packages 2026`, not `web-search nixpkgs unfree packages`.
2. User asks to read a specific URL → `web-fetch` first
3. If `web-fetch` returns <500 chars or obviously wrong content → `web-fetch-jina`
4. If you need both search AND content for a URL in one call → `web-search` gives snippets; follow up with `web-fetch` on specific URLs of interest.
