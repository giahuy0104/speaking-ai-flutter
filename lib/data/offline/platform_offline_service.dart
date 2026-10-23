import '../../domain/offline/offline_service.dart';
import '../../features/conversation/application/offline_language_service.dart';
import '../../features/listening/application/android_offline_speech_model_service.dart';

class PlatformOfflineService implements OfflineService {
  PlatformOfflineService({
    required this.isAndroid,
    required AndroidOfflineSpeechModelConsentStore consentStore,
    required AndroidOfflineSpeechModelService speech,
    required OfflineVietnameseEnglishTranslator translator,
    required Future<bool> Function(String) prepareAppleLocale,
  }) : _consentStore = consentStore,
       _speech = speech,
       _translator = translator,
       _prepareAppleLocale = prepareAppleLocale,
       _coordinator = AndroidOfflineSpeechModelCoordinator(
         service: speech,
         consentStore: consentStore,
       );

  @override
  final bool isAndroid;
  final AndroidOfflineSpeechModelConsentStore _consentStore;
  final AndroidOfflineSpeechModelService _speech;
  final OfflineVietnameseEnglishTranslator _translator;
  final Future<bool> Function(String) _prepareAppleLocale;
  final AndroidOfflineSpeechModelCoordinator _coordinator;
  bool _closed = false;

  @override
  Future<AndroidOfflineSpeechModelConsent> readConsent() =>
      _consentStore.read();
  @override
  Future<void> writeConsent(AndroidOfflineSpeechModelConsent consent) =>
      _consentStore.write(consent);

  @override
  Future<AndroidOfflineSpeechModelStatus> readStatus({
    required AndroidOfflineSpeechModelConsent consent,
    required bool preparingIosModels,
  }) async {
    final translationReady = await _translator.modelsReady();
    if (isAndroid) {
      final statuses = await Future.wait<AndroidOfflineSpeechModelStatus>([
        _speech.status(locale: 'en-US'),
        _speech.status(locale: 'vi-VN'),
      ]);
      return _combineAndroidStatuses(
        statuses,
        translationReady: translationReady,
        automaticDownloadAllowed:
            consent == AndroidOfflineSpeechModelConsent.allowed,
      );
    }
    return AndroidOfflineSpeechModelStatus(
      state: translationReady
          ? AndroidOfflineSpeechModelState.installed
          : preparingIosModels
          ? AndroidOfflineSpeechModelState.pending
          : AndroidOfflineSpeechModelState.missing,
      appManaged: true,
      modelId: 'apple-speech+mlkit-vi-en',
    );
  }

  @override
  Future<AndroidOfflineSpeechModelStatus> disableDownloads() async {
    if (isAndroid) {
      await _speech.cancelDownload();
      return _speech.status();
    }
    return const AndroidOfflineSpeechModelStatus(
      state: AndroidOfflineSpeechModelState.missing,
      appManaged: true,
      modelId: 'apple-speech',
    );
  }

  @override
  Future<void> prepareModels({required bool Function() isActive}) async {
    if (_closed ||
        !isActive() ||
        await readConsent() != AndroidOfflineSpeechModelConsent.allowed) {
      return;
    }
    if (_closed || !isActive()) return;
    if (isAndroid) {
      await Future.wait<AndroidOfflineSpeechModelPreparationResult>([
        _coordinator.prepare(locale: 'en-US'),
        _coordinator.prepare(locale: 'vi-VN'),
      ]);
    } else {
      for (final locale in const ['vi-VN', 'en-US']) {
        if (_closed || !isActive()) return;
        await _prepareAppleLocale(locale);
      }
    }
    if (!_closed &&
        isActive() &&
        await readConsent() == AndroidOfflineSpeechModelConsent.allowed) {
      if (_closed || !isActive()) return;
      await _translator.downloadModels(wifiOnly: true);
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _translator.close();
  }

  AndroidOfflineSpeechModelStatus _combineAndroidStatuses(
    List<AndroidOfflineSpeechModelStatus> statuses, {
    required bool translationReady,
    required bool automaticDownloadAllowed,
  }) {
    final states = statuses.map((status) => status.state).toSet();
    final allSpeechInstalled = states.every(
      (state) => state == AndroidOfflineSpeechModelState.installed,
    );
    final state = allSpeechInstalled && translationReady
        ? AndroidOfflineSpeechModelState.installed
        : states.contains(AndroidOfflineSpeechModelState.pending) ||
              (automaticDownloadAllowed && !translationReady)
        ? AndroidOfflineSpeechModelState.pending
        : states.contains(AndroidOfflineSpeechModelState.unavailable)
        ? AndroidOfflineSpeechModelState.unavailable
        : AndroidOfflineSpeechModelState.missing;
    final totalBytes = statuses.fold<int>(
      0,
      (sum, status) => sum + (status.downloadBytes ?? 0),
    );
    final weightedProgress = totalBytes <= 0
        ? statuses.isEmpty
              ? 0
              : statuses.fold<int>(0, (sum, status) => sum + status.progress) ~/
                    statuses.length
        : statuses.fold<int>(
                0,
                (sum, status) =>
                    sum + status.progress * (status.downloadBytes ?? 0),
              ) ~/
              totalBytes;
    final progress = allSpeechInstalled && !translationReady
        ? 95
        : weightedProgress;
    return AndroidOfflineSpeechModelStatus(
      state: state,
      appManaged: true,
      progress: progress,
      modelId: 'vosk-en-us+vi-vn',
      downloadBytes: totalBytes,
    );
  }
}
