// Isolated fixed-reply pack. Disabling it restores the original TTS fallback.
const homiGap19ManifestAsset = 'assets/data/homi_gap19_audio.json';
const homiGap19AudioEnabled = bool.fromEnvironment(
  'HOMI_GAP19_AUTHORED_AUDIO',
  defaultValue: true,
);
