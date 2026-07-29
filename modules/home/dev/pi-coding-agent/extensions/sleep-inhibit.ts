/**
 * Sleep Inhibit Extension
 *
 * Takes a systemd sleep inhibitor while pi is actively working
 * (between before_agent_start and agent_end events), releases
 * it when idle at prompt. Protects long-running agent turns
 * from being interrupted by systemd suspend.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { spawn, type ChildProcess } from "node:child_process";

export default function sleepInhibitExtension(pi: ExtensionAPI): void {
  // Host-gated via PI_SLEEP_INHIBIT from the managed pi wrapper.
  // No spawn / handlers when unset — avoids Polkit prompts on hosts that never sleep.
  if (process.env.PI_SLEEP_INHIBIT !== "1") return;

  let inhibitor: ChildProcess | null = null;

  function takeInhibitor(): void {
    if (inhibitor) return;
    const child = spawn(
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
    inhibitor = child;
    child.unref();
    child.on("exit", () => {
      if (inhibitor === child) inhibitor = null;
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
  process.on("SIGHUP", cleanup);
  process.on("beforeExit", cleanup);

  pi.on("before_agent_start", async () => {
    takeInhibitor();
  });

  pi.on("agent_end", async () => {
    releaseInhibitor();
  });

  pi.on("session_shutdown", async () => {
    cleanup();
    process.off("SIGTERM", cleanup);
    process.off("SIGINT", cleanup);
    process.off("SIGHUP", cleanup);
    process.off("beforeExit", cleanup);
  });
}
