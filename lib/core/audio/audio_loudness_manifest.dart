import 'dart:convert';

import 'package:flutter/services.dart';

import 'audio_gain.dart';

/// Playback gain for every bundled clip, measured once at build time by
/// `tool/measure_audio_loudness.py`.
///
/// The authored catalogue is not level with itself: Vietnamese clips sit about
/// 4 dB above the English ones and the whole set spans roughly 18 dB, so a
/// child hears the Vietnamese lead and then a noticeably quieter English
/// sentence. Android corrects that by decoding each clip before it plays;
/// iOS never did, so on iOS the unevenness reached the child unchanged.
///
/// Measuring at runtime on iOS too would have put a decode in front of every
/// clip, on the navigation path already reported as slow. Bundled audio cannot
/// change between builds, so the measurement is shipped instead: both platforms
/// look the gain up with no decode and no wait, and get the same number on a
/// clip's first play as on its tenth.
///
/// Anything not in the manifest — a recording, a remote clip — still falls back
/// to whatever the platform measures for itself.
class AudioLoudnessManifest {
  const AudioLoudnessManifest._(this._gainDb);

  /// Used when the manifest is missing or unreadable. Playback then behaves
  /// exactly as it did before the manifest existed rather than failing.
  static const AudioLoudnessManifest empty = AudioLoudnessManifest._(
    <String, double>{},
  );

  static const String assetKey = 'assets/data/audio_loudness.json';

  final Map<String, double> _gainDb;

  static Future<AudioLoudnessManifest>? _pending;
  static AssetBundle? _loadedFrom;

  /// Loads and caches the manifest. Concurrent callers share one load.
  ///
  /// The cache is tied to the bundle it was read from, so a caller that passes
  /// its own bundle is never silently served another caller's copy.
  static Future<AudioLoudnessManifest> load({AssetBundle? bundle}) {
    final source = bundle ?? rootBundle;
    final pending = _pending;
    if (pending != null && identical(_loadedFrom, source)) return pending;
    _loadedFrom = source;
    return _pending = _read(source).catchError((Object _, StackTrace _) {
      // A missing manifest must never stop a child from hearing the lesson.
      // Nothing is cached either: a bundle that was not ready yet must not pin
      // an empty manifest for the rest of the process.
      if (identical(_loadedFrom, source)) {
        _pending = null;
        _loadedFrom = null;
      }
      return empty;
    });
  }

  static Future<AudioLoudnessManifest> _read(AssetBundle bundle) async {
    final raw = await bundle.loadString(assetKey);
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, Object?>) return empty;
    final gains = decoded['gainDb'];
    if (gains is! Map<String, Object?>) return empty;
    return AudioLoudnessManifest._(<String, double>{
      for (final entry in gains.entries)
        if (entry.value is num) entry.key: (entry.value! as num).toDouble(),
    });
  }

  /// Forgets the cached manifest. Tests use it to load a different bundle.
  static void resetForTesting() {
    _pending = null;
    _loadedFrom = null;
  }

  /// The gain for [assetPath], or null when the clip was not measured — a song
  /// too long to meter, or a clip that is not bundled at all.
  double? gainDbForAsset(String assetPath) {
    final gain = _gainDb[assetPath];
    if (gain == null || !gain.isFinite) return null;
    // A hand-edited or mis-generated entry must not be able to silence a clip
    // or drive a boost past the shared policy cap.
    return gain.clamp(-40.0, androidMaxPlaybackGainDb).toDouble();
  }

  int get length => _gainDb.length;
}
