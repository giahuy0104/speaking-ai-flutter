import 'dart:async';
import 'dart:io';

import 'package:ai_speaking_flutter_app/core/audio/audio_gain.dart';
import 'package:ai_speaking_flutter_app/core/audio/audio_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/audio_playback_service.dart';
import 'package:ai_speaking_flutter_app/core/audio/hfp_audio_control.dart';
import 'package:ai_speaking_flutter_app/core/audio/wav_audio.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_media_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Android lesson capture route', () {
    late Directory temporary;
    late _FakeLessonRecorder recorder;
    late _FakeHfpAudioControl hfp;
    late StreamController<BluetoothAudioStatus> statuses;
    late _RecordingTestMediaService media;

    setUp(() async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      temporary = await Directory.systemTemp.createTemp('lesson-route-test-');
      recorder = _FakeLessonRecorder();
      statuses = StreamController<BluetoothAudioStatus>.broadcast();
      hfp = _FakeHfpAudioControl(
        <String>[],
        status: const BluetoothAudioStatus(
          phase: BluetoothAudioConnectionPhase.recording,
          deviceId: '00:11:22:33:44:55',
          deviceName: 'H20',
          routeActive: true,
        ),
        changes: statuses.stream,
      );
      media = _RecordingTestMediaService(
        '${temporary.path}/attempt.wav',
        recorder: recorder,
        playbackService: _ControlledPlaybackService(),
        hfpAudioControl: hfp,
      );
    });

    tearDown(() async {
      await media.dispose();
      await statuses.close();
      await temporary.delete(recursive: true);
      debugDefaultTargetPlatformOverride = null;
    });

    Future<void> start() => media.startRecording(
      lessonId: 'numbers',
      sentenceNumber: 1,
      saveToHistory: false,
    );

    test('pins H20 input and keeps its output through feedback', () async {
      await start();
      expect(recorder.lastConfig?.device, _FakeLessonRecorder.h20);
      final recording = await media.stopRecording();
      expect(await File(recording.filePath).exists(), isTrue);
      expect(hfp.stopCalls, 0);

      await media.play(Uri.parse('https://example.test/feedback.mp3'));
      expect(hfp.stopCalls, 0);
      await media.stopPlayback();
      expect(hfp.stopCalls, 1);
    });

    test('selected H20 cannot silently fall back to the phone mic', () async {
      recorder.devices = const [_FakeLessonRecorder.phone];
      await expectLater(start(), throwsA(isA<LessonMediaException>()));
      expect(recorder.startCalls, 0);
    });

    test('playback stop cannot release the live recording route', () async {
      await start();
      await media.stopPlayback();
      expect(hfp.stopCalls, 0);
      await media.cancelRecording();
      expect(recorder.cancelCalls, 1);
      expect(hfp.stopCalls, 1);
    });

    test(
      'route lost while recorder starts never reports live capture',
      () async {
        final startGate = Completer<void>();
        recorder.startGate = startGate;
        final starting = start();
        final failed = expectLater(
          starting,
          throwsA(isA<LessonMediaException>()),
        );
        await Future<void>.delayed(Duration.zero);
        hfp.status = const BluetoothAudioStatus(
          phase: BluetoothAudioConnectionPhase.ready,
          deviceId: '00:11:22:33:44:55',
        );
        startGate.complete();
        await failed;
        expect(recorder.cancelCalls, 1);
      },
    );

    test('phone capture still explicitly uses the built-in input', () async {
      hfp.status = const BluetoothAudioStatus(
        phase: BluetoothAudioConnectionPhase.idle,
      );
      await start();
      expect(recorder.lastConfig?.device, _FakeLessonRecorder.phone);
      expect(hfp.startCalls, 0);
      await media.stopRecording();
    });

    test(
      'route loss reports capture failure instead of no recording',
      () async {
        await start();
        final failed = media.recordingErrors.first;
        statuses.add(
          const BluetoothAudioStatus(
            phase: BluetoothAudioConnectionPhase.ready,
            deviceId: '00:11:22:33:44:55',
          ),
        );
        final failure = await failed;
        expect(recorder.cancelCalls, 1);
        await expectLater(media.stopRecording(), throwsA(same(failure)));
      },
    );

    test(
      'delayed loss from an old capture cannot cancel a newer one',
      () async {
        await start();
        final oldStop = Completer<void>();
        recorder.stopGate = oldStop;
        final stopping = media.stopRecording();
        final restarting = start();
        await Future<void>.delayed(Duration.zero);
        statuses.add(
          const BluetoothAudioStatus(
            phase: BluetoothAudioConnectionPhase.ready,
            deviceId: '00:11:22:33:44:55',
          ),
        );
        await Future<void>.delayed(Duration.zero);
        oldStop.complete();
        await stopping;
        await restarting;
        await Future<void>.delayed(Duration.zero);
        expect(recorder.startCalls, 2);
        expect(recorder.cancelCalls, 0);
        await media.stopRecording();
      },
    );
  });

  test(
    'stop during playback preparation prevents a late clip on default output',
    () async {
      final playback = _BlockedPreparationPlaybackService();
      final media = LessonMediaService(playbackService: playback);
      final playing = media.playToCompletion(
        Uri.parse('https://example.test/model.mp3'),
      );
      final cancelled = expectLater(
        playing,
        throwsA(isA<LessonMediaException>()),
      );
      await Future<void>.delayed(Duration.zero);
      await media.stopPlayback();
      playback.ready.complete();
      await cancelled;
      expect(playback.playCalls, 0);
      await media.dispose();
    },
  );
  test(
    'Android route loss stops the clip and fails its completion gate',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final events = <String>[];
      final playback = _RouteAwareControlledPlaybackService(events);
      final statuses = StreamController<BluetoothAudioStatus>.broadcast();
      final hfp = _FakeHfpAudioControl(
        events,
        status: const BluetoothAudioStatus(
          phase: BluetoothAudioConnectionPhase.recording,
          deviceId: 'h20',
          routeActive: true,
        ),
        changes: statuses.stream,
      );
      final media = LessonMediaService(
        playbackService: playback,
        hfpAudioControl: hfp,
      );
      final playing = media.playToCompletion(
        Uri.parse('https://example.test/model.mp3'),
      );
      final failed = expectLater(playing, throwsA(isA<HfpAudioException>()));
      await Future<void>.delayed(Duration.zero);
      statuses.add(
        const BluetoothAudioStatus(
          phase: BluetoothAudioConnectionPhase.ready,
          deviceId: 'h20',
          routeActive: false,
        ),
      );
      await failed;
      expect(playback.stopCalls, 1);
      await media.dispose();
      await statuses.close();
    },
  );
  test(
    'playToCompletion does not finish until playback reports ended',
    () async {
      final playback = _ControlledPlaybackService();
      final mediaService = LessonMediaService(playbackService: playback);
      var completed = false;

      final future = mediaService
          .playToCompletion(Uri.parse('https://example.test/intro.mp3'))
          .then((_) => completed = true);
      await Future<void>.delayed(Duration.zero);

      expect(playback.playCalls, 1);
      expect(completed, isFalse);

      playback.finish();
      await future;
      expect(completed, isTrue);

      await mediaService.dispose();
    },
  );

  test(
    'completion-aware playback ignores a temporary playing false state',
    () async {
      final playback = _CompletionAwareControlledPlaybackService();
      final mediaService = LessonMediaService(playbackService: playback);
      var completed = false;

      final future = mediaService
          .playToCompletion(Uri.parse('https://example.test/next-intro.mp3'))
          .then((_) => completed = true);
      await Future<void>.delayed(Duration.zero);

      playback.pauseTemporarily();
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);

      playback.resume();
      playback.finish();
      await future;
      expect(completed, isTrue);

      await mediaService.dispose();
    },
  );

  test(
    'completion-aware playback ignores a completed state from the old source',
    () async {
      final playback = _StaleCompletionPlaybackService();
      final mediaService = LessonMediaService(playbackService: playback);
      var completed = false;

      final future = mediaService
          .playToCompletion(Uri.parse('https://example.test/new-intro.mp3'))
          .then((_) => completed = true);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(playback.playCalls, 1);
      expect(completed, isFalse);

      playback.finish();
      await future;
      expect(completed, isTrue);

      await mediaService.dispose();
    },
  );

  test(
    'Android selected H20 route is prepared before lesson playback starts',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final events = <String>[];
      final playback = _RouteAwareControlledPlaybackService(events);
      final hfp = _FakeHfpAudioControl(
        events,
        status: const BluetoothAudioStatus(
          phase: BluetoothAudioConnectionPhase.ready,
          deviceId: 'h20-uid',
          deviceName: 'H20',
          sampleRate: 16000,
        ),
      );
      final mediaService = LessonMediaService(
        playbackService: playback,
        hfpAudioControl: hfp,
      );

      final future = mediaService.playToCompletion(
        Uri.parse('https://example.test/guide.mp3'),
      );
      await Future<void>.delayed(Duration.zero);

      expect(events, <String>[
        'communication:true',
        'prepare',
        'hfp:start',
        'play',
      ]);

      playback.finish();
      await future;
      await mediaService.stopPlayback();
      expect(hfp.stopCalls, 1);
      await mediaService.dispose();
    },
  );

  test('iOS selected H20 lesson playback holds HFP for output', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final events = <String>[];
    final playback = _RouteAwareControlledPlaybackService(events);
    final hfp = _FakeHfpAudioControl(
      events,
      status: const BluetoothAudioStatus(
        phase: BluetoothAudioConnectionPhase.ready,
        deviceId: 'h20-uid',
        deviceName: 'H20',
        sampleRate: 16000,
      ),
    );
    final mediaService = LessonMediaService(
      playbackService: playback,
      hfpAudioControl: hfp,
    );

    final playing = mediaService.playToCompletion(
      Uri.parse('https://example.test/guide.mp3'),
    );
    await Future<void>.delayed(Duration.zero);

    expect(events, <String>[
      'communication:true',
      'prepare',
      'hfp:start',
      'play',
    ]);
    expect(hfp.startCalls, 1);

    playback.finish();
    await playing;
    await mediaService.dispose();
  });

  test('phone playback does not activate an unselected HFP route', () async {
    final events = <String>[];
    final playback = _RouteAwareControlledPlaybackService(events);
    final hfp = _FakeHfpAudioControl(
      events,
      status: const BluetoothAudioStatus(
        phase: BluetoothAudioConnectionPhase.idle,
        sampleRate: 16000,
      ),
    );
    final mediaService = LessonMediaService(
      playbackService: playback,
      hfpAudioControl: hfp,
    );

    final future = mediaService.playToCompletion(
      Uri.parse('https://example.test/guide.mp3'),
    );
    await Future<void>.delayed(Duration.zero);

    expect(events, <String>['communication:false', 'prepare', 'play']);
    expect(hfp.startCalls, 0);

    playback.finish();
    await future;
    await mediaService.dispose();
  });

  test(
    'navigation prompt never falls back to the phone when HFP setup fails',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final events = <String>[];
      final playback = _RouteAwareControlledPlaybackService(events);
      final hfp = _FakeHfpAudioControl(
        events,
        status: const BluetoothAudioStatus(
          phase: BluetoothAudioConnectionPhase.ready,
          deviceId: 'h20-uid',
          deviceName: 'H20',
          sampleRate: 16000,
        ),
        startError: const HfpAudioException('SCO is still settling.'),
      );
      final mediaService = LessonMediaService(
        playbackService: playback,
        hfpAudioControl: hfp,
      );

      await expectLater(
        mediaService.prepareSelectedLessonOutput(),
        throwsA(
          isA<HfpAudioException>().having(
            (error) => error.message,
            'message',
            'SCO is still settling.',
          ),
        ),
      );

      expect(events, <String>['communication:true', 'prepare', 'hfp:start']);
      await mediaService.dispose();
    },
  );

  test('coach prompt leaves H20 and plays on the phone speaker', () async {
    final events = <String>[];
    final playback = _RouteAwareControlledPlaybackService(events);
    final hfp = _FakeHfpAudioControl(
      events,
      status: const BluetoothAudioStatus(
        phase: BluetoothAudioConnectionPhase.ready,
        deviceId: 'h20-uid',
        deviceName: 'H20',
        sampleRate: 16000,
      ),
    );
    final mediaService = LessonMediaService(
      playbackService: playback,
      hfpAudioControl: hfp,
    );

    final sample = mediaService.playToCompletion(
      Uri.parse('https://example.test/sample.mp3'),
    );
    await Future<void>.delayed(Duration.zero);
    playback.finish();
    await sample;

    final prompt = mediaService.playToCompletion(
      Uri.parse('https://example.test/coach.mp3'),
      route: LessonPlaybackRoute.phoneSpeaker,
    );
    await Future<void>.delayed(Duration.zero);

    expect(events, <String>[
      'communication:true',
      'prepare',
      'hfp:start',
      'play',
      'communication:false',
      'hfp:stop',
      'prepare',
      'play',
    ]);

    playback.finish();
    await prompt;
    await mediaService.dispose();
  });

  test('consecutive H20 clips revalidate a dropped SCO route', () async {
    final events = <String>[];
    final playback = _RouteAwareControlledPlaybackService(events);
    final hfp = _FakeHfpAudioControl(
      events,
      status: const BluetoothAudioStatus(
        phase: BluetoothAudioConnectionPhase.ready,
        deviceId: 'h20-uid',
        deviceName: 'H20',
        sampleRate: 16000,
      ),
    );
    final mediaService = LessonMediaService(
      playbackService: playback,
      hfpAudioControl: hfp,
    );

    for (final uri in <Uri>[
      Uri.parse('https://example.test/english.mp3'),
      Uri.parse('https://example.test/vietnamese.mp3'),
    ]) {
      final playing = mediaService.playToCompletion(uri);
      await Future<void>.delayed(Duration.zero);
      playback.finish();
      await playing;
    }

    // The fake deliberately keeps routeActive false, modelling Android's
    // Bluetooth audio-disconnected broadcast while the Dart owner survives.
    expect(hfp.startCalls, 2);
    await mediaService.stopPlayback();
    expect(hfp.stopCalls, 1);
    await mediaService.dispose();
  });

  test('child recording gain is applied after H20 route preparation', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final events = <String>[];
    final playback = _GainAwareControlledPlaybackService(events);
    final hfp = _FakeHfpAudioControl(
      events,
      status: const BluetoothAudioStatus(
        phase: BluetoothAudioConnectionPhase.ready,
        deviceId: 'h20-uid',
        deviceName: 'H20',
        sampleRate: 16000,
      ),
    );
    final mediaService = LessonMediaService(
      playbackService: playback,
      hfpAudioControl: hfp,
    );

    await mediaService.play(
      Uri.file('child-recording.wav'),
      playbackGainDb: lessonRecordingPlaybackGainDb,
    );

    expect(events, <String>[
      'communication:true',
      'prepare',
      'hfp:start',
      'gain:$lessonRecordingPlaybackGainDb',
      'play',
    ]);
    await mediaService.dispose();
  });

  test('iOS lesson recording configuration is input-capable', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final hfpSession = lessonRecordingAudioSessionConfiguration(
      useSelectedHfp: true,
    );
    final phoneSession = lessonRecordingAudioSessionConfiguration(
      useSelectedHfp: false,
    );
    final hfpRecord = LessonMediaService.lessonRecordConfig(
      useSelectedHfp: true,
    );
    final phoneRecord = LessonMediaService.lessonRecordConfig(
      useSelectedHfp: false,
    );

    expect(
      hfpSession.avAudioSessionCategory,
      AVAudioSessionCategory.playAndRecord,
    );
    expect(hfpSession.avAudioSessionMode, AVAudioSessionMode.voiceChat);
    expect(
      hfpSession.avAudioSessionCategoryOptions,
      AVAudioSessionCategoryOptions.allowBluetooth,
    );
    expect(
      phoneSession.avAudioSessionCategoryOptions,
      AVAudioSessionCategoryOptions.defaultToSpeaker,
    );
    expect(hfpRecord.iosConfig.categoryOptions, <IosAudioCategoryOption>[
      IosAudioCategoryOption.allowBluetooth,
    ]);
    expect(phoneRecord.iosConfig.categoryOptions, <IosAudioCategoryOption>[
      IosAudioCategoryOption.defaultToSpeaker,
    ]);
    expect(hfpRecord.androidConfig.manageBluetooth, isFalse);
    expect(
      hfpRecord.androidConfig.audioSource,
      AndroidAudioSource.voiceCommunication,
    );
    expect(
      hfpRecord.androidConfig.audioManagerMode,
      AudioManagerMode.modeInCommunication,
    );
    expect(phoneRecord.androidConfig.manageBluetooth, isFalse);
    expect(phoneRecord.androidConfig.audioSource, AndroidAudioSource.mic);
    expect(
      phoneRecord.androidConfig.audioManagerMode,
      AudioManagerMode.modeNormal,
    );
    expect(hfpRecord.encoder, AudioEncoder.aacLc);
  });

  test('Android lesson recording is 16 kHz mono PCM WAV', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final recordConfig = LessonMediaService.lessonRecordConfig(
      useSelectedHfp: false,
    );

    expect(recordConfig.encoder, AudioEncoder.wav);
    expect(recordConfig.sampleRate, 16000);
    expect(recordConfig.numChannels, 1);
  });

  test('iOS recording input selects exact H20 UID and built-in phone mic', () {
    const builtIn = InputDevice(
      id: 'iphone-mic',
      label: 'iPhone Microphone',
      type: InputDeviceType.builtIn,
    );
    const otherHeadset = InputDevice(
      id: 'other-hfp',
      label: 'Other Headset',
      type: InputDeviceType.bluetoothSco,
    );
    const h20 = InputDevice(
      id: 'h20-uid',
      label: 'H20',
      type: InputDeviceType.bluetoothSco,
    );
    const devices = <InputDevice>[builtIn, otherHeadset, h20];

    expect(
      selectLessonRecordingInput(
        devices,
        useSelectedHfp: true,
        selectedHfpDeviceId: 'h20-uid',
      ),
      h20,
    );
    expect(selectLessonRecordingInput(devices, useSelectedHfp: false), builtIn);
  });
}

class _ControlledPlaybackService implements AudioPlaybackService {
  final StreamController<bool> _playing = StreamController<bool>.broadcast();
  int playCalls = 0;
  int stopCalls = 0;

  @override
  Stream<bool> get playingStream => _playing.stream;

  @override
  Future<PlaybackStartMetrics> play(Uri uri) async {
    playCalls += 1;
    _playing.add(true);
    return const PlaybackStartMetrics(
      audioLoadDuration: Duration.zero,
      startedAfterRequest: Duration.zero,
      fromDeviceCache: false,
    );
  }

  void finish() => _playing.add(false);

  @override
  Future<void> prepare() async {}

  @override
  Future<void> preload(Uri uri) async {}

  @override
  Future<void> stop() async {
    stopCalls += 1;
    finish();
  }

  @override
  Future<void> dispose() => _playing.close();
}

class _RecordingTestMediaService extends LessonMediaService {
  _RecordingTestMediaService(
    this.path, {
    super.recorder,
    super.playbackService,
    super.hfpAudioControl,
  });

  final String path;

  @override
  Future<String> recordingPath({
    required String lessonId,
    required int sentenceNumber,
    String? extension,
  }) async => path;
}

class _FakeLessonRecorder implements AudioRecorder {
  static const phone = InputDevice(
    id: '1',
    label: 'Built-in microphone',
    type: InputDeviceType.builtIn,
  );
  static const h20 = InputDevice(
    id: '42',
    label: 'H20',
    type: InputDeviceType.bluetoothSco,
  );

  List<InputDevice> devices = const [phone, h20];
  RecordConfig? lastConfig;
  String? path;
  int startCalls = 0;
  int cancelCalls = 0;
  Completer<void>? stopGate;
  Completer<void>? startGate;

  @override
  Future<bool> hasPermission({bool request = true}) async => true;

  @override
  Future<List<InputDevice>> listInputDevices() async => devices;

  @override
  Future<void> start(RecordConfig config, {required String path}) async {
    lastConfig = config;
    this.path = path;
    startCalls += 1;
    await startGate?.future;
  }

  @override
  Future<String?> stop() async {
    await stopGate?.future;
    await File(
      path!,
    ).writeAsBytes(buildPcm16Wav(Uint8List.fromList([1, 2, 3, 4])));
    return path;
  }

  @override
  Future<void> cancel() async {
    cancelCalls += 1;
  }

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BlockedPreparationPlaybackService extends _ControlledPlaybackService {
  final ready = Completer<void>();
  @override
  Future<void> prepare() => ready.future;
}

class _CompletionAwareControlledPlaybackService
    implements AudioPlaybackService, CompletionAwareAudioPlaybackService {
  final StreamController<bool> _playing = StreamController<bool>.broadcast();
  final StreamController<void> _completed = StreamController<void>.broadcast();

  @override
  Stream<bool> get playingStream => _playing.stream;

  @override
  Stream<void> get completionStream => _completed.stream;

  @override
  Future<PlaybackStartMetrics> play(Uri uri) async {
    _playing.add(true);
    return const PlaybackStartMetrics(
      audioLoadDuration: Duration.zero,
      startedAfterRequest: Duration.zero,
      fromDeviceCache: false,
    );
  }

  void pauseTemporarily() => _playing.add(false);

  void resume() => _playing.add(true);

  void finish() {
    _completed.add(null);
    _playing.add(false);
  }

  @override
  Future<void> prepare() async {}

  @override
  Future<void> preload(Uri uri) async {}

  @override
  Future<void> stop() async => _playing.add(false);

  @override
  Future<void> dispose() async {
    await Future.wait<void>(<Future<void>>[
      _playing.close(),
      _completed.close(),
    ]);
  }
}

class _StaleCompletionPlaybackService
    implements AudioPlaybackService, CompletionAwareAudioPlaybackService {
  _StaleCompletionPlaybackService() {
    _completed = StreamController<void>.broadcast(
      sync: true,
      onListen: () {
        final subscribedBeforeNewSourceStarted = playCalls == 0;
        if (subscribedBeforeNewSourceStarted) {
          scheduleMicrotask(() => _completed.add(null));
        }
      },
    );
  }

  final StreamController<bool> _playing = StreamController<bool>.broadcast();
  late final StreamController<void> _completed;
  int playCalls = 0;

  @override
  Stream<bool> get playingStream => _playing.stream;

  @override
  Stream<void> get completionStream => _completed.stream;

  @override
  Future<PlaybackStartMetrics> play(Uri uri) async {
    playCalls += 1;
    _playing.add(true);
    return const PlaybackStartMetrics(
      audioLoadDuration: Duration.zero,
      startedAfterRequest: Duration.zero,
      fromDeviceCache: false,
    );
  }

  void finish() {
    _completed.add(null);
    _playing.add(false);
  }

  @override
  Future<void> prepare() async {}

  @override
  Future<void> preload(Uri uri) async {}

  @override
  Future<void> stop() async => _playing.add(false);

  @override
  Future<void> dispose() async {
    await Future.wait<void>(<Future<void>>[
      _playing.close(),
      _completed.close(),
    ]);
  }
}

class _RouteAwareControlledPlaybackService extends _ControlledPlaybackService
    implements CommunicationRouteAwareAudioPlaybackService {
  _RouteAwareControlledPlaybackService(this.events);

  final List<String> events;

  @override
  void setCommunicationRouteActive(bool active) {
    events.add('communication:$active');
  }

  @override
  Future<void> prepare() async {
    events.add('prepare');
  }

  @override
  Future<PlaybackStartMetrics> play(Uri uri) {
    events.add('play');
    return super.play(uri);
  }
}

class _GainAwareControlledPlaybackService
    extends _RouteAwareControlledPlaybackService
    implements PlaybackGainAwareAudioPlaybackService {
  _GainAwareControlledPlaybackService(super.events);

  @override
  Future<void> setPlaybackGainDb(double gainDb) async {
    events.add('gain:$gainDb');
  }
}

class _FakeHfpAudioControl implements HfpAudioControl {
  _FakeHfpAudioControl(
    this.events, {
    required this.status,
    this.startError,
    this.changes,
  });

  final List<String> events;
  final Object? startError;
  final Stream<BluetoothAudioStatus>? changes;

  @override
  BluetoothAudioStatus status;

  int startCalls = 0;
  int stopCalls = 0;

  @override
  bool get usesBrowserAudioInput => false;

  @override
  Stream<BluetoothAudioStatus> get statusChanges =>
      changes ?? const Stream<BluetoothAudioStatus>.empty();

  @override
  Future<void> initialize() async {}

  @override
  Future<List<HfpAudioDevice>> findDevices() async => const <HfpAudioDevice>[];

  @override
  Future<void> connect(HfpAudioDevice device) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> startAudioRoute() async {
    startCalls += 1;
    events.add('hfp:start');
    final error = startError;
    if (error != null) throw error;
  }

  @override
  Future<void> stopAudioRoute() async {
    stopCalls += 1;
    events.add('hfp:stop');
  }

  @override
  Future<void> dispose() async {}
}
