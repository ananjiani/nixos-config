import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { dismissPending, notifyPending } from "./lib/notify";

export default function (pi: ExtensionAPI) {
  pi.on("agent_end", async (_event, ctx) => {
    if (!ctx.hasUI) return;
    void notifyPending(pi, "finished — waiting for input");
  });

  pi.on("agent_start", async () => {
    dismissPending();
  });

  pi.on("session_shutdown", async () => {
    dismissPending();
  });
}
