#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///

import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from shared import log_to_file


def check_incomplete_todos() -> list[dict]:
    todos_dir = Path.home() / ".claude" / "todos"
    if not todos_dir.exists():
        return []

    incomplete = []
    for f in todos_dir.glob("*.json"):
        try:
            items = json.loads(f.read_text())
            for item in items:
                status = item.get("status", "")
                if status in ("pending", "in_progress"):
                    incomplete.append({
                        "file": f.name,
                        "content": item.get("content", ""),
                        "status": status,
                    })
        except (json.JSONDecodeError, OSError):
            continue
    return incomplete


def has_code_been_modified() -> bool:
    try:
        subprocess.run(
            ["git", "rev-parse", "--is-inside-work-tree"],
            check=True, capture_output=True,
        )
    except (subprocess.CalledProcessError, OSError):
        return False

    for args in (["git", "diff", "--quiet"], ["git", "diff", "--cached", "--quiet"]):
        result = subprocess.run(args, capture_output=True)
        if result.returncode != 0:
            return True
    return False


def get_session_summary() -> dict:
    summary: dict = {"tools_used": [], "files_modified": [], "commands_run": []}
    log_file = Path.home() / ".claude" / "hooks" / "logs" / "post_tool_use.json"

    try:
        logs = json.loads(log_file.read_text())
    except (json.JSONDecodeError, OSError):
        return summary

    recent = logs[-50:]
    tools_seen: set[str] = set()
    files_seen: set[str] = set()

    for entry in recent:
        analysis = entry.get("data", {}).get("analysis", {})
        tool_name = analysis.get("tool_name", "")
        if not tool_name:
            continue
        tools_seen.add(tool_name)
        if tool_name == "Bash":
            cmd = analysis.get("command", "")
            if cmd:
                summary["commands_run"].append(cmd)
        if tool_name in ("Edit", "Write", "MultiEdit"):
            fp = analysis.get("file_path", "")
            if fp:
                files_seen.add(fp)

    summary["tools_used"] = list(tools_seen)
    summary["files_modified"] = list(files_seen)
    return summary


def main() -> None:
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        sys.exit(0)

    incomplete_todos = check_incomplete_todos()
    code_modified = has_code_been_modified()
    session_summary = get_session_summary()

    stop_analysis = {
        "incomplete_todos": incomplete_todos,
        "code_modified": code_modified,
        "session_summary": session_summary,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }

    log_to_file("stop.json", {"input_data": data, "analysis": stop_analysis})

    if incomplete_todos:
        print(f"⚠️  You have {len(incomplete_todos)} incomplete todo(s)")
    if code_modified:
        print("💡 Code has been modified - consider running lint/typecheck")
    if session_summary["tools_used"]:
        print(f"📊 Session used {len(session_summary['tools_used'])} different tools")

    sys.exit(0)


if __name__ == "__main__":
    main()
