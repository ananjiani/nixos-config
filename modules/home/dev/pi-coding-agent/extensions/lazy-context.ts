/**
 * Lazy Context Extension
 *
 * Mimics Claude Code's subdirectory CLAUDE.md behaviour:
 * discovers AGENTS.md / CLAUDE.md files in subdirectories and lazily
 * injects them into the system prompt when the agent touches files in
 * those directories or when the user's prompt references them.
 *
 * Only walks subdirectories of cwd. Skips hidden dirs and common
 * build artifacts (node_modules, target, .git, result, etc.).
 */

import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import * as fs from "node:fs";
import * as path from "node:path";

export default async function (pi: ExtensionAPI) {
  const loadedDirs = new Set<string>();
  const dirToAgents = new Map<string, string>();
  const touchedDirs = new Set<string>();

  // Discover relative to process.cwd() at extension load time
  // (session start). Event handlers use ctx.cwd if it differs.
  const loadCwd = process.cwd();

  // Recursively discover AGENTS.md / CLAUDE.md in subdirectories
  function discover(dir: string): void {
    let entries: fs.Dirent[];
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }

    for (const entry of entries) {
      if (!entry.isDirectory()) continue;
      if (entry.name.startsWith(".")) continue;
      if (
        [
          "node_modules",
          "vendor",
          "target",
          "dist",
          "build",
          "result",
          ".git",
        ].includes(entry.name)
      ) {
        continue;
      }

      const subdir = path.join(dir, entry.name);

      for (const name of ["AGENTS.md", "CLAUDE.md"]) {
        const file = path.join(subdir, name);
        if (fs.existsSync(file)) {
          try {
            dirToAgents.set(subdir, fs.readFileSync(file, "utf-8"));
          } catch {
            // ignore unreadable
          }
          break; // prefer AGENTS.md over CLAUDE.md
        }
      }

      discover(subdir);
    }
  }

  discover(loadCwd);

  if (dirToAgents.size === 0) {
    console.log("[lazy-context] no AGENTS.md / CLAUDE.md found in subdirectories of", loadCwd);
    return;
  }

  console.log(
    "[lazy-context] discovered",
    dirToAgents.size,
    "context file(s):",
    [...dirToAgents.keys()].map((d) => path.relative(loadCwd, d)).join(", "),
  );

  // Track directories touched by read/write/edit tool calls
  pi.on("tool_result", async (event, ctx) => {
    if (!["read", "write", "edit"].includes(event.toolName)) return;

    const filePath = event.input.path as string;
    const cwd = ctx.cwd || loadCwd;
    // Handle both absolute and relative paths
    const absPath = path.isAbsolute(filePath)
      ? filePath
      : path.resolve(cwd, filePath);

    for (const [dir, _] of dirToAgents) {
      if (absPath.startsWith(dir + path.sep) && !loadedDirs.has(dir)) {
        touchedDirs.add(dir);
        console.log("[lazy-context] queued for load:", path.relative(loadCwd, dir));
      }
    }
  });

  // Inject relevant AGENTS.md content before each agent turn
  pi.on("before_agent_start", async (event, ctx) => {
    const prompt = event.prompt || "";
    const toLoad = new Set<string>();

    // Match by prompt text referencing a directory
    for (const [dir, _] of dirToAgents) {
      if (loadedDirs.has(dir)) continue;
      const relDir = path.relative(loadCwd, dir);
      if (prompt.includes(relDir) || prompt.includes(dir)) {
        toLoad.add(dir);
        console.log("[lazy-context] prompt matched:", relDir);
      }
    }

    // Match by files touched in previous turns
    for (const dir of touchedDirs) {
      if (!loadedDirs.has(dir)) toLoad.add(dir);
    }
    touchedDirs.clear();

    if (toLoad.size === 0) return;

    const blocks: string[] = [];
    for (const dir of toLoad) {
      const content = dirToAgents.get(dir)!;
      const relDir = path.relative(loadCwd, dir);
      blocks.push(`--- ${relDir}/AGENTS.md ---\n${content}`);
      loadedDirs.add(dir);
    }

    const banner = `[lazy-context] loaded ${blocks.length} context file(s): ${[...toLoad].map((d) => path.relative(loadCwd, d)).join(", ")}`;
    console.log(banner);

    // If UI is available, show a transient notification so the user sees it
    if (ctx.hasUI) {
      ctx.ui.notify(banner, "info");
    }

    return {
      systemPrompt: event.systemPrompt + "\n\n" + blocks.join("\n\n"),
    };
  });
}
