import '../../features/listening/application/android_offline_speech_model_service.dart';

/// Operations for the offline pack management UI. Existing native adapters
/// retain ownership of model files and platform downloads.
abstract interface class OfflineService {
  bool get isAndroid;
  Future<AndroidOfflineSpeechModelConsent> readConsent();
  Future<void> writeConsent(AndroidOfflineSpeechModelConsent consent);
  Future<AndroidOfflineSpeechModelStatus> readStatus({
    required AndroidOfflineSpeechModelConsent consent,
    required bool preparingIosModels,
  });
  Future<AndroidOfflineSpeechModelStatus> disableDownloads();
  Future<void> prepareModels({required bool Function() isActive});
  Future<void> close();
}
