/**
 * Sleep Inhibit Extension
 *
 * Takes a systemd sleep inhibitor while pi is actively working
 * (between before_agent_start and agent_end events), releases
 * it when idle at prompt. Protects long-running agent turns
 * from being interrupted by systemd suspend.
 */

import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { spawn, type ChildProcess } from "node:child_process";

export default function sleepInhibitExtension(pi: ExtensionAPI): void {
  let inhibitor: ChildProcess | null = null;

  function takeInhibitor(): void {
    if (inhibitor) return;
    inhibitor = spawn(
      "systemd-inhibit",
      [
        "--what=sleep",
        "--who=pi",
        "--why=pi coding agent actively working",
        "--mode=block",
        "sleep",
        "infinity",
      ],
      { stdio: "ignore" },
    );
    inhibitor.unref();
    inhibitor.on("exit", () => {
      inhibitor = null;
    });
  }

  function releaseInhibitor(): void {
    if (!inhibitor) return;
    inhibitor.kill("SIGTERM");
    inhibitor = null;
  }

  // Clean up on shutdown so a crashed/force-killed pi doesn't
  // leak an orphaned inhibitor.
  const cleanup = () => releaseInhibitor();
  process.on("SIGTERM", cleanup);
  process.on("SIGINT", cleanup);
  process.on("beforeExit", cleanup);

  pi.on("before_agent_start", async () => {
    takeInhibitor();
  });

  pi.on("agent_end", async () => {
    releaseInhibitor();
  });
}
