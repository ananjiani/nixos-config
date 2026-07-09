import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { basename } from "node:path";

const SPINNER = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];

export default function (pi: ExtensionAPI) {
  let interval: ReturnType<typeof setInterval> | null = null;
  let spinnerIdx = 0;

  function updateTitle(ctx: any, active: boolean) {
    const name = pi.getSessionName();
    const dir = basename(process.cwd());
    const base = name ? `${name} — ${dir}` : dir;
    ctx.ui.setTitle(active ? `${SPINNER[spinnerIdx % SPINNER.length]} π ${base}` : `π ${base}`);
  }

  pi.on("session_start", async (_event, ctx) => {
    updateTitle(ctx, false);
  });

  pi.on("session_info_changed", async (_event, ctx) => {
    updateTitle(ctx, false);
  });

  pi.on("agent_start", async (_event, ctx) => {
    spinnerIdx = 0;
    interval = setInterval(() => {
      updateTitle(ctx, true);
      spinnerIdx++;
    }, 120);
  });

  pi.on("agent_end", async (_event, ctx) => {
    if (interval) {
      clearInterval(interval);
      interval = null;
    }
    updateTitle(ctx, false);
  });

  pi.on("session_shutdown", async () => {
    if (interval) {
      clearInterval(interval);
      interval = null;
    }
  });
}
