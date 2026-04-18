#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///

import json
import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from shared import log_to_file

SOUND_PATH = "/nix/store/xln87i4xqg9j9fvk380qgqynnnps5hgj-vscode-1.85.1/lib/vscode/resources/app/out/vs/platform/audioCues/browser/media/taskCompleted.mp3"


def find_terminal_pid(pid: int) -> str:
    """Walk the process tree upward to find a 'foot' terminal PID."""
    for _ in range(10):
        try:
            result = subprocess.run(
                ["ps", "-p", str(pid), "-o", "ppid="],
                capture_output=True, text=True, check=True,
            )
            ppid_str = result.stdout.strip()
            if not ppid_str:
                return ""
            ppid = int(ppid_str)

            cmd_result = subprocess.run(
                ["ps", "-p", ppid_str, "-o", "cmd="],
                capture_output=True, text=True,
            )
            if "foot" in cmd_result.stdout:
                return ppid_str

            pid = ppid
        except (subprocess.CalledProcessError, ValueError, OSError):
            return ""
    return ""


def is_terminal_focused() -> bool:
    terminal_pid = find_terminal_pid(os.getpid())
    if not terminal_pid:
        return False

    try:
        result = subprocess.run(
            ["hyprctl", "activewindow", "-j"],
            capture_output=True, text=True, check=True,
        )
        active = json.loads(result.stdout)
        focused_pid = active.get("pid")
        if focused_pid is None:
            return False
        return str(int(focused_pid)) == terminal_pid
    except (subprocess.CalledProcessError, json.JSONDecodeError, OSError, ValueError):
        return False


def is_zellij_pane_active() -> bool:
    if not os.environ.get("ZELLIJ"):
        return True  # Not in Zellij — consider active
    my_pane_id = os.environ.get("ZELLIJ_PANE_ID", "")
    if not my_pane_id:
        return True
    try:
        result = subprocess.run(
            ["zellij", "action", "list-clients"],
            capture_output=True, text=True, check=True,
        )
        return my_pane_id in result.stdout
    except (subprocess.CalledProcessError, OSError):
        return True


def send_notification() -> None:
    subprocess.Popen(
        ["notify-send", "Claude Code", "Your attention is needed", "-u", "critical"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    subprocess.Popen(
        ["pw-play", SOUND_PATH],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )


def main() -> None:
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        sys.exit(0)

    log_to_file("notification.json", data)

    if is_terminal_focused() and is_zellij_pane_active():
        sys.exit(0)

    send_notification()
    sys.exit(0)


if __name__ == "__main__":
    main()
