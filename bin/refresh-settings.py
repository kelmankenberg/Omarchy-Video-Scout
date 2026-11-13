#!/usr/bin/env python3
"""Read and atomically save Video Scout's opt-in refresh interval."""

import json
import os
from pathlib import Path
import sys
from storage import save_json


INTERVALS = (0, 10, 15, 30, 45, 60, 90, 120)
RESULT_LIMITS = (50, 100, 150)


def settings_path():
    return Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "omarchy-video-scout" / "settings.json"


def validate(value):
    if type(value) is not int or value not in INTERVALS:
        raise ValueError("Refresh interval must be Off, 10, 15, 30, 45, 60, 90, or 120 minutes.")
    return value


def validate_limit(value):
    if type(value) is not int or value not in RESULT_LIMITS:
        raise ValueError("Video limit must be 50, 100, or 150.")
    return value


def read_settings(path):
    if not path.exists():
        return {"refreshMinutes": 0, "resultLimit": 50}
    with path.open() as stream:
        settings = json.load(stream)
    return {
        "refreshMinutes": validate(settings["refreshMinutes"]),
        "resultLimit": validate_limit(settings.get("resultLimit", 50)),
    }


def read_interval(path):
    return read_settings(path)["refreshMinutes"]


def save_interval(path, value):
    validate(value)
    settings = read_settings(path)
    settings["refreshMinutes"] = value
    save_json(path, settings)


def save_limit(path, value):
    validate_limit(value)
    settings = read_settings(path)
    settings["resultLimit"] = value
    save_json(path, settings)


def main():
    try:
        path = settings_path()
        if len(sys.argv) == 1:
            pass
        elif len(sys.argv) == 2:
            value = validate(int(sys.argv[1]))
            save_interval(path, value)
        elif len(sys.argv) == 3 and sys.argv[1] == "--limit":
            save_limit(path, int(sys.argv[2]))
        else:
            raise ValueError("Expected no arguments, an interval, or --limit followed by 50, 100, or 150.")
        print(json.dumps(read_settings(path)))
        return 0
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"Video Scout refresh settings: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
