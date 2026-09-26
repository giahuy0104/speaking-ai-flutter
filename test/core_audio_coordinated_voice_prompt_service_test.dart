import 'dart:async';

import 'package:ai_speaking_flutter_app/core/audio/audio_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/coordinated_voice_prompt_service.dart';
import 'package:ai_speaking_flutter_app/core/audio/hfp_audio_control.dart';
import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'selected HFP output confirms before speech and stays until completion',
    () async {
      final coordinator = AudioTurnCoordinator();
      addTearDown(coordinator.dispose);
      final route = _PromptRoute()..confirmation = Completer<void>();
      final delegate = _BlockingPromptService();
      final service = CoordinatedVoicePromptService(
        delegate: delegate,
        coordinator: coordinator,
        owner: AudioTurnOwner.mainAssistant,
        selectedOutputRoute: route,
      );
      final operation = service.speakAndWaitOnSelectedMediaOutput('MAIN');
      await route.startRequested.future;
      expect(delegate.startCalls, 0);
      route.confirmation!.complete();
      await delegate.started.future;
      expect(route.stopCalls, 0);
      delegate.finish();
      await operation;
      expect(route.stopCalls, 1);
      expect(coordinator.hasActiveTurn, isFalse);
    },
  );

  test(
    'cancelling pending HFP confirmation never starts the stale prompt',
    () async {
      final coordinator = AudioTurnCoordinator();
      addTearDown(coordinator.dispose);
      final route = _PromptRoute()..confirmation = Completer<void>();
      final delegate = _BlockingPromptService();
      final service = CoordinatedVoicePromptService(
        delegate: delegate,
        coordinator: coordinator,
        owner: AudioTurnOwner.mainAssistant,
        selectedOutputRoute: route,
      );
      final operation = service.speakAndWait('Old');
      await route.startRequested.future;
      await service.stop();
      route.confirmation!.complete();
      await operation;
      expect(delegate.startCalls, 0);
      expect(route.stopCalls, 1);
      expect(coordinator.hasActiveTurn, isFalse);
    },
  );

  test('failed selected route does not fall back to phone audio', () async {
    final coordinator = AudioTurnCoordinator();
    addTearDown(coordinator.dispose);
    final route = _PromptRoute()..failStart = true;
    final delegate = _BlockingPromptService();
    final service = CoordinatedVoicePromptService(
      delegate: delegate,
      coordinator: coordinator,
      owner: AudioTurnOwner.mainAssistant,
      selectedOutputRoute: route,
    );
    await expectLater(
      service.speakAndWait('MAIN'),
      throwsA(isA<HfpAudioException>()),
    );
    expect(delegate.startCalls, 0);
    expect(route.stopCalls, 1);
    expect(coordinator.hasActiveTurn, isFalse);
  });

  test(
    'route loss stops an in-flight prompt instead of continuing on phone',
    () async {
      final coordinator = AudioTurnCoordinator();
      addTearDown(coordinator.dispose);
      final route = _PromptRoute();
      addTearDown(route.changes.close);
      final delegate = _BlockingPromptService();
      final service = CoordinatedVoicePromptService(
        delegate: delegate,
        coordinator: coordinator,
        owner: AudioTurnOwner.mainAssistant,
        selectedOutputRoute: route,
      );
      final operation = service.speakAndWait('MAIN');
      final failure = expectLater(operation, throwsA(isA<HfpAudioException>()));
      await delegate.started.future;
      route.loseRoute();
      await failure;
      expect(delegate.stopCalls, 1);
      expect(route.stopCalls, 1);
      expect(coordinator.hasActiveTurn, isFalse);
    },
  );

  test(
    'no selected Bluetooth leaves ordinary phone output unchanged',
    () async {
      final coordinator = AudioTurnCoordinator();
      addTearDown(coordinator.dispose);
      final route = _PromptRoute()..selected = false;
      final delegate = _CapabilityPromptService();
      final service = CoordinatedVoicePromptService(
        delegate: delegate,
        coordinator: coordinator,
        owner: AudioTurnOwner.mainAssistant,
        selectedOutputRoute: route,
      );
      await service.speakAndWaitOnSelectedMediaOutput('Phone');
      expect(delegate.selectedPrompts, ['vi-VN|Phone']);
      expect(route.startCalls, 0);
      expect(route.stopCalls, 0);
    },
  );

  test('explicit phone-speaker prompt does not acquire selected HFP', () async {
    final coordinator = AudioTurnCoordinator();
    addTearDown(coordinator.dispose);
    final route = _PromptRoute();
    final delegate = _BlockingPromptService()..finish();
    final service = CoordinatedVoicePromptService(
      delegate: delegate,
      coordinator: coordinator,
      owner: AudioTurnOwner.mainAssistant,
      selectedOutputRoute: route,
    );
    await service.speakAndWaitOnPhoneSpeaker('Phone');
    expect(delegate.startCalls, 1);
    expect(route.startCalls, 0);
  });

  test('serializes prompts from different feature owners', () async {
    final coordinator = AudioTurnCoordinator();
    addTearDown(coordinator.dispose);
    final lessonDelegate = _BlockingPromptService();
    final mainDelegate = _BlockingPromptService();
    final lesson = CoordinatedVoicePromptService(
      delegate: lessonDelegate,
      coordinator: coordinator,
      owner: AudioTurnOwner.listeningLesson,
    );
    final main = CoordinatedVoicePromptService(
      delegate: mainDelegate,
      coordinator: coordinator,
      owner: AudioTurnOwner.mainAssistant,
    );

    final lessonPrompt = lesson.speakAndWait('Lesson prompt');
    await lessonDelegate.started.future;
    final mainPrompt = main.speakAndWait('MAIN prompt');
    await Future<void>.delayed(Duration.zero);
    expect(mainDelegate.startCalls, 0);

    lessonDelegate.finish();
    await lessonPrompt;
    await mainDelegate.started.future;
    expect(mainDelegate.startCalls, 1);
    mainDelegate.finish();
    await mainPrompt;
  });

  test('stopping an old prompt cannot stop the next owner', () async {
    final coordinator = AudioTurnCoordinator();
    addTearDown(coordinator.dispose);
    final oldDelegate = _BlockingPromptService();
    final nextDelegate = _BlockingPromptService();
    final oldPrompt = CoordinatedVoicePromptService(
      delegate: oldDelegate,
      coordinator: coordinator,
      owner: AudioTurnOwner.listeningLesson,
    );
    final nextPrompt = CoordinatedVoicePromptService(
      delegate: nextDelegate,
      coordinator: coordinator,
      owner: AudioTurnOwner.mainAssistant,
    );

    final oldOperation = oldPrompt.speakAndWait('Old');
    await oldDelegate.started.future;
    await oldPrompt.stop();
    await oldOperation;

    final nextOperation = nextPrompt.speakAndWait('Next');
    await nextDelegate.started.future;
    await oldPrompt.dispose();
    expect(nextDelegate.stopCalls, 0);
    nextDelegate.finish();
    await nextOperation;
  });

  test('forwards selected-output and ready-cue capabilities', () async {
    final coordinator = AudioTurnCoordinator();
    addTearDown(coordinator.dispose);
    final delegate = _CapabilityPromptService();
    final service = CoordinatedVoicePromptService(
      delegate: delegate,
      coordinator: coordinator,
      owner: AudioTurnOwner.listeningLesson,
    );

    await service.speakAndWaitOnSelectedMediaOutput('English', locale: 'en-US');
    await service.playSpeechReadyCue();
    await service.speakAndWaitStyled(
      'Translation',
      locale: 'en-US',
      speechRate: 0.85,
      pitch: 1.05,
    );

    expect(delegate.selectedPrompts, <String>['en-US|English']);
    expect(delegate.readyCueCalls, 1);
    expect(delegate.styles, ['en-US|Translation|0.85|1.05']);
  });
}

class _PromptRoute implements HfpAudioControl {
  bool selected = true;
  bool failStart = false;
  bool active = false;
  final changes = StreamController<BluetoothAudioStatus>.broadcast(sync: true);
  int startCalls = 0;
  int stopCalls = 0;
  final startRequested = Completer<void>();
  Completer<void>? confirmation;

  @override
  BluetoothAudioStatus get status => BluetoothAudioStatus(
    phase: selected
        ? BluetoothAudioConnectionPhase.ready
        : BluetoothAudioConnectionPhase.idle,
    deviceId: selected ? 'h20' : null,
    routeActive: active,
  );
  @override
  Stream<BluetoothAudioStatus> get statusChanges => changes.stream;
  void loseRoute() {
    active = false;
    changes.add(status);
  }

  @override
  bool get usesBrowserAudioInput => false;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> startAudioRoute() async {
    startCalls++;
    if (!startRequested.isCompleted) startRequested.complete();
    if (failStart) throw const HfpAudioException('H20 unavailable');
    await confirmation?.future;
    active = true;
  }

  @override
  Future<void> stopAudioRoute() async {
    stopCalls++;
  }

  @override
  Future<List<HfpAudioDevice>> findDevices() async => [];
  @override
  Future<void> connect(HfpAudioDevice device) async {}
  @override
  Future<void> disconnect() async {}
  @override
  Future<void> dispose() async {}
}

class _BlockingPromptService implements VoicePromptService {
  Completer<void> started = Completer<void>();
  final Completer<void> _completion = Completer<void>();
  int startCalls = 0;
  int stopCalls = 0;

  void finish() {
    if (!_completion.isCompleted) {
      _completion.complete();
    }
  }

  @override
  Future<void> speak(String text, {String locale = 'vi-VN'}) =>
      speakAndWait(text, locale: locale);

  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) async {
    startCalls += 1;
    if (!started.isCompleted) {
      started.complete();
    }
    await _completion.future;
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
    finish();
  }

  @override
  Future<void> dispose() => stop();
}

class _CapabilityPromptService
    implements
        VoicePromptService,
        SelectedMediaOutputVoicePromptService,
        StyledMediaOutputVoicePromptService,
        SpeechReadyCuePlayer {
  final styles = <String>[];
  final List<String> selectedPrompts = <String>[];
  int readyCueCalls = 0;

  @override
  Future<void> speak(String text, {String locale = 'vi-VN'}) async {}

  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) async {}

  @override
  Future<void> speakAndWaitOnSelectedMediaOutput(
    String text, {
    String locale = 'vi-VN',
  }) async {
    selectedPrompts.add('$locale|$text');
  }

  @override
  Future<void> playSpeechReadyCue() async {
    readyCueCalls += 1;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> speakAndWaitStyled(
    String text, {
    required String locale,
    required double speechRate,
    required double pitch,
  }) async {
    styles.add('$locale|$text|$speechRate|$pitch');
  }
}
