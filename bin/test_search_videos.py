import base64
import importlib.util
import json
from pathlib import Path
import unittest
from urllib.parse import parse_qs, urlparse


spec = importlib.util.spec_from_file_location(
    "search_videos", Path(__file__).with_name("search-videos.py")
)
search = importlib.util.module_from_spec(spec)
spec.loader.exec_module(search)


class SearchVideosTests(unittest.TestCase):
    def test_ranges_are_sent_to_youtube_before_result_limit(self):
        for date_range, code in (("day", 2), ("week", 3), ("month", 4), ("all", None)):
            with self.subTest(date_range=date_range):
                query = parse_qs(urlparse(search.search_url(date_range)).query)
                self.assertEqual(query["search_query"], ["Omarchy"])
                filters = b"\x10\x01" if code is None else bytes([8, code, 16, 1])
                self.assertEqual(
                    base64.b64decode(query["sp"][0]),
                    bytes([8, 2, 18, len(filters)]) + filters,
                )

    def test_sorts_upload_times_and_keeps_undated_and_markup_titles(self):
        entries = [
            ("AAAAAAAAAAA", "Older", "Channel", 1793304000),
            ("BBBBBBBBBBB", "Undated", "Channel", None),
            ("CCCCCCCCCCC", '<img src="https://example.invalid/tracker">', "Channel", 1793350800),
        ]
        output = "\n".join(json.dumps(field) for entry in entries for field in entry).encode()
        videos = search.parse_videos(output)
        self.assertEqual([video["id"] for video in videos], ["CCCCCCCCCCC", "AAAAAAAAAAA", "BBBBBBBBBBB"])
        self.assertEqual(videos[0]["title"], entries[2][1])
        self.assertEqual(videos[-1]["uploadDate"], "")

    def test_invalid_timestamps_and_incomplete_output_are_errors(self):
        for timestamp in (True, "yesterday", -1, float("inf")):
            with self.subTest(timestamp=timestamp):
                output = "\n".join(json.dumps(field) for field in (
                    "AAAAAAAAAAA", "Video", "Channel", timestamp
                )).encode()
                with self.assertRaises(ValueError):
                    search.parse_videos(output)
        with self.assertRaises(ValueError):
            search.parse_videos(b'"AAAAAAAAAAA"\n')


if __name__ == "__main__":
    unittest.main()
