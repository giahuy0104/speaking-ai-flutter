import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import '../../../core/audio/audio_input.dart';
import '../domain/conversation_models.dart';

class OfflineSpeechTranscript {
  const OfflineSpeechTranscript({
    required this.text,
    this.alternatives = const <String>[],
    this.confidence,
  });

  final String text;
  final List<String> alternatives;
  final double? confidence;
}

abstract interface class OfflineVietnameseSpeechRecognizer {
  Future<OfflineSpeechTranscript> recognize(AudioCapture audio);
}

/// Reads the app-owned Vietnamese Vosk model on Android.
///
/// The controller invokes this only after the existing backend request fails,
/// so an online turn continues to use the production ASR pipeline unchanged.
class AndroidVoskVietnameseSpeechRecognizer
    implements OfflineVietnameseSpeechRecognizer {
  const AndroidVoskVietnameseSpeechRecognizer({
    MethodChannel channel = const MethodChannel('homi_offline_speech'),
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<OfflineSpeechTranscript> recognize(AudioCapture audio) async {
    final path = audio.filePath.trim();
    final isWav =
        audio.mimeType.toLowerCase().contains('wav') ||
        path.toLowerCase().endsWith('.wav');
    if (path.isEmpty || !isWav) {
      throw PlatformException(
        code: 'INVALID_RECORDED_AUDIO',
        message: 'Offline Vietnamese recognition requires a WAV recording.',
      );
    }

    final result = await _channel
        .invokeMapMethod<String, dynamic>('recognizeFile', <String, dynamic>{
          'filePath': path,
          'locale': 'vi-VN',
          'preferOnDevice': true,
          'requireOnDevice': true,
        });
    final transcript = '${result?['text'] ?? ''}'.trim();
    final alternatives = (result?['alternatives'] as List<dynamic>? ?? const [])
        .map((value) => '$value'.trim())
        .where((value) => value.isNotEmpty && value != transcript)
        .toList(growable: false);
    if (transcript.isEmpty) {
      throw PlatformException(
        code: 'OFFLINE_SPEECH_UNCLEAR',
        message: 'Vietnamese speech was not clear enough to recognize.',
      );
    }
    return OfflineSpeechTranscript(
      text: transcript,
      alternatives: alternatives,
      confidence: (result?['confidence'] as num?)?.toDouble(),
    );
  }
}

abstract interface class OfflineVietnameseEnglishTranslator {
  Future<bool> modelsReady();

  Future<bool> downloadModels({bool wifiOnly = true});

  Future<String> translate(String vietnameseText);

  Future<void> close();
}

abstract interface class OfflineVietnameseTargetTranslator {
  Future<bool> modelsReadyFor(TranslationOutputLanguage language);

  Future<bool> downloadAllModels({bool wifiOnly = true});

  Future<String> translateTo(
    String vietnameseText,
    TranslationOutputLanguage language,
  );
}

abstract interface class OfflineEnglishVietnameseTranslator {
  Future<bool> modelsReady();

  Future<String> translate(String englishText);

  Future<void> close();
}

abstract interface class OfflineTranslationAdapter {
  Future<bool> isModelDownloaded(String languageCode);

  Future<bool> downloadModel(String languageCode, {required bool wifiOnly});

  Future<String> translate(String text);

  Future<void> close();
}

abstract interface class OfflineTargetTranslationAdapter {
  Future<String> translateTo(String text, TranslationOutputLanguage language);
}

class MlKitOfflineTranslationAdapter
    implements OfflineTranslationAdapter, OfflineTargetTranslationAdapter {
  MlKitOfflineTranslationAdapter()
    : _modelManager = OnDeviceTranslatorModelManager(),
      _translator = OnDeviceTranslator(
        sourceLanguage: TranslateLanguage.vietnamese,
        targetLanguage: TranslateLanguage.english,
      );

  final OnDeviceTranslatorModelManager _modelManager;
  final OnDeviceTranslator _translator;
  final Map<TranslationOutputLanguage, OnDeviceTranslator> _targetTranslators =
      <TranslationOutputLanguage, OnDeviceTranslator>{};

  @override
  Future<bool> isModelDownloaded(String languageCode) {
    return _modelManager.isModelDownloaded(languageCode);
  }

  @override
  Future<bool> downloadModel(String languageCode, {required bool wifiOnly}) {
    return _modelManager.downloadModel(languageCode, isWifiRequired: wifiOnly);
  }

  @override
  Future<String> translate(String text) {
    return _translator.translateText(text);
  }

  @override
  Future<String> translateTo(String text, TranslationOutputLanguage language) {
    if (language == TranslationOutputLanguage.english) return translate(text);
    final translator = _targetTranslators.putIfAbsent(
      language,
      () => OnDeviceTranslator(
        sourceLanguage: TranslateLanguage.vietnamese,
        targetLanguage: switch (language) {
          TranslationOutputLanguage.chinese => TranslateLanguage.chinese,
          TranslationOutputLanguage.japanese => TranslateLanguage.japanese,
          TranslationOutputLanguage.korean => TranslateLanguage.korean,
          TranslationOutputLanguage.french => TranslateLanguage.french,
          TranslationOutputLanguage.english => TranslateLanguage.english,
        },
      ),
    );
    return translator.translateText(text);
  }

  @override
  Future<void> close() async {
    await Future.wait<void>(<Future<void>>[
      _translator.close(),
      ..._targetTranslators.values.map((translator) => translator.close()),
    ]);
    _targetTranslators.clear();
  }
}

/// Android/iOS on-device Vietnamese translation for every output language.
///
/// ML Kit stores downloaded language packs in the platform model store.
class MlKitOfflineVietnameseEnglishTranslator
    implements
        OfflineVietnameseEnglishTranslator,
        OfflineVietnameseTargetTranslator {
  MlKitOfflineVietnameseEnglishTranslator({
    OfflineTranslationAdapter? adapter,
    bool? enabled,
  }) : _adapter = adapter ?? MlKitOfflineTranslationAdapter(),
       _enabled =
           enabled ??
           (!kIsWeb &&
               (defaultTargetPlatform == TargetPlatform.android ||
                   defaultTargetPlatform == TargetPlatform.iOS));

  static const String _vietnameseCode = 'vi';

  final OfflineTranslationAdapter _adapter;
  final bool _enabled;
  Future<bool>? _downloadOperation;
  bool _closed = false;

  @override
  Future<bool> modelsReady() async {
    return modelsReadyFor(TranslationOutputLanguage.english);
  }

  @override
  Future<bool> modelsReadyFor(TranslationOutputLanguage language) async {
    if (!_enabled || _closed) {
      return false;
    }
    try {
      final states = await Future.wait<bool>(<Future<bool>>[
        _adapter.isModelDownloaded(_vietnameseCode),
        if (language != TranslationOutputLanguage.english)
          _adapter.isModelDownloaded(language.apiValue),
      ]);
      return states.every((ready) => ready);
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> downloadModels({bool wifiOnly = true}) {
    if (!_enabled || _closed) {
      return Future<bool>.value(false);
    }
    final active = _downloadOperation;
    if (active != null) {
      return active;
    }
    final operation = _downloadModels(wifiOnly: wifiOnly);
    _downloadOperation = operation;
    operation.then<void>(
      (_) {
        if (identical(_downloadOperation, operation)) {
          _downloadOperation = null;
        }
      },
      onError: (Object _, StackTrace stackTrace) {
        if (identical(_downloadOperation, operation)) {
          _downloadOperation = null;
        }
      },
    );
    return operation;
  }

  Future<bool> _downloadModels({required bool wifiOnly}) async {
    try {
      Future<bool> ensureModel(String languageCode) async {
        if (_closed) return false;
        if (!await _adapter.isModelDownloaded(languageCode)) {
          if (_closed) return false;
          return _adapter.downloadModel(languageCode, wifiOnly: wifiOnly);
        }
        return true;
      }

      if (!await ensureModel(_vietnameseCode)) return false;
      return modelsReady();
    } on MissingPluginException {
      return false;
    } on PlatformException catch (error) {
      debugPrint('Offline translation model download skipped: $error');
      return false;
    }
  }

  @override
  Future<bool> downloadAllModels({bool wifiOnly = true}) async {
    if (!_enabled || _closed) return false;
    try {
      final codes = <String>[
        _vietnameseCode,
        ...TranslationOutputLanguage.values
            .where((language) => language != TranslationOutputLanguage.english)
            .map((language) => language.apiValue),
      ];
      // Queue every iOS download while the app is active so ML Kit can keep
      // downloading when the setup screen is dismissed.
      final results = await Future.wait<bool>(
        codes.map((code) async {
          if (_closed) return false;
          if (await _adapter.isModelDownloaded(code)) return true;
          if (_closed) return false;
          return _adapter.downloadModel(code, wifiOnly: wifiOnly);
        }),
      );
      if (results.any((ready) => !ready)) return false;
      final ready = await Future.wait<bool>(
        TranslationOutputLanguage.values.map(modelsReadyFor),
      );
      return ready.every((value) => value);
    } on MissingPluginException {
      return false;
    } on PlatformException catch (error) {
      debugPrint('Offline translation model download skipped: $error');
      return false;
    }
  }

  @override
  Future<String> translate(String vietnameseText) async {
    return translateTo(vietnameseText, TranslationOutputLanguage.english);
  }

  @override
  Future<String> translateTo(
    String vietnameseText,
    TranslationOutputLanguage language,
  ) async {
    final source = vietnameseText.trim();
    if (source.isEmpty) {
      return '';
    }
    if (!await modelsReadyFor(language)) {
      throw PlatformException(
        code: 'OFFLINE_TRANSLATION_MODEL_UNAVAILABLE',
        message: 'The translation models are not installed.',
      );
    }
    if (language == TranslationOutputLanguage.english) {
      return (await _adapter.translate(source)).trim();
    }
    final adapter = _adapter;
    if (adapter is! OfflineTargetTranslationAdapter) {
      throw PlatformException(
        code: 'OFFLINE_TRANSLATION_TARGET_UNAVAILABLE',
        message: 'The selected language is unavailable on this device.',
      );
    }
    return (await (adapter as OfflineTargetTranslationAdapter).translateTo(
      source,
      language,
    )).trim();
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    try {
      await _adapter.close();
    } on MissingPluginException {
      // The service may be disposed by a widget test without a native host.
    }
  }
}

/// On-device English-to-Vietnamese companion used by parent-authored
/// vocabulary sentences. It shares ML Kit's downloaded language models with
/// [MlKitOfflineVietnameseEnglishTranslator] and never consumes AI tokens.
class MlKitOfflineEnglishVietnameseTranslator
    implements OfflineEnglishVietnameseTranslator {
  MlKitOfflineEnglishVietnameseTranslator({bool? enabled})
    : _enabled =
          enabled ??
          (!kIsWeb &&
              (defaultTargetPlatform == TargetPlatform.android ||
                  defaultTargetPlatform == TargetPlatform.iOS)),
      _modelManager = OnDeviceTranslatorModelManager(),
      _translator = OnDeviceTranslator(
        sourceLanguage: TranslateLanguage.english,
        targetLanguage: TranslateLanguage.vietnamese,
      );

  final bool _enabled;
  final OnDeviceTranslatorModelManager _modelManager;
  final OnDeviceTranslator _translator;
  bool _closed = false;

  @override
  Future<bool> modelsReady() async {
    if (!_enabled || _closed) return false;
    try {
      // English is bundled with ML Kit on both platforms.
      return _modelManager.isModelDownloaded('vi');
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<String> translate(String englishText) async {
    final source = englishText.trim();
    if (source.isEmpty) return '';
    if (!await modelsReady()) {
      throw PlatformException(
        code: 'OFFLINE_TRANSLATION_MODEL_UNAVAILABLE',
        message: 'English and Vietnamese translation models are not installed.',
      );
    }
    return (await _translator.translateText(source)).trim();
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _translator.close();
    } on MissingPluginException {
      // Widget tests and unsupported hosts do not register the ML Kit plugin.
    }
  }
}

/// Requests the Apple Speech locale assets in advance. On iOS 26 the native
/// bridge downloads SpeechAnalyzer assets; on iOS 15.5-25 it validates that
/// SFSpeechRecognizer can perform on-device recognition for the locale.
class AppleOfflineSpeechAssetService {
  const AppleOfflineSpeechAssetService({
    MethodChannel channel = const MethodChannel('ailingo_speech'),
  }) : _channel = channel;

  final MethodChannel _channel;

  /// Asset-only preparation: no permission prompt or audio session mutation.
  /// Native checks installed assets first and only starts downloads on Wi-Fi.
  Future<String> prepareTopicInBackground() async {
    return await _channel.invokeMethod<String>(
          'speech.prepareTopicAssets',
          const <String, dynamic>{'locale': 'en-US'},
        ) ??
        'unavailable';
  }

  Future<String> prepareBackgroundLocale(String locale) async {
    try {
      return await _channel.invokeMethod<String>(
            'speech.prepareBackgroundAssets',
            <String, dynamic>{'locale': locale},
          ) ??
          'unavailable';
    } on MissingPluginException {
      return 'unavailable';
    } on PlatformException catch (error) {
      debugPrint('Apple offline speech locale $locale is unavailable: $error');
      return 'deferred';
    }
  }
}
