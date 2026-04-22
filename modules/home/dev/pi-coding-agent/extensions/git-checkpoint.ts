/**
 * Git Checkpoint Extension
 *
 * Creates lightweight git stash refs before each LLM turn.
 * When forking a session, offers to restore the working tree
 * to the code state at that point in time.
 *
 * Uses `git stash create` (not `git stash push`) so the working
 * tree is never touched — only a ref is captured.
 */

import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

export default function (pi: ExtensionAPI) {
  // Map session entryId -> stash ref
  const checkpoints = new Map<string, string>();
  let currentEntryId: string | undefined;

  // Track the current leaf entry ID when tool results arrive
  pi.on("tool_result", async (_event, ctx) => {
    const leaf = ctx.sessionManager.getLeafEntry();
    if (leaf) currentEntryId = leaf.id;
  });

  // Capture a stash ref before the LLM starts its turn
  pi.on("turn_start", async () => {
    const { stdout } = await pi.exec("git", ["stash", "create"]);
    const ref = stdout.trim();
    if (ref && currentEntryId) {
      checkpoints.set(currentEntryId, ref);
    }
  });

  // On fork, offer to restore the working tree to that checkpoint
  pi.on("session_before_fork", async (event, ctx) => {
    const ref = checkpoints.get(event.entryId);
    if (!ref) return;

    if (!ctx.hasUI) {
      // Non-interactive: silently skip restore
      return;
    }

    const choice = await ctx.ui.select("Restore code state to checkpoint?", [
      "Yes, restore code to that point",
      "No, keep current code",
    ]);

    if (choice?.startsWith("Yes")) {
      await pi.exec("git", ["stash", "apply", ref]);
      ctx.ui.notify("Code restored to checkpoint", "info");
    }
  });

  // Clean up checkpoints when the agent finishes
  pi.on("agent_end", async () => {
    checkpoints.clear();
  });
}
