import 'package:flutter/foundation.dart';
import '../../data/offline/platform_offline_service.dart';
import '../../domain/offline/offline_service.dart';
import '../../features/conversation/application/offline_language_service.dart';
import '../../features/listening/application/android_offline_speech_model_service.dart';
import '../../presentation/offline/bloc/offline_service_bloc.dart';

class OfflineDependencies {
  const OfflineDependencies({required this.createService});
  final OfflineService Function() createService;
  OfflineServiceBloc createBloc() =>
      OfflineServiceBloc(service: createService());

  static OfflineServiceBloc createPlatformBloc() => OfflineDependencies(
    createService: () => PlatformOfflineService(
      isAndroid: !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
      consentStore:
          const SharedPreferencesAndroidOfflineSpeechModelConsentStore(),
      speech: const MethodChannelAndroidOfflineSpeechModelService(),
      translator: MlKitOfflineVietnameseEnglishTranslator(),
      prepareAppleLocale: const AppleOfflineSpeechAssetService().prepareLocale,
    ),
  ).createBloc();
}
