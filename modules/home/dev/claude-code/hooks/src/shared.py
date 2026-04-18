"""Shared utilities for Claude Code hooks."""

import json
import os
from datetime import datetime, timezone
from pathlib import Path


def log_to_file(filename: str, data: object) -> None:
    """Append a timestamped entry to a JSON log file. Silently ignores errors."""
    try:
        log_dir = Path.home() / ".claude" / "hooks" / "logs"
        log_dir.mkdir(parents=True, exist_ok=True)
        log_file = log_dir / filename

        entry = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "data": data,
        }

        logs = []
        if log_file.exists():
            try:
                logs = json.loads(log_file.read_text())
            except (json.JSONDecodeError, OSError):
                pass

        logs.append(entry)
        log_file.write_text(json.dumps(logs, indent=2))
    except Exception:
        pass


def get_str(d: dict, key: str) -> str:
    """Safely extract a string value from a dict."""
    val = d.get(key, "")
    return val if isinstance(val, str) else ""
