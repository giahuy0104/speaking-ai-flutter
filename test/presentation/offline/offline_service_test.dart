import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_speaking_flutter_app/app/di/offline_dependencies.dart';
import 'package:ai_speaking_flutter_app/data/offline/platform_offline_service.dart';
import 'package:ai_speaking_flutter_app/domain/offline/offline_service.dart';
import 'package:ai_speaking_flutter_app/features/conversation/application/offline_language_service.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/android_offline_speech_model_service.dart';
import 'package:ai_speaking_flutter_app/presentation/offline/bloc/offline_service_bloc.dart';

Future<void> flush() => Future<void>.delayed(Duration.zero);
const missing = AndroidOfflineSpeechModelStatus(
  state: AndroidOfflineSpeechModelState.missing,
);
const installed = AndroidOfflineSpeechModelStatus(
  state: AndroidOfflineSpeechModelState.installed,
);
const pending = AndroidOfflineSpeechModelStatus(
  state: AndroidOfflineSpeechModelState.pending,
);

void main() {
  test(
    'Android aggregates weighted progress and preserves 95% while translation is missing',
    () async {
      final speech = _Speech()
        ..statuses = {
          'en-US': const AndroidOfflineSpeechModelStatus(
            state: AndroidOfflineSpeechModelState.pending,
            progress: 20,
            downloadBytes: 100,
          ),
          'vi-VN': const AndroidOfflineSpeechModelStatus(
            state: AndroidOfflineSpeechModelState.pending,
            progress: 80,
            downloadBytes: 300,
          ),
        };
      final translator = _Translator();
      final service = PlatformOfflineService(
        isAndroid: true,
        consentStore: _Consent(),
        speech: speech,
        translator: translator,
        prepareAppleLocale: (_) async => throw StateError('Not Android'),
      );
      addTearDown(service.close);
      Future<AndroidOfflineSpeechModelStatus> status() => service.readStatus(
        consent: AndroidOfflineSpeechModelConsent.allowed,
        preparingIosModels: false,
      );
      expect((await status()).progress, 65);
      speech.statuses = {'en-US': installed, 'vi-VN': installed};
      expect((await status()).progress, 95);
      expect((await status()).state, AndroidOfflineSpeechModelState.pending);
      translator.ready = true;
      expect((await status()).state, AndroidOfflineSpeechModelState.installed);
    },
  );

  test(
    'Android prepares both locales and Wi-Fi translation, disabling cancels without deleting models',
    () async {
      final speech = _Speech();
      final translator = _Translator();
      final service = PlatformOfflineService(
        isAndroid: true,
        consentStore: _Consent()
          ..value = AndroidOfflineSpeechModelConsent.allowed,
        speech: speech,
        translator: translator,
        prepareAppleLocale: (_) async => false,
      );
      addTearDown(service.close);
      await service.prepareModels(isActive: () => true);
      expect(speech.downloads, ['en-US', 'vi-VN']);
      expect(translator.wifi, [true]);
      await service.writeConsent(AndroidOfflineSpeechModelConsent.declined);
      await service.disableDownloads();
      expect(speech.cancelled, 1);
      await service.prepareModels(isActive: () => true);
      expect(translator.wifi, [true]);
    },
  );

  test(
    'iOS prepares Apple locales then translation and respects revoked consent',
    () async {
      final consent = _Consent()
        ..value = AndroidOfflineSpeechModelConsent.allowed;
      final translator = _Translator();
      final locales = <String>[];
      final gate = Completer<bool>();
      final service = PlatformOfflineService(
        isAndroid: false,
        consentStore: consent,
        speech: _Speech(),
        translator: translator,
        prepareAppleLocale: (locale) {
          locales.add(locale);
          return gate.future;
        },
      );
      addTearDown(service.close);
      final prepare = service.prepareModels(isActive: () => true);
      await flush();
      consent.value = AndroidOfflineSpeechModelConsent.declined;
      gate.complete(true);
      await prepare;
      expect(locales, ['vi-VN', 'en-US']);
      expect(translator.wifi, isEmpty);
      consent.value = AndroidOfflineSpeechModelConsent.allowed;
      await service.prepareModels(isActive: () => true);
      expect(translator.wifi, [true]);
    },
  );

  test(
    'Bloc failed consent write is retryable; refresh does not start a download',
    () async {
      final service = _FakeService();
      final bloc = OfflineDependencies(
        createService: () => service,
      ).createBloc();
      addTearDown(bloc.close);
      await bloc.dispatch(OfflineServiceRefreshRequested());
      expect(bloc.state.busy, isFalse);
      expect(service.prepares, 0);
      service.failWrite = true;
      await bloc.dispatch(OfflineServiceAutomaticDownloadChanged(true));
      expect(bloc.state.saveFailed, isTrue);
      expect(bloc.state.busy, isFalse);
      expect(service.prepares, 0);
      service.failWrite = false;
      await bloc.dispatch(OfflineServiceAutomaticDownloadChanged(true));
      await flush();
      expect(service.prepares, 1);
      expect(bloc.state.saveFailed, isFalse);
      expect(bloc.state.noticeRevision, 2);
    },
  );

  test(
    'late status cannot overwrite a new preference; repeated taps do not duplicate writes',
    () async {
      final service = _FakeService();
      final bloc = OfflineServiceBloc(service: service);
      addTearDown(bloc.close);
      await bloc.dispatch(OfflineServiceRefreshRequested());
      service.statusGate = Completer();
      final refresh = bloc.dispatch(OfflineServiceRefreshRequested());
      await flush();
      service.writeGate = Completer();
      final change = bloc.dispatch(
        OfflineServiceAutomaticDownloadChanged(true),
      );
      await flush();
      await bloc.dispatch(OfflineServiceAutomaticDownloadChanged(true));
      service.statusGate!.complete(missing);
      await refresh;
      expect(bloc.state.busy, isTrue);
      expect(bloc.state.consent, AndroidOfflineSpeechModelConsent.allowed);
      service.writeGate!.complete();
      await change;
      await flush();
      expect(service.writes, 1);
      expect(service.prepares, 1);
    },
  );

  testWidgets(
    'pending polls every two seconds and stops after ready and close',
    (tester) async {
      final service = _FakeService()..status = pending;
      final bloc = OfflineServiceBloc(service: service);
      bloc.add(OfflineServiceRefreshRequested());
      await tester.pump();
      expect(service.reads, 1);
      await tester.pump(const Duration(milliseconds: 1999));
      expect(service.reads, 1);
      await tester.pump(const Duration(milliseconds: 1));
      expect(service.reads, 2);
      service.status = installed;
      await tester.pump(const Duration(seconds: 2));
      expect(service.reads, 3);
      await tester.pump(const Duration(seconds: 4));
      expect(service.reads, 3);
      await tester.runAsync(
        () => bloc.close().timeout(const Duration(seconds: 2)),
      );
      expect(service.closed, isTrue);
      await tester.pump(const Duration(seconds: 4));
      expect(service.reads, 3);
    },
  );

  test(
    'closing while preparation is pending releases handlers and drops late result',
    () async {
      final service = _FakeService()..prepareGate = Completer();
      final bloc = OfflineServiceBloc(service: service);
      await bloc.dispatch(OfflineServiceRefreshRequested());
      await bloc.dispatch(OfflineServiceAutomaticDownloadChanged(true));
      await flush();
      expect(bloc.state.preparingIosModels, isTrue);
      await bloc.close().timeout(const Duration(seconds: 1));
      final state = bloc.state;
      service.prepareGate!.completeError(StateError('late plugin error'));
      await flush();
      expect(bloc.state, same(state));
      expect(service.closed, isTrue);
    },
  );
}

class _Consent implements AndroidOfflineSpeechModelConsentStore {
  AndroidOfflineSpeechModelConsent value =
      AndroidOfflineSpeechModelConsent.undecided;
  @override
  Future<AndroidOfflineSpeechModelConsent> read() async => value;
  @override
  Future<void> write(AndroidOfflineSpeechModelConsent consent) async {
    value = consent;
  }
}

class _Speech implements AndroidOfflineSpeechModelService {
  Map<String, AndroidOfflineSpeechModelStatus> statuses = {};
  final downloads = <String>[];
  int cancelled = 0;
  @override
  Future<AndroidOfflineSpeechModelStatus> status({
    String locale = 'en-US',
  }) async => statuses[locale] ?? missing;
  @override
  Future<AndroidOfflineSpeechModelDownloadResult> requestDownload({
    String locale = 'en-US',
  }) async {
    downloads.add(locale);
    return AndroidOfflineSpeechModelDownloadResult.requested;
  }

  @override
  Future<void> cancelDownload() async {
    cancelled++;
  }
}

class _Translator implements OfflineVietnameseEnglishTranslator {
  bool ready = false;
  final wifi = <bool>[];
  @override
  Future<bool> modelsReady() async => ready;
  @override
  Future<bool> downloadModels({bool wifiOnly = true}) async {
    wifi.add(wifiOnly);
    return ready = true;
  }

  @override
  Future<String> translate(String text) async => text;
  @override
  Future<void> close() async {}
}

class _FakeService implements OfflineService {
  @override
  bool get isAndroid => false;
  AndroidOfflineSpeechModelConsent consent =
      AndroidOfflineSpeechModelConsent.undecided;
  AndroidOfflineSpeechModelStatus status = missing;
  Completer<AndroidOfflineSpeechModelStatus>? statusGate;
  Completer<void>? writeGate;
  Completer<void>? prepareGate;
  bool failWrite = false;
  bool closed = false;
  int reads = 0;
  int prepares = 0;
  int writes = 0;
  @override
  Future<AndroidOfflineSpeechModelConsent> readConsent() async => consent;
  @override
  Future<AndroidOfflineSpeechModelStatus> readStatus({
    required AndroidOfflineSpeechModelConsent consent,
    required bool preparingIosModels,
  }) async {
    reads++;
    return statusGate == null ? status : await statusGate!.future;
  }

  @override
  Future<void> writeConsent(AndroidOfflineSpeechModelConsent value) async {
    writes++;
    if (failWrite) throw StateError('storage failed');
    await writeGate?.future;
    consent = value;
  }

  @override
  Future<AndroidOfflineSpeechModelStatus> disableDownloads() async => missing;
  @override
  Future<void> prepareModels({required bool Function() isActive}) async {
    prepares++;
    await prepareGate?.future;
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}
