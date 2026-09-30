import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';

import 'package:ai_speaking_flutter_app/core/audio/audio_loudness_manifest.dart';
import 'package:ai_speaking_flutter_app/core/audio/audio_playback_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/controlled_audio_playback.dart';

/// Covers the branch of `_applySourceLevel` and `preload` that the manifest
/// introduced: a bundled asset whose gain was measured at build time.
///
/// Before the manifest, iOS applied no level at all and Android decoded every
/// clip. Nothing exercised the asset path, which made it the riskiest change
/// in the loudness work.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const levelChannel = MethodChannel('ailingo_voice_prompt');
  const sessionChannel = MethodChannel('com.ryanheise.audio_session');
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  // A clip the manifest measured, and one it never saw.
  const measuredAsset = 'assets/audio/MAIN/vi/greeting.mp3';
  final measuredUri = Uri.parse('asset:///$measuredAsset');
  // A bundled clip the manifest has no entry for — two real songs are in this
  // state. It must still take the runtime path, not inherit a neighbour's gain.
  final missedAssetUri = Uri.parse('asset:///assets/audio/MAIN/en/song.mp3');
  final unmeasuredUri = Uri.parse('file:///recording.wav');
  const manifestGainDb = -9.5;

  late List<MethodCall> levelCalls;
  late Directory tempDirectory;

  setUp(() {
    levelCalls = <MethodCall>[];
    tempDirectory = Directory.systemTemp.createTempSync('playback-level');
    AudioLoudnessManifest.resetForTesting();
    // `rootBundle` is a CachingAssetBundle: without this the mock below is read
    // by the first test only and every later reset re-serves its cached copy.
    rootBundle.clear();

    messenger.setMockMethodCallHandler(sessionChannel, (_) async => null);
    messenger.setMockMethodCallHandler(pathProviderChannel, (_) async {
      return tempDirectory.path;
    });
    messenger.setMockMethodCallHandler(levelChannel, (call) async {
      levelCalls.add(call);
      // A runtime measurement that disagrees with the manifest, so a test can
      // tell which of the two actually reached the player.
      return call.method == 'analyzePlaybackLevel'
          ? <String, Object?>{'gainDb': -3.0}
          : null;
    });
    messenger.setMockMessageHandler('flutter/assets', (ByteData? message) async {
      final key = utf8.decode(message!.buffer.asUint8List());
      if (key != AudioLoudnessManifest.assetKey) return null;
      final bytes = utf8.encode(
        jsonEncode({
          'gainDb': {measuredAsset: manifestGainDb},
        }),
      );
      return ByteData.sublistView(Uint8List.fromList(bytes));
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    AudioLoudnessManifest.resetForTesting();
    messenger.setMockMethodCallHandler(sessionChannel, null);
    messenger.setMockMethodCallHandler(pathProviderChannel, null);
    messenger.setMockMethodCallHandler(levelChannel, null);
    messenger.setMockMessageHandler('flutter/assets', null);
    tempDirectory.deleteSync(recursive: true);
  });

  JustAudioPlaybackService serviceWith(ControlledPlayer player) {
    final cache = ControlledCache();
    final service = JustAudioPlaybackService(player: player, cache: cache);
    addTearDown(() async {
      await service.dispose();
      cache.dispose();
    });
    return service;
  }

  double volumeFor(double gainDb) => math.pow(10, gainDb / 20).toDouble();

  test('iOS attenuates a bundled clip to the gain measured at build time', () async {
    // iOS cannot measure anything at runtime, so before the manifest the
    // catalogue's ~18 dB spread reached the child untouched.
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final player = ControlledPlayer();
    final service = serviceWith(player);

    await service.play(measuredUri);
    await flushMicrotasks();

    expect(player.volumeChanges, contains(closeTo(volumeFor(manifestGainDb), 1e-9)));
    expect(
      levelCalls.where((call) => call.method == 'analyzePlaybackLevel'),
      isEmpty,
      reason: 'iOS has no meter; asking for one would only add a decode',
    );
  });

  test('a measured clip is never re-measured at playback on Android', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final player = ControlledPlayer();
    final service = serviceWith(player);

    await service.play(measuredUri);
    await flushMicrotasks();

    expect(player.volumeChanges, contains(closeTo(volumeFor(manifestGainDb), 1e-9)));
    expect(
      player.volumeChanges,
      isNot(contains(closeTo(volumeFor(-3.0), 1e-9))),
      reason: 'the runtime measurement must not outrank the manifest',
    );
  });

  test('preload does not decode a clip the manifest already covers', () async {
    // Regression: preload warmed the native meter for every clip, including
    // the 2865 whose gain ships in the manifest and whose measurement
    // playback then never reads.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final service = serviceWith(ControlledPlayer());

    await service.preload(measuredUri);
    await flushMicrotasks();

    expect(
      levelCalls.where((call) => call.method == 'analyzePlaybackLevel'),
      isEmpty,
    );
  });

  test('preload still warms the meter for a clip nothing measured', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final service = serviceWith(ControlledPlayer());

    await service.preload(unmeasuredUri);
    await flushMicrotasks();

    expect(
      levelCalls.where((call) => call.method == 'analyzePlaybackLevel'),
      hasLength(1),
    );
  });

  test('a bundled clip the manifest missed is still measured at runtime', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final player = ControlledPlayer();
    final service = serviceWith(player);

    await service.play(missedAssetUri);
    await flushMicrotasks();

    expect(
      levelCalls.where((call) => call.method == 'analyzePlaybackLevel'),
      hasLength(1),
      reason: 'the asset scheme alone must not stand in for a manifest hit',
    );
    expect(player.volumeChanges, contains(closeTo(volumeFor(-3.0), 1e-9)));
  });

  test('preload warms the meter for a bundled clip the manifest missed', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final service = serviceWith(ControlledPlayer());

    await service.preload(missedAssetUri);
    await flushMicrotasks();

    expect(
      levelCalls.where((call) => call.method == 'analyzePlaybackLevel'),
      hasLength(1),
    );
  });

  test('a fixed gain suppresses the preload decode as well', () async {
    // A lesson sets a fixed gain for its whole turn; measuring a clip whose
    // measurement is then discarded is pure cost on the path already reported
    // as slow.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final service = serviceWith(ControlledPlayer());
    await service.setFixedPlaybackGainDb(6);

    await service.preload(unmeasuredUri);
    await flushMicrotasks();

    expect(
      levelCalls.where((call) => call.method == 'analyzePlaybackLevel'),
      isEmpty,
    );
  });
}
