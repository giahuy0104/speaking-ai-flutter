import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../conversation/application/offline_language_service.dart';

import 'android_offline_speech_model_service.dart';

/// App-owned preparation triggered after Home's first frame, never awaited by
/// navigation. Android WorkManager / Apple AssetInventory own installation.
/// iOS retries deferred preparation while the app is alive, across navigation.
class TopicOfflineModelPreparationService {
  TopicOfflineModelPreparationService({
    this.isIos = false,
    AppleOfflineSpeechAssetService appleService =
        const AppleOfflineSpeechAssetService(),
    AndroidOfflineSpeechModelService service =
        const MethodChannelAndroidOfflineSpeechModelService(),
    AndroidOfflineSpeechModelConsentStore consentStore =
        const SharedPreferencesAndroidOfflineSpeechModelConsentStore(),
  }) : _appleService = appleService,
       _service = service,
       _consentStore = consentStore;

  final bool isIos;
  final AppleOfflineSpeechAssetService _appleService;
  Timer? _retryTimer;
  final AndroidOfflineSpeechModelService _service;
  final AndroidOfflineSpeechModelConsentStore _consentStore;
  Future<void>? _pending;
  bool _disposed = false;

  Future<void> prepare() {
    if (_disposed) return Future<void>.value();
    if (isIos) {
      _retryTimer ??= Timer.periodic(const Duration(seconds: 30), (_) {
        unawaited(prepare());
      });
    }
    return _pending ??= _prepare().whenComplete(() => _pending = null);
  }

  Future<void> _prepare() async {
    try {
      if ((isIos &&
              await _consentStore.read() ==
                  AndroidOfflineSpeechModelConsent.declined) ||
          _disposed) {
        _stopRetry();
        return;
      }
      if (isIos) {
        final state = await _appleService.prepareTopicInBackground();
        if (state == 'installed' || state == 'unavailable') _stopRetry();
        return;
      }
      final status = await _service.status(locale: 'en-US');
      if (_disposed ||
          status.state == AndroidOfflineSpeechModelState.installed ||
          status.state == AndroidOfflineSpeechModelState.pending ||
          status.state == AndroidOfflineSpeechModelState.unavailable) {
        return;
      }
      if (_disposed) {
        return;
      }
      // Scheduling while offline is intentional. No model bytes are fetched
      // until native constraints permit validated, unmetered Wi-Fi. An unknown
      // status is also safe: native code checks installation before scheduling.
      await _service.requestDownload(locale: 'en-US');
    } catch (error) {
      // A later Home entry/resume can recheck; preparation never blocks learning.
      debugPrint('Topic offline model background preparation deferred: $error');
    }
  }

  void _stopRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void dispose() {
    _disposed = true;
    _stopRetry();
    // Do not cancel the native job merely because the Flutter tree goes away.
  }
}
