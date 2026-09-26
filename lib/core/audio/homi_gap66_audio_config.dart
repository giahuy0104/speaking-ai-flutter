// Fixed recording rollout only. Does not alter learning or session decisions.
const homiGap66ManifestAsset = 'assets/data/homi_gap66_audio.json';
const homiGap66AudioEnabled = bool.fromEnvironment(
  'HOMI_GAP66_AUTHORED_AUDIO',
  defaultValue: true,
);

const homiGap66AudioGroups = <String, bool>{
  'gap66-level-selection': bool.fromEnvironment(
    'HOMI_GAP66_LEVEL_SELECTION',
    defaultValue: true,
  ),
  'gap66-topic-replay': bool.fromEnvironment(
    'HOMI_GAP66_TOPIC_REPLAY',
    defaultValue: true,
  ),
  'gap66-topic-replay-recovery': bool.fromEnvironment(
    'HOMI_GAP66_TOPIC_REPLAY_RECOVERY',
    defaultValue: true,
  ),
  'gap66-active-screen': bool.fromEnvironment(
    'HOMI_GAP66_ACTIVE_SCREEN',
    defaultValue: true,
  ),
  'gap66-navigation-recovery': bool.fromEnvironment(
    'HOMI_GAP66_NAVIGATION_RECOVERY',
    defaultValue: true,
  ),
  'gap66-vocabulary-recovery': bool.fromEnvironment(
    'HOMI_GAP66_VOCABULARY_RECOVERY',
    defaultValue: true,
  ),
  'gap66-completion-recovery': bool.fromEnvironment(
    'HOMI_GAP66_COMPLETION_RECOVERY',
    defaultValue: true,
  ),
};
