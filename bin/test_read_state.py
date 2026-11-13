import importlib.util
from pathlib import Path
import tempfile
import unittest


spec = importlib.util.spec_from_file_location(
    "read_state", Path(__file__).with_name("read-state.py")
)
state = importlib.util.module_from_spec(spec)
spec.loader.exec_module(state)


class ReadStateTests(unittest.TestCase):
    def test_read_and_unread_preserve_other_ranges_and_persist(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "scout" / "read.json"
            first, second, third = "abcdefghijk", "12345678901", "ABCDEFGHIJK"
            self.assertEqual(state.read_ids(path), set())
            state.update_ids(path, [first, second], True)
            state.update_ids(path, [second, third], True)
            self.assertEqual(state.read_ids(path), {first, second, third})
            state.update_ids(path, [second, third], False)
            self.assertEqual(state.read_ids(path), {first})

    def test_invalid_ids_do_not_replace_saved_state(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "read.json"
            state.update_ids(path, ["abcdefghijk"], True)
            for ids in (["bad"], ["abcdefghijk", "$(bad)"], [None]):
                with self.subTest(ids=ids), self.assertRaises(ValueError):
                    state.update_ids(path, ids, True)
            self.assertEqual(state.read_ids(path), {"abcdefghijk"})

    def test_corrupt_state_is_reported_not_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "read.json"
            path.write_text("{")
            with self.assertRaises(ValueError):
                state.update_ids(path, ["abcdefghijk"], True)
            self.assertEqual(path.read_text(), "{")


if __name__ == "__main__":
    unittest.main()
