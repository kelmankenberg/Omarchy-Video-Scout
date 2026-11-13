import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


spec = importlib.util.spec_from_file_location(
    "refresh_settings", Path(__file__).with_name("refresh-settings.py")
)
settings = importlib.util.module_from_spec(spec)
spec.loader.exec_module(settings)


class RefreshSettingsTests(unittest.TestCase):
    def test_opt_in_default_and_persistent_intervals(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "scout" / "settings.json"
            self.assertEqual(settings.read_interval(path), 0)
            for minutes in settings.INTERVALS:
                settings.save_interval(path, minutes)
                self.assertEqual(settings.read_interval(path), minutes)

    def test_invalid_values_do_not_overwrite_saved_settings(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "settings.json"
            settings.save_interval(path, 30)
            for value in (True, -1, 5, 121, "10", 10.0):
                with self.subTest(value=value), self.assertRaises(ValueError):
                    settings.save_interval(path, value)
            self.assertEqual(settings.read_interval(path), 30)

    def test_corrupt_settings_are_reported(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "settings.json"
            for contents in ("{", "{}", '{"refreshMinutes": 5}'):
                path.write_text(contents)
                with self.subTest(contents=contents), self.assertRaises((ValueError, KeyError)):
                    settings.read_interval(path)

    def test_video_limit_migrates_and_preserves_interval(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "settings.json"
            path.write_text('{"refreshMinutes": 10}')
            self.assertEqual(settings.read_settings(path)["resultLimit"], 50)
            for limit in (50, 100, 150):
                settings.save_limit(path, limit)
                self.assertEqual(settings.read_settings(path), {"refreshMinutes": 10, "resultLimit": limit})
            settings.save_interval(path, 30)
            self.assertEqual(settings.read_settings(path), {"refreshMinutes": 30, "resultLimit": 150})
            for limit in (0, 51, 200, True, "100"):
                with self.subTest(limit=limit), self.assertRaises(ValueError):
                    settings.save_limit(path, limit)
            self.assertEqual(settings.read_settings(path)["resultLimit"], 150)


if __name__ == "__main__":
    unittest.main()
