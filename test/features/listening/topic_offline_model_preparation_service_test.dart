import 'dart:async';

import 'package:ai_speaking_flutter_app/features/listening/application/android_offline_speech_model_service.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/topic_offline_model_preparation_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_speaking_flutter_app/features/conversation/application/offline_language_service.dart';

void main() {
  for (final terminalState in ['installed', 'unavailable']) {
    testWidgets('iOS $terminalState stops retries without Android calls', (
      tester,
    ) async {
      final apple = _AppleAssets()..state = terminalState;
      final android = _Models();
      final consent = _Consent();
      final service = TopicOfflineModelPreparationService(
        isIos: true,
        appleService: apple,
        service: android,
        consentStore: consent,
      );
      addTearDown(service.dispose);
      await service.prepare();
      await tester.pump(const Duration(minutes: 1));
      expect(apple.calls, 1);
      expect(android.checks, 0);
      expect(android.downloads, isEmpty);
      expect(consent.writes, 0);
      // Re-entry/resume revalidates: Apple may have evicted unused assets.
      await service.prepare();
      expect(apple.calls, 2);
    });
  }

  for (final deferredState in ['waitingForWifi', 'pending', 'deferred']) {
    testWidgets(
      'iOS $deferredState retries across navigation then stops when ready',
      (tester) async {
        final apple = _AppleAssets()..state = deferredState;
        final service = TopicOfflineModelPreparationService(
          isIos: true,
          appleService: apple,
          consentStore: _Consent(),
        );
        addTearDown(service.dispose);
        await service.prepare();
        await tester.pump(const Duration(seconds: 29));
        expect(apple.calls, 1);
        apple.state = 'installed';
        await tester.pump(const Duration(seconds: 1));
        expect(apple.calls, 2);
        await tester.pump(const Duration(minutes: 1));
        expect(apple.calls, 2);
      },
    );
  }

  testWidgets(
    'iOS concurrent Home/resume/timer checks do not duplicate preparation',
    (tester) async {
      final apple = _AppleAssets()..gate = Completer<void>();
      final service = TopicOfflineModelPreparationService(
        isIos: true,
        appleService: apple,
        consentStore: _Consent(),
      );
      addTearDown(service.dispose);
      final first = service.prepare();
      final second = service.prepare();
      await tester.pump(const Duration(seconds: 30));
      expect(apple.calls, 1);
      apple.gate!.complete();
      await Future.wait([first, second]);
    },
  );

  testWidgets(
    'iOS failure is silent and retries; opting out prevents further work',
    (tester) async {
      final apple = _AppleAssets()..fail = true;
      final consent = _Consent();
      final service = TopicOfflineModelPreparationService(
        isIos: true,
        appleService: apple,
        consentStore: consent,
      );
      addTearDown(service.dispose);
      await service.prepare();
      apple.fail = false;
      apple.state = 'waitingForWifi';
      await tester.pump(const Duration(seconds: 30));
      expect(apple.calls, 2);
      consent.value = AndroidOfflineSpeechModelConsent.declined;
      await tester.pump(const Duration(seconds: 30));
      await tester.pump(const Duration(seconds: 30));
      expect(apple.calls, 2);
    },
  );

  testWidgets('iOS explicit opt-out skips preparation from first Home', (
    tester,
  ) async {
    final apple = _AppleAssets();
    final service = TopicOfflineModelPreparationService(
      isIos: true,
      appleService: apple,
      consentStore: _Consent()
        ..value = AndroidOfflineSpeechModelConsent.declined,
    );
    addTearDown(service.dispose);
    await service.prepare();
    await tester.pump(const Duration(minutes: 1));
    expect(apple.calls, 0);
  });

  testWidgets(
    'iOS dispose cancels timer even while Apple operation finishes late',
    (tester) async {
      final apple = _AppleAssets()
        ..gate = Completer<void>()
        ..state = 'deferred';
      final service = TopicOfflineModelPreparationService(
        isIos: true,
        appleService: apple,
        consentStore: _Consent(),
      );
      final pending = service.prepare();
      await tester.pump();
      service.dispose();
      apple.gate!.complete();
      await pending;
      await tester.pump(const Duration(minutes: 1));
      await service.prepare();
      expect(apple.calls, 1);
    },
  );

  test(
    'default Home preparation schedules only English without changing global consent',
    () async {
      final models = _Models();
      final consent = _Consent();
      final service = TopicOfflineModelPreparationService(
        service: models,
        consentStore: consent,
      );
      await service.prepare();
      expect(models.downloads, ['en-US']);
      expect(consent.value, AndroidOfflineSpeechModelConsent.undecided);
      expect(consent.writes, 0);
      // Native job is pending, including when waiting for Wi-Fi; resume does not
      // start a second job or need a screen to stay mounted.
      await service.prepare();
      expect(models.downloads, hasLength(1));
    },
  );

  test('concurrent Home and resume checks share one operation', () async {
    final models = _Models()..gate = Completer<void>();
    final service = TopicOfflineModelPreparationService(
      service: models,
      consentStore: _Consent(),
    );
    final first = service.prepare();
    final second = service.prepare();
    await Future<void>.delayed(Duration.zero);
    expect(models.checks, 1);
    models.gate!.complete();
    await Future.wait([first, second]);
    expect(models.downloads, hasLength(1));
  });

  for (final state in [
    AndroidOfflineSpeechModelState.installed,
    AndroidOfflineSpeechModelState.pending,
    AndroidOfflineSpeechModelState.unavailable,
  ]) {
    test('$state does not schedule a download', () async {
      final models = _Models()..state = state;
      final service = TopicOfflineModelPreparationService(
        service: models,
        consentStore: _Consent(),
      );
      await service.prepare();
      expect(models.downloads, isEmpty);
    });
  }

  test('failed scheduling is silent and can retry on resume', () async {
    final models = _Models()..fail = true;
    final service = TopicOfflineModelPreparationService(
      service: models,
      consentStore: _Consent(),
    );
    await service.prepare();
    models.fail = false;
    await service.prepare();
    expect(models.downloads, ['en-US', 'en-US']);
  });

  test(
    'missing or corrupt model is checked again on a later Home entry',
    () async {
      final models = _Models()
        ..state = AndroidOfflineSpeechModelState.installed;
      final service = TopicOfflineModelPreparationService(
        service: models,
        consentStore: _Consent(),
      );
      await service.prepare();
      models.state = AndroidOfflineSpeechModelState.missing;
      await service.prepare();
      expect(models.downloads, ['en-US']);
    },
  );

  test(
    'explicit opt-out is respected, including while a status query is pending',
    () async {
      final consent = _Consent()
        ..value = AndroidOfflineSpeechModelConsent.declined;
      final models = _Models();
      final service = TopicOfflineModelPreparationService(
        service: models,
        consentStore: consent,
      );
      await service.prepare();
      expect(models.checks, 0);
      consent.value = AndroidOfflineSpeechModelConsent.allowed;
      models.gate = Completer<void>();
      final pending = service.prepare();
      await Future<void>.delayed(Duration.zero);
      consent.value = AndroidOfflineSpeechModelConsent.declined;
      models.gate!.complete();
      await pending;
      expect(models.downloads, isEmpty);
    },
  );

  test(
    'dispose suppresses late scheduling without cancelling the native job',
    () async {
      final models = _Models()..gate = Completer<void>();
      final service = TopicOfflineModelPreparationService(
        service: models,
        consentStore: _Consent(),
      );
      final pending = service.prepare();
      await Future<void>.delayed(Duration.zero);
      service.dispose();
      models.gate!.complete();
      await pending;
      await service.prepare();
      expect(models.downloads, isEmpty);
      expect(models.cancellations, 0);
    },
  );
}

class _Models implements AndroidOfflineSpeechModelService {
  AndroidOfflineSpeechModelState state = AndroidOfflineSpeechModelState.missing;
  Completer<void>? gate;
  int checks = 0;
  int cancellations = 0;
  bool fail = false;
  final downloads = <String>[];
  @override
  Future<AndroidOfflineSpeechModelStatus> status({
    String locale = 'en-US',
  }) async {
    checks++;
    await gate?.future;
    return AndroidOfflineSpeechModelStatus(state: state);
  }

  @override
  Future<AndroidOfflineSpeechModelDownloadResult> requestDownload({
    String locale = 'en-US',
  }) async {
    downloads.add(locale);
    if (fail) throw StateError('scheduler unavailable');
    state = AndroidOfflineSpeechModelState.pending;
    return AndroidOfflineSpeechModelDownloadResult.requested;
  }

  @override
  Future<void> cancelDownload() async {
    cancellations++;
  }
}

class _Consent implements AndroidOfflineSpeechModelConsentStore {
  AndroidOfflineSpeechModelConsent value =
      AndroidOfflineSpeechModelConsent.undecided;
  int writes = 0;
  @override
  Future<AndroidOfflineSpeechModelConsent> read() async => value;
  @override
  Future<void> write(AndroidOfflineSpeechModelConsent consent) async {
    writes++;
    value = consent;
  }
}

class _AppleAssets extends AppleOfflineSpeechAssetService {
  String state = 'installed';
  int calls = 0;
  bool fail = false;
  Completer<void>? gate;
  @override
  Future<String> prepareTopicInBackground() async {
    calls++;
    await gate?.future;
    if (fail) throw StateError('Apple assets temporarily unavailable');
    return state;
  }
}
