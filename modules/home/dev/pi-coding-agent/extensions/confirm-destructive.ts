/**
 * Confirm destructive actions before they execute.
 *
 * Covers two categories:
 *   1. Dangerous bash commands (rm -rf, nixos-rebuild switch, deploy-rs,
 *      sops decrypt, tofu apply, force git push, etc.)
 *   2. Destructive session events (clearing messages, switching sessions,
 *      forking with unsaved work)
 *
 * In interactive mode the user gets a confirmation dialog. In non-interactive
 * mode (pi --print, JSON mode) dangerous commands are blocked outright.
 */

import type {
  ExtensionAPI,
  SessionBeforeSwitchEvent,
  SessionMessageEntry,
} from "@mariozechner/pi-coding-agent";

export default function (pi: ExtensionAPI) {
  // ─── Bash command gate ───
  const dangerousPatterns: Array<{ pattern: RegExp; reason: string }> = [
    { pattern: /\brm\s+(-[rR]|--recursive)/, reason: "recursive delete" },
    { pattern: /\bsudo\b/, reason: "elevated privileges" },
    { pattern: /\b(chmod|chown)\b.*777/, reason: "world-writable permissions" },
    {
      pattern: /\bnixos-rebuild\s+(switch|test|build|dry-build)/,
      reason: "system rebuild",
    },
    {
      pattern: /\bnh\s+(os|home)\s+switch/,
      reason: "Nix system/home switch",
    },
    {
      pattern: /\bdeploy\b/,
      reason: "remote server deployment (deploy-rs)",
    },
    {
      pattern: /\bsops\s+(-d|--decrypt)/,
      reason: "secret decryption",
    },
    {
      pattern: /\b(tofu|terraform)\s+apply/,
      reason: "infrastructure apply",
    },
    {
      pattern: /\bgit\s+push\s+.*(-f|--force)/,
      reason: "force git push",
    },
    {
      pattern: /\bgit\s+clean\s+.*-[df]/,
      reason: "delete untracked files",
    },
  ];

  pi.on("tool_call", async (event, ctx) => {
    if (event.toolName !== "bash") return;

    const command = event.input.command as string;
    const match = dangerousPatterns.find((d) => d.pattern.test(command));
    if (!match) return;

    if (!ctx.hasUI) {
      return {
        block: true,
        reason: `Blocked ${match.reason} (no UI for confirmation)`,
      };
    }

    const choice = await ctx.ui.select(
      `⚠️  Destructive command (${match.reason}):\n\n  ${command}\n\nAllow?`,
      ["Yes", "No"],
    );

    if (choice !== "Yes") {
      ctx.ui.notify("Command blocked", "warning");
      return { block: true, reason: "Blocked by user" };
    }
  });

  // ─── Session event gate ───

  pi.on("session_before_switch", async (event: SessionBeforeSwitchEvent, ctx) => {
    if (!ctx.hasUI) return;

    if (event.reason === "new") {
      const confirmed = await ctx.ui.confirm(
        "Clear session?",
        "This will delete all messages in the current session.",
      );
      if (!confirmed) {
        ctx.ui.notify("Clear cancelled", "info");
        return { cancel: true };
      }
      return;
    }

    // reason === "resume" — check for unsaved work
    const entries = ctx.sessionManager.getEntries();
    const hasUnsavedWork = entries.some(
      (e): e is SessionMessageEntry =>
        e.type === "message" && e.message.role === "user",
    );

    if (hasUnsavedWork) {
      const confirmed = await ctx.ui.confirm(
        "Switch session?",
        "You have messages in the current session. Switch anyway?",
      );
      if (!confirmed) {
        ctx.ui.notify("Switch cancelled", "info");
        return { cancel: true };
      }
    }
  });

  pi.on("session_before_fork", async (event, ctx) => {
    if (!ctx.hasUI) return;

    const choice = await ctx.ui.select(
      `Fork from entry ${event.entryId.slice(0, 8)}…?`,
      ["Yes, create fork", "No, stay in current session"],
    );

    if (choice !== "Yes, create fork") {
      ctx.ui.notify("Fork cancelled", "info");
      return { cancel: true };
    }
  });
}
