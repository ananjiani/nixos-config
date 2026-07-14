/**
 * Desktop notifications for "agent pending your action" moments.
 *
 * Sends a swaync notification via notify-send, suppressed when the foot
 * window running this pi session is focused (niri IPC). Clicking the
 * notification focuses that window.
 */

import { type ChildProcess, execFile, spawn } from "node:child_process";
import { readFileSync } from "node:fs";
import { basename } from "node:path";

type Ctx = {
  sessionManager: {
    getSessionName(): string | undefined;
    getEntries(): any[];
  };
};

// Same fallback the resume picker uses: explicit name, else first user message.
function sessionLabel(ctx: Ctx): string {
  const name = ctx.sessionManager.getSessionName();
  if (name) return name;
  for (const e of ctx.sessionManager.getEntries()) {
    if (e.type === "message" && e.message?.role === "user") {
      const c = e.message.content;
      const text = typeof c === "string" ? c : c?.find?.((b: any) => b.type === "text")?.text;
      if (text) {
        const oneLine = text.replace(/\s+/g, " ").trim();
        return oneLine.length > 60 ? `${oneLine.slice(0, 60)}…` : oneLine;
      }
    }
  }
  return "";
}

let waitProc: ChildProcess | null = null;
let lastId: number | null = null;

function findFootPid(): number | null {
  let pid = process.pid;
  for (let i = 0; i < 15; i++) {
    let stat: string;
    try {
      stat = readFileSync(`/proc/${pid}/stat`, "utf8");
    } catch {
      return null;
    }
    const m = stat.match(/^\d+ \((.*)\) \S+ (\d+)/s);
    if (!m) return null;
    if (m[1] === "foot" || m[1] === "footclient") return pid;
    pid = Number(m[2]);
    if (pid <= 1) return null;
  }
  return null;
}

function niriWindows(): Promise<Array<{ id: number; pid: number; is_focused: boolean }>> {
  return new Promise((resolve) => {
    execFile("niri", ["msg", "--json", "windows"], (err, stdout) => {
      if (err) return resolve([]);
      try {
        resolve(JSON.parse(stdout));
      } catch {
        resolve([]);
      }
    });
  });
}

export function dismissPending(): void {
  if (waitProc) {
    waitProc.kill();
    waitProc = null;
  }
  if (lastId !== null) {
    spawn(
      "busctl",
      [
        "--user",
        "call",
        "org.freedesktop.Notifications",
        "/org/freedesktop/Notifications",
        "org.freedesktop.Notifications",
        "CloseNotification",
        "u",
        String(lastId),
      ],
      { stdio: "ignore", detached: true },
    ).unref();
    lastId = null;
  }
}

export async function notifyPending(ctx: Ctx, body: string): Promise<void> {
  const footPid = findFootPid();
  let windowId: number | null = null;

  if (footPid !== null) {
    const win = (await niriWindows()).find((w) => w.pid === footPid);
    if (win?.is_focused) return;
    if (win) windowId = win.id;
  }

  dismissPending();

  const label = sessionLabel(ctx);
  const dir = basename(process.cwd());
  const title = `π ${label ? `${dir}: ${label}` : dir}`;

  const proc = spawn(
    "notify-send",
    ["-a", "pi", "-u", "critical", "--action=default=Focus", "--wait", "--print-id", title, body],
    { stdio: ["ignore", "pipe", "ignore"] },
  );
  waitProc = proc;

  let buf = "";
  const handleLine = (line: string) => {
    const t = line.trim();
    if (/^\d+$/.test(t)) lastId = Number(t);
    if ((t === "default" || t === "action=default") && windowId !== null) {
      spawn("niri", ["msg", "action", "focus-window", "--id", String(windowId)], {
        stdio: "ignore",
        detached: true,
      }).unref();
    }
  };
  proc.stdout?.on("data", (chunk: Buffer) => {
    buf += chunk.toString();
    const lines = buf.split("\n");
    buf = lines.pop() ?? "";
    for (const line of lines) handleLine(line);
  });
  proc.on("exit", () => {
    if (buf) handleLine(buf);
    if (waitProc === proc) {
      waitProc = null;
      lastId = null;
    }
  });
  proc.on("error", () => {
    if (waitProc === proc) waitProc = null;
  });
}
