"""Check the benchmark cannot claim denoising from just lowering the volume."""
import unittest
import numpy as np
from run import align, latency, pcm, score


class MetricsTest(unittest.TestCase):
    def setUp(self):
        rng = np.random.default_rng(42)
        self.voice = rng.normal(size=16000) * .03
        self.noise = rng.normal(size=16000) * .01

    def test_lower_volume_alone_does_not_improve_score(self):
        mixed = self.voice + self.noise
        self.assertAlmostEqual(score(self.voice, mixed),
                               score(self.voice, mixed * .1), places=8)

    def test_reducing_known_noise_improves_score(self):
        # Make noise orthogonal to speech so finite random correlation cannot
        # change the scale projection used by SI-SDR.
        voice = self.voice - self.voice.mean()
        noise = self.noise - self.noise.mean()
        noise -= np.dot(noise, voice) / np.dot(voice, voice) * voice
        before = score(voice, voice + noise)
        after = score(voice, voice + noise * .5)
        self.assertAlmostEqual(after - before, 6.0206, places=3)

    def test_delay_is_recovered_with_same_sample_count(self):
        delayed = np.pad(self.voice, (400, 0))
        lag = latency(self.voice, delayed)
        self.assertEqual(lag, 400)
        np.testing.assert_array_equal(align(delayed, lag, len(self.voice)), self.voice)

    def test_pcm_roundtrip_error_is_bounded(self):
        recovered = np.frombuffer(pcm(self.voice), dtype='<i2') / 32768
        self.assertLessEqual(np.max(np.abs(recovered - self.voice)), .5/32768)

    def test_noise_reduction_in_silence_cannot_inflate_voiced_score(self):
        reference = np.concatenate([self.voice, np.zeros(16000)])
        mixture = reference + np.tile(self.noise, 2)
        gated = mixture.copy()
        gated[16000:] = 0
        mask = np.arange(32000) < 16000
        self.assertEqual(score(reference, mixture, mask), score(reference, gated, mask))


if __name__ == '__main__':
    unittest.main()
