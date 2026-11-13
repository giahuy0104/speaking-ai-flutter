"""Focused checks for the audio manifest CI gate."""

import copy
import unittest

from measure_audio_loudness import gain_db_sha256, manifest_matches


class ManifestMatchesTest(unittest.TestCase):
    def setUp(self):
        self.measured = {
            "policy": {"targetRmsDbfs": -21.0, "decodeRate": 16000},
            "audioSourceSha256": "same-mp3-bytes",
            "gainDb": {"a.mp3": -8.0, "b.mp3": 2.0},
        }
        self.saved = copy.deepcopy(self.measured)
        self.saved["gainDbSha256"] = gain_db_sha256(self.saved["gainDb"])

    def test_allows_small_decoder_drift_with_identical_source(self):
        self.measured["gainDb"]["a.mp3"] = -8.58
        self.assertTrue(manifest_matches(self.saved, self.measured))

    def test_rejects_changed_audio_even_with_small_gain_drift(self):
        self.measured["audioSourceSha256"] = "other-mp3-bytes"
        self.assertFalse(manifest_matches(self.saved, self.measured))

    def test_rejects_missing_gain_entry(self):
        del self.measured["gainDb"]["b.mp3"]
        self.assertFalse(manifest_matches(self.saved, self.measured))

    def test_rejects_changed_policy(self):
        self.saved["policy"]["decodeRate"] = 22050
        self.assertFalse(manifest_matches(self.saved, self.measured))

    def test_rejects_gain_drift_over_limit(self):
        self.measured["gainDb"]["a.mp3"] = -8.61
        self.assertFalse(manifest_matches(self.saved, self.measured))

    def test_accepts_exact_tolerance_boundary(self):
        self.measured["gainDb"]["a.mp3"] = -8.6
        self.assertTrue(manifest_matches(self.saved, self.measured))

    def test_rejects_non_finite_gain(self):
        self.measured["gainDb"]["a.mp3"] = float("nan")
        self.assertFalse(manifest_matches(self.saved, self.measured))

    def test_rejects_manual_gain_edit_without_updated_digest(self):
        self.saved["gainDb"]["a.mp3"] = -7.5
        self.assertFalse(manifest_matches(self.saved, self.measured))


if __name__ == "__main__":
    unittest.main()
