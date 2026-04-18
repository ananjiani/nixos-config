#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from shared import get_str, log_to_file

FILE_TYPE_MAP = {
    ".py": "python",
    ".js": "javascript",
    ".ts": "javascript",
    ".json": "json",
    ".md": "markdown",
    ".go": "go",
    ".nix": "nix",
}


def analyze_tool_usage(data: dict) -> dict:
    tool = data.get("tool", {})
    tool_name = tool.get("name", data.get("tool_name", ""))
    params = tool.get("parameters", {})
    result = data.get("result", {})

    analysis: dict = {
        "tool_name": tool_name,
        "success": not result.get("error", False),
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }

    if tool_name == "Bash":
        command = get_str(params, "command")
        analysis["command"] = command
        if "git" in command:
            analysis["command_type"] = "git"
        elif "npm" in command or "yarn" in command:
            analysis["command_type"] = "package_manager"
        elif "test" in command or "jest" in command or "pytest" in command:
            analysis["command_type"] = "test"
        elif "lint" in command or "format" in command:
            analysis["command_type"] = "code_quality"
        else:
            analysis["command_type"] = "general"

    elif tool_name in ("Read", "Edit", "Write", "MultiEdit"):
        file_path = get_str(params, "file_path")
        analysis["file_path"] = file_path
        if file_path:
            ext = Path(file_path).suffix
            analysis["file_type"] = FILE_TYPE_MAP.get(ext, "other")

    elif tool_name in ("Grep", "Glob"):
        analysis["pattern"] = get_str(params, "pattern")

    return analysis


def main() -> None:
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        sys.exit(0)

    analysis = analyze_tool_usage(data)
    log_to_file("post_tool_use.json", {"original_data": data, "analysis": analysis})
    sys.exit(0)


if __name__ == "__main__":
    main()
