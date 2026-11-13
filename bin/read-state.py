#!/usr/bin/env python3
"""Persist explicitly marked-read video IDs independently of date filters."""

import json
import os
from pathlib import Path
import re
import sys

from storage import save_json


def state_path():
    return Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "omarchy-video-scout" / "read.json"


def validate_ids(values):
    if not isinstance(values, list) or len(values) > 100000:
        raise ValueError("Read state must contain a list of at most 100,000 video IDs.")
    if any(not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9_-]{11}", value) for value in values):
        raise ValueError("Read state contains an invalid video ID.")
    return set(values)


def read_ids(path):
    if not path.exists():
        return set()
    with path.open() as stream:
        contents = stream.read(4000001)
    if len(contents) > 4000000:
        raise ValueError("Read state exceeds the size limit.")
    return validate_ids(json.loads(contents)["readIds"])


def update_ids(path, ids, read):
    ids = validate_ids(ids)
    previous = read_ids(path)
    result = previous | ids if read else previous - ids
    validate_ids(list(result))
    save_json(path, {"readIds": sorted(result)})
    return result


def main():
    try:
        path = state_path()
        if len(sys.argv) == 1:
            ids = read_ids(path)
        elif len(sys.argv) > 2 and sys.argv[1] in ("read", "unread"):
            ids = update_ids(path, sys.argv[2:], sys.argv[1] == "read")
        else:
            raise ValueError("Expected read or unread followed by video IDs.")
        print(json.dumps({"readIds": sorted(ids)}))
        return 0
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"Video Scout read state: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
