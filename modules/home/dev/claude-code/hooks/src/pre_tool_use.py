#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///

import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from shared import get_str, log_to_file

DANGEROUS_RM_PATTERNS = [
    r"\brm\s+.*-rf.*/",
    r"\brm\s+.*-rf.*\*",
    r"\brm\s+.*-rf.*~",
    r"\brm\s+.*-rf.*/home",
    r"\brm\s+.*-rf.*/root",
    r"\brm\s+.*-rf.*\$HOME",
    r"\brm\s+.*-rf.*\.\.",
    r"\brm\s+.*-rf.*\s+/(?!tmp|var/tmp)",
]

DANGEROUS_COMMAND_PATTERNS = [
    r":\(\)\{.*:\|:&.*\};:",       # fork bomb
    r">\s*/dev/[sh]d[a-z]",        # direct device write
    r"dd\s+.*of=/dev/[sh]d[a-z]",  # dd to device
    r"\bmkfs\.",                    # filesystem format
    r"chmod\s+.*-R\s*777",         # recursive 777
    r"chmod\s+.*777\s*-R",
]


def is_dangerous_rm(command: str) -> bool:
    normalized = command.strip().lower()
    return any(re.search(p, normalized) for p in DANGEROUS_RM_PATTERNS)


def is_dangerous_command(command: str) -> bool:
    normalized = command.strip()
    return any(re.search(p, normalized, re.IGNORECASE) for p in DANGEROUS_COMMAND_PATTERNS)


def is_env_file_access(tool_name: str, file_path: str) -> bool:
    if not file_path:
        return False
    if ".env.sample" in file_path:
        return False
    return ".env" in file_path or "credentials.json" in file_path


def main() -> None:
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        sys.exit(0)

    log_to_file("pre_tool_use.json", data)

    tool_name = data.get("tool_name", "")
    tool_input = data.get("tool_input", {})

    if tool_name == "Bash":
        command = get_str(tool_input, "command")
        if is_dangerous_rm(command):
            print(f"Blocked dangerous rm command: {command}", file=sys.stderr)
            sys.exit(2)
        if is_dangerous_command(command):
            print(f"Blocked dangerous command: {command}", file=sys.stderr)
            sys.exit(2)

    if tool_name in ("Read", "Edit", "Write", "MultiEdit"):
        file_path = get_str(tool_input, "file_path")
        if is_env_file_access(tool_name, file_path):
            print(f"Blocked access to sensitive file: {file_path}", file=sys.stderr)
            sys.exit(2)

    sys.exit(0)


if __name__ == "__main__":
    main()
