import 'dart:async';

import 'package:ai_speaking_flutter_app/core/platform/background_learning_session.dart';
import 'package:ai_speaking_flutter_app/features/home/application/background_learning_coordinator.dart';
import 'package:ai_speaking_flutter_app/features/listening/data/active_listening_session_store.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final platform in <TargetPlatform>[
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    test(
      '${platform.name} waits for native stop before re-enabling voice',
      () async {
        final session = _FakeBackgroundSession();
        addTearDown(session.dispose);
        final nativeStop = Completer<void>();
        final directives = <BackgroundLearningDirective>[];
        final coordinator = BackgroundLearningCoordinator(
          session: session,
          initialLifecycleState: AppLifecycleState.resumed,
          onDirective: directives.add,
          isWeb: false,
          targetPlatform: platform,
        );
        addTearDown(coordinator.dispose);
        await coordinator.initialize(voiceAccessEnabled: true);
        session.onStop = () => nativeStop.future;

        final stopping = coordinator.updateVoiceAccess(false);
        final enabling = coordinator.updateVoiceAccess(true);
        session.emit(
          const BackgroundLearningEvent(
            type: BackgroundLearningEventType.resumable,
            reason: 'audio_session_interruption_ended',
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(session.startCount, 1);
        expect(coordinator.isActive, isFalse);
        expect(directives, <BackgroundLearningDirective>[
          BackgroundLearningDirective.keepVoiceNavigation,
        ]);

        session.onStop = null;
        nativeStop.complete();
        await stopping;
        await enabling;

        expect(session.startCount, 2);
        expect(coordinator.isActive, isTrue);
        expect(directives, <BackgroundLearningDirective>[
          BackgroundLearningDirective.keepVoiceNavigation,
          BackgroundLearningDirective.keepVoiceNavigation,
        ]);
      },
    );

    test(
      '${platform.name} cannot restore voice after a revoked start',
      () async {
        final session = _FakeBackgroundSession();
        addTearDown(session.dispose);
        final nativeStart = Completer<bool>();
        session.onStart = () => nativeStart.future;
        final directives = <BackgroundLearningDirective>[];
        final coordinator = BackgroundLearningCoordinator(
          session: session,
          initialLifecycleState: AppLifecycleState.resumed,
          onDirective: directives.add,
          isWeb: false,
          targetPlatform: platform,
        );
        addTearDown(coordinator.dispose);

        final starting = coordinator.initialize(voiceAccessEnabled: true);
        await coordinator.updateVoiceAccess(false);
        session.emit(
          const BackgroundLearningEvent(
            type: BackgroundLearningEventType.resumable,
            reason: 'audio_session_interruption_ended',
          ),
        );
        nativeStart.complete(true);
        await starting;
        await Future<void>.delayed(Duration.zero);

        expect(coordinator.isActive, isFalse);
        expect(directives, isEmpty);
        expect(session.startCount, 1);
        expect(session.stopCount, 2);
      },
    );

    test('${platform.name} retries a failed native background start', () async {
      final session = _FakeBackgroundSession();
      addTearDown(session.dispose);
      session.onStart = () async => throw StateError('native start failed');
      final directives = <BackgroundLearningDirective>[];
      final coordinator = BackgroundLearningCoordinator(
        session: session,
        initialLifecycleState: AppLifecycleState.resumed,
        onDirective: directives.add,
        isWeb: false,
        targetPlatform: platform,
      );
      addTearDown(coordinator.dispose);

      await coordinator.initialize(voiceAccessEnabled: true);
      expect(coordinator.isActive, isFalse);
      expect(directives, isEmpty);
      session.onStart = null;
      await coordinator.ensureStarted(voiceAccessEnabled: true);

      expect(session.startCount, 2);
      expect(coordinator.isActive, isTrue);
      expect(directives, <BackgroundLearningDirective>[
        BackgroundLearningDirective.keepVoiceNavigation,
      ]);
    });
  }

  test('iOS re-enables voice after the revoked native start settles', () async {
    final session = _FakeBackgroundSession();
    addTearDown(session.dispose);
    final nativeStart = Completer<bool>();
    session.onStart = () => nativeStart.future;
    final directives = <BackgroundLearningDirective>[];
    final coordinator = BackgroundLearningCoordinator(
      session: session,
      initialLifecycleState: AppLifecycleState.resumed,
      onDirective: directives.add,
      isWeb: false,
      targetPlatform: TargetPlatform.iOS,
    );
    addTearDown(coordinator.dispose);

    final starting = coordinator.initialize(voiceAccessEnabled: true);
    await coordinator.updateVoiceAccess(false);
    await coordinator.updateVoiceAccess(true);
    session.onStart = null;
    nativeStart.complete(true);
    await starting;
    await Future<void>.delayed(Duration.zero);

    expect(session.startCount, 2);
    expect(session.stopCount, 2);
    expect(coordinator.isActive, isTrue);
    expect(directives, <BackgroundLearningDirective>[
      BackgroundLearningDirective.keepVoiceNavigation,
    ]);
  });

  test(
    'iOS closes a native start that completes after Home disposal',
    () async {
      final session = _FakeBackgroundSession();
      addTearDown(session.dispose);
      final nativeStart = Completer<bool>();
      session.onStart = () => nativeStart.future;
      final directives = <BackgroundLearningDirective>[];
      final coordinator = BackgroundLearningCoordinator(
        session: session,
        initialLifecycleState: AppLifecycleState.resumed,
        onDirective: directives.add,
        isWeb: false,
        targetPlatform: TargetPlatform.iOS,
      );
      addTearDown(coordinator.dispose);

      final starting = coordinator.initialize(voiceAccessEnabled: true);
      coordinator.dispose();
      nativeStart.complete(true);
      await starting;

      expect(coordinator.isActive, isFalse);
      expect(directives, isEmpty);
      expect(session.stopCount, 2);
    },
  );

  test(
    'iOS detached lifecycle invalidates pending native background start',
    () async {
      final session = _FakeBackgroundSession();
      addTearDown(session.dispose);
      final nativeStart = Completer<bool>();
      session.onStart = () => nativeStart.future;
      final directives = <BackgroundLearningDirective>[];
      final coordinator = BackgroundLearningCoordinator(
        session: session,
        initialLifecycleState: AppLifecycleState.resumed,
        onDirective: directives.add,
        isWeb: false,
        targetPlatform: TargetPlatform.iOS,
      );
      addTearDown(coordinator.dispose);

      final starting = coordinator.initialize(voiceAccessEnabled: true);
      expect(
        coordinator.handleLifecycle(
          AppLifecycleState.detached,
          voiceAccessEnabled: true,
          explicitMainSessionActive: true,
        ),
        BackgroundLearningDirective.pauseVoiceNavigation,
      );
      nativeStart.complete(true);
      await starting;

      session.emit(
        const BackgroundLearningEvent(
          type: BackgroundLearningEventType.resumable,
          reason: 'audio_session_interruption_ended',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(coordinator.isActive, isFalse);
      expect(directives, isEmpty);
      expect(session.startCount, 1);
      expect(session.stopCount, 2);

      session.onStart = null;
      coordinator.handleLifecycle(
        AppLifecycleState.resumed,
        voiceAccessEnabled: true,
        explicitMainSessionActive: false,
      );
      await Future<void>.delayed(Duration.zero);
      expect(session.startCount, 2);
      expect(coordinator.isActive, isTrue);
    },
  );

  test(
    'Android keeps only an explicit MAIN microphone in background',
    () async {
      final session = _FakeBackgroundSession();
      addTearDown(session.dispose);
      final directives = <BackgroundLearningDirective>[];
      final coordinator = BackgroundLearningCoordinator(
        session: session,
        initialLifecycleState: AppLifecycleState.resumed,
        onDirective: directives.add,
        isWeb: false,
        targetPlatform: TargetPlatform.android,
      );
      addTearDown(coordinator.dispose);
      await coordinator.initialize(voiceAccessEnabled: true);

      expect(
        coordinator.handleLifecycle(
          AppLifecycleState.paused,
          voiceAccessEnabled: true,
          explicitMainSessionActive: false,
        ),
        BackgroundLearningDirective.pauseVoiceNavigation,
      );
      expect(
        coordinator.handleLifecycle(
          AppLifecycleState.paused,
          voiceAccessEnabled: true,
          explicitMainSessionActive: true,
        ),
        BackgroundLearningDirective.keepVoiceNavigation,
      );
      expect(session.stopCount, 0);
    },
  );

  test('native interruption and resume become typed directives', () async {
    final session = _FakeBackgroundSession();
    addTearDown(session.dispose);
    final directives = <BackgroundLearningDirective>[];
    final coordinator = BackgroundLearningCoordinator(
      session: session,
      initialLifecycleState: AppLifecycleState.resumed,
      onDirective: directives.add,
      isWeb: false,
      targetPlatform: TargetPlatform.android,
    );
    addTearDown(coordinator.dispose);
    await coordinator.initialize(voiceAccessEnabled: true);

    session.emit(
      const BackgroundLearningEvent(
        type: BackgroundLearningEventType.interrupted,
        reason: 'audio_focus_loss',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    session.emit(
      const BackgroundLearningEvent(
        type: BackgroundLearningEventType.resumable,
        reason: 'audio_session_interruption_ended',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(directives, <BackgroundLearningDirective>[
      BackgroundLearningDirective.keepVoiceNavigation,
      BackgroundLearningDirective.pauseVoiceNavigation,
      BackgroundLearningDirective.keepVoiceNavigation,
    ]);
  });

  test(
    'visible resume restarts a session that cannot open mic in background',
    () async {
      final session = _FakeBackgroundSession();
      addTearDown(session.dispose);
      final coordinator = BackgroundLearningCoordinator(
        session: session,
        initialLifecycleState: AppLifecycleState.paused,
        onDirective: (_) {},
        isWeb: false,
        targetPlatform: TargetPlatform.android,
      );
      addTearDown(coordinator.dispose);
      await coordinator.initialize(voiceAccessEnabled: true);
      session.emit(
        const BackgroundLearningEvent(
          type: BackgroundLearningEventType.resumable,
          reason: 'microphone_requires_visible_resume',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      coordinator.handleLifecycle(
        AppLifecycleState.resumed,
        voiceAccessEnabled: true,
        explicitMainSessionActive: true,
      );
      await Future<void>.delayed(Duration.zero);

      expect(session.startCount, 2);
    },
  );

  test(
    'restores one listening checkpoint only after iOS is foreground',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await const ActiveListeningSessionStore().save(
        childAge: 8,
        topicNumber: 2,
        lessonNumber: 3,
      );
      final session = _FakeBackgroundSession();
      addTearDown(session.dispose);
      final coordinator = BackgroundLearningCoordinator(
        session: session,
        initialLifecycleState: AppLifecycleState.paused,
        onDirective: (_) {},
        isWeb: false,
        targetPlatform: TargetPlatform.iOS,
      );
      addTearDown(coordinator.dispose);

      expect(
        await coordinator.takeListeningCheckpoint(voiceAccessEnabled: true),
        isNull,
      );
      coordinator.handleLifecycle(
        AppLifecycleState.resumed,
        voiceAccessEnabled: true,
        explicitMainSessionActive: false,
      );
      final checkpoint = await coordinator.takeListeningCheckpoint(
        voiceAccessEnabled: true,
      );

      expect(checkpoint?.childAge, 8);
      expect(checkpoint?.topicNumber, 2);
      expect(checkpoint?.lessonNumber, 3);
      expect(
        await coordinator.takeListeningCheckpoint(voiceAccessEnabled: true),
        isNull,
      );
    },
  );

  test(
    'forwards active-learning wake ownership without owning audio',
    () async {
      final session = _FakeBackgroundSession();
      addTearDown(session.dispose);
      final coordinator = BackgroundLearningCoordinator(
        session: session,
        initialLifecycleState: AppLifecycleState.resumed,
        onDirective: (_) {},
        isWeb: false,
        targetPlatform: TargetPlatform.android,
      );
      addTearDown(coordinator.dispose);

      await coordinator.setActiveLearning(true);
      await coordinator.setActiveLearning(false);

      expect(session.activeLearningValues, <bool>[true, false]);
    },
  );
}

class _FakeBackgroundSession
    implements
        BackgroundLearningSessionControl,
        ActiveLearningBackgroundSessionControl {
  final StreamController<BackgroundLearningEvent> _events =
      StreamController<BackgroundLearningEvent>.broadcast();
  int startCount = 0;
  int stopCount = 0;
  Future<bool> Function()? onStart;
  Future<void> Function()? onStop;
  final List<bool> activeLearningValues = <bool>[];

  @override
  Stream<BackgroundLearningEvent> get events => _events.stream;

  @override
  Future<bool> start() async {
    startCount += 1;
    if (onStart != null) return onStart!();
    return true;
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
    await onStop?.call();
  }

  @override
  Future<void> setActiveLearning(bool active) async {
    activeLearningValues.add(active);
  }

  void emit(BackgroundLearningEvent event) => _events.add(event);

  Future<void> dispose() => _events.close();
}
