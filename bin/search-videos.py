#!/usr/bin/env python3

import json
import base64
import math
import re
import subprocess
import sys
import time
from datetime import datetime, timezone
from urllib.parse import urlencode


MAX_RESULTS = 50
RESULT_LIMITS = (50, 100, 150)
MAX_OUTPUT = 64 * 1024
VIDEO_ID = re.compile(r"^[A-Za-z0-9_-]{11}$")
RANGES = {"day": 2, "week": 3, "month": 4, "all": None}


def search_url(date_range):
    filters = bytes([16, 1])  # Video results, rather than channels or playlists.
    if RANGES[date_range] is not None:
        filters = bytes([8, RANGES[date_range]]) + filters
    params = bytes([8, 2, 18, len(filters)]) + filters
    return "https://www.youtube.com/results?" + urlencode(
        {"search_query": "Omarchy", "sp": base64.b64encode(params).decode("ascii")}
    )


def fail(message):
    print(json.dumps({"error": message}))
    return 1


def clean_text(value, limit):
    if not isinstance(value, str):
        return ""
    return " ".join("".join(char for char in value if char.isprintable()).split())[:limit]


def validate_limit(value):
    if type(value) is not int or value not in RESULT_LIMITS:
        raise ValueError("Video limit must be 50, 100, or 150.")
    return value


def parse_videos(output, max_results=MAX_RESULTS):
    validate_limit(max_results)
    lines = output.decode("utf-8").splitlines()
    if len(lines) > max_results * 4 or len(lines) % 4:
        raise ValueError("Invalid metadata fields")

    videos = []
    seen = set()
    for index in range(0, len(lines), 4):
        video_id, raw_title, raw_channel, timestamp = [
            json.loads(line) for line in lines[index:index + 4]
        ]
        if not isinstance(video_id, str) or not VIDEO_ID.fullmatch(video_id):
            continue
        title = clean_text(raw_title, 240)
        if not title or video_id in seen:
            continue
        seen.add(video_id)
        if timestamp is not None and (
            isinstance(timestamp, bool)
            or not isinstance(timestamp, (int, float))
            or not math.isfinite(timestamp)
            or not 1104537600 <= timestamp <= time.time() + 86400
        ):
            raise ValueError("Invalid upload timestamp")
        videos.append(
            {
                "id": video_id,
                "title": title,
                "channel": clean_text(raw_channel, 120),
                "timestamp": timestamp,
                "uploadDate": (
                    datetime.fromtimestamp(timestamp, timezone.utc).strftime("%Y%m%d")
                    if timestamp is not None else ""
                ),
            }
        )
    videos.sort(key=lambda video: video["timestamp"] or 0, reverse=True)
    return videos


def main():
    date_range = sys.argv[1] if len(sys.argv) > 1 else "week"
    if date_range not in RANGES:
        return fail("Invalid date range. Choose day, week, month, or all.")
    try:
        if len(sys.argv) > 3:
            raise ValueError("Expected a date range and optional video limit.")
        max_results = validate_limit(int(sys.argv[2])) if len(sys.argv) > 2 else MAX_RESULTS
    except ValueError as error:
        return fail(str(error))
    try:
        result = subprocess.run(
            [
                "yt-dlp",
                "--ignore-config",
                "--flat-playlist",
                "--extractor-args",
                "youtubetab:approximate_date",
                "--skip-download",
                "--no-warnings",
                "--output-na-placeholder",
                "null",
                "--socket-timeout",
                "15",
                "--playlist-end",
                str(max_results),
                "--print",
                "%(id)j",
                "--print",
                "%(title)j",
                "--print",
                "%(channel)j",
                "--print",
                "%(timestamp)j",
                search_url(date_range),
            ],
            capture_output=True,
            timeout=30,
            check=False,
        )
    except FileNotFoundError:
        return fail("yt-dlp is not installed or is not on PATH.")
    except subprocess.TimeoutExpired:
        return fail("The YouTube search timed out.")
    except OSError:
        return fail("Could not start yt-dlp.")

    if result.returncode != 0:
        detail = clean_text(result.stderr.decode("utf-8", "replace"), 240)
        return fail(detail or "yt-dlp could not complete the YouTube search.")
    if len(result.stdout) > MAX_OUTPUT * (max_results // MAX_RESULTS):
        return fail("The YouTube search response was too large.")

    try:
        videos = parse_videos(result.stdout, max_results)
    except (UnicodeDecodeError, json.JSONDecodeError, TypeError, ValueError):
        return fail("yt-dlp returned invalid search data.")

    print(json.dumps({"videos": videos}, ensure_ascii=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
