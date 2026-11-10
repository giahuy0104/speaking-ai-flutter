import 'dart:async';

import 'package:ai_speaking_flutter_app/core/audio/audio_input.dart';
import 'package:ai_speaking_flutter_app/features/conversation/application/offline_language_service.dart';
import 'package:ai_speaking_flutter_app/features/conversation/domain/conversation_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Home asset warm-up uses permission-free topic channel with English only',
    () async {
      const channel = MethodChannel('test_apple_topic_assets');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return 'waitingForWifi';
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      expect(
        await const AppleOfflineSpeechAssetService(
          channel: channel,
        ).prepareTopicInBackground(),
        'waitingForWifi',
      );
      expect(calls.single.method, 'speech.prepareTopicAssets');
      expect(calls.single.arguments, {'locale': 'en-US'});
    },
  );

  TestWidgetsFlutterBinding.ensureInitialized();

  group('ML Kit offline Vietnamese-English translator', () {
    test('downloads Vietnamese over Wi-Fi and translates to English', () async {
      final adapter = _FakeTranslationAdapter();
      final translator = MlKitOfflineVietnameseEnglishTranslator(
        adapter: adapter,
        enabled: true,
      );

      expect(await translator.modelsReady(), isFalse);
      expect(await translator.downloadModels(), isTrue);
      expect(adapter.downloads, <String>['vi:wifi']);
      expect(
        await translator.translate('Con muốn uống nước'),
        'Can I have some water?',
      );
      expect(adapter.translatedTexts, <String>['Con muốn uống nước']);

      await translator.close();
      expect(adapter.closed, isTrue);
    });

    test('does not download an already installed model', () async {
      final adapter = _FakeTranslationAdapter(installed: <String>{'vi'});
      final translator = MlKitOfflineVietnameseEnglishTranslator(
        adapter: adapter,
        enabled: true,
      );

      expect(await translator.downloadModels(), isTrue);
      expect(adapter.downloads, isEmpty);
    });

    test('rejects translation while a language model is missing', () async {
      final translator = MlKitOfflineVietnameseEnglishTranslator(
        adapter: _FakeTranslationAdapter(),
        enabled: true,
      );

      await expectLater(
        translator.translate('Xin chào'),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'OFFLINE_TRANSLATION_MODEL_UNAVAILABLE',
          ),
        ),
      );
    });

    test('prepares all five offline outputs with one operation', () async {
      final adapter = _FakeTranslationAdapter(installed: <String>{'vi', 'ja'});
      final translator = MlKitOfflineVietnameseEnglishTranslator(
        adapter: adapter,
        enabled: true,
      );

      expect(await translator.downloadAllModels(), isTrue);
      expect(
        adapter.downloads,
        unorderedEquals(<String>['zh:wifi', 'ko:wifi', 'fr:wifi']),
      );
      for (final language in TranslationOutputLanguage.values) {
        expect(await translator.modelsReadyFor(language), isTrue);
      }
      expect(
        await translator.translateTo(
          'Xin chào',
          TranslationOutputLanguage.korean,
        ),
        'ko:Xin chào',
      );
      await translator.close();
    });

    test(
      'a missing target pack does not claim that language is ready',
      () async {
        final adapter = _FakeTranslationAdapter(
          installed: <String>{'vi', 'zh'},
        );
        final translator = MlKitOfflineVietnameseEnglishTranslator(
          adapter: adapter,
          enabled: true,
        );
        expect(
          await translator.modelsReadyFor(TranslationOutputLanguage.chinese),
          isTrue,
        );
        expect(
          await translator.modelsReadyFor(TranslationOutputLanguage.french),
          isFalse,
        );
        await expectLater(
          translator.translateTo('Xin chào', TranslationOutputLanguage.french),
          throwsA(
            isA<PlatformException>().having(
              (error) => error.code,
              'code',
              'OFFLINE_TRANSLATION_MODEL_UNAVAILABLE',
            ),
          ),
        );
        await translator.close();
      },
    );
  });

  test(
    'Android Vosk recognizer sends WAV and vi-VN to native bridge',
    () async {
      const channel = MethodChannel('test_homi_offline_speech');
      MethodCall? received;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            received = call;
            return <String, dynamic>{
              'text': 'con muốn uống nước',
              'alternatives': <String>['con muốn dùng nước'],
              'confidence': 0.91,
            };
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final transcript =
          await const AndroidVoskVietnameseSpeechRecognizer(
            channel: channel,
          ).recognize(
            const AudioCapture(
              filePath: r'C:\recordings\turn.wav',
              mimeType: 'audio/wav',
              duration: Duration(seconds: 2),
              inputLabel: 'Mic điện thoại',
              isBluetoothInput: false,
              initialNoiseRms: null,
            ),
          );

      expect(received?.method, 'recognizeFile');
      expect(
        received?.arguments,
        containsPair('filePath', r'C:\recordings\turn.wav'),
      );
      expect(received?.arguments, containsPair('locale', 'vi-VN'));
      expect(transcript.text, 'con muốn uống nước');
      expect(transcript.alternatives, <String>['con muốn dùng nước']);
    },
  );

  test('iOS downloads the same translation packs over Wi-Fi', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final adapter = _FakeTranslationAdapter();
    final translator = MlKitOfflineVietnameseEnglishTranslator(
      adapter: adapter,
    );
    expect(await translator.modelsReady(), isFalse);
    expect(await translator.downloadModels(), isTrue);
    expect(adapter.downloads, <String>['vi:wifi']);
    expect(
      await translator.translate('Con muốn uống nước'),
      'Can I have some water?',
    );
    await translator.close();
  });

  test('iOS queues all five packs before the first one finishes', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final gate = Completer<void>();
    final adapter = _FakeTranslationAdapter(vietnameseDownloadGate: gate);
    final translator = MlKitOfflineVietnameseEnglishTranslator(
      adapter: adapter,
    );
    final pending = translator.downloadAllModels();
    await Future<void>.delayed(Duration.zero);
    expect(
      adapter.downloads,
      unorderedEquals(<String>[
        'vi:wifi',
        'zh:wifi',
        'ja:wifi',
        'ko:wifi',
        'fr:wifi',
      ]),
    );
    gate.complete();
    expect(await pending, isTrue);
    await translator.close();
  });

  test('iOS routes English, Japanese and reverse translation to native packs', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const channel = MethodChannel('google_mlkit_on_device_translator');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'nlp#manageLanguageModelModels') return true;
          if (call.method == 'nlp#startLanguageTranslator') {
            if ((call.arguments as Map)['target'] == 'ja') return '水が飲みたいです。';
            return (call.arguments as Map)['source'] == 'en'
                ? 'Con muốn uống nước'
                : 'Can I have some water?';
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final forward = MlKitOfflineVietnameseEnglishTranslator();
    final reverse = MlKitOfflineEnglishVietnameseTranslator();
    expect(
      await forward.translate('Con muốn uống nước'),
      'Can I have some water?',
    );
    expect(
      await reverse.translate('Can I have some water?'),
      'Con muốn uống nước',
    );
    expect(
      await forward.translateTo(
        'Con muốn uống nước',
        TranslationOutputLanguage.japanese,
      ),
      '水が飲みたいです。',
    );
    final translationCalls = calls
        .where((call) => call.method == 'nlp#startLanguageTranslator')
        .toList();
    expect(translationCalls[0].arguments, containsPair('source', 'vi'));
    expect(translationCalls[0].arguments, containsPair('target', 'en'));
    expect(translationCalls[1].arguments, containsPair('source', 'en'));
    expect(translationCalls[1].arguments, containsPair('target', 'vi'));
    expect(translationCalls[2].arguments, containsPair('source', 'vi'));
    expect(translationCalls[2].arguments, containsPair('target', 'ja'));
    expect(
      calls.where(
        (call) =>
            call.method == 'nlp#manageLanguageModelModels' &&
            (call.arguments as Map)['task'] == 'download',
      ),
      isEmpty,
    );
    await forward.close();
    await reverse.close();
  });

  test(
    'unavailable iOS simulator cannot claim offline translation ready',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const channel = MethodChannel('google_mlkit_on_device_translator');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'nlp#closeLanguageTranslator') return null;
            if ((call.arguments as Map)['task'] == 'check') return false;
            throw PlatformException(
              code: 'OFFLINE_TRANSLATION_SIMULATOR_UNAVAILABLE',
            );
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final translator = MlKitOfflineVietnameseEnglishTranslator();
      expect(await translator.modelsReady(), isFalse);
      expect(await translator.downloadModels(), isFalse);
      await expectLater(
        translator.translate('Xin chào'),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'OFFLINE_TRANSLATION_MODEL_UNAVAILABLE',
          ),
        ),
      );
      await translator.close();
    },
  );

  test('desktop does not start translation model downloads', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final adapter = _FakeTranslationAdapter();
    final translator = MlKitOfflineVietnameseEnglishTranslator(
      adapter: adapter,
    );
    expect(await translator.modelsReady(), isFalse);
    expect(await translator.downloadModels(), isFalse);
    expect(adapter.downloads, isEmpty);
    await translator.close();
  });

  test(
    'Apple speech assets are prepared without requesting recognition access',
    () async {
      const channel = MethodChannel('test_apple_speech_assets');
      MethodCall? received;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            received = call;
            return 'installed';
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      expect(
        await const AppleOfflineSpeechAssetService(
          channel: channel,
        ).prepareBackgroundLocale('vi-VN'),
        'installed',
      );
      expect(received?.method, 'speech.prepareBackgroundAssets');
      expect(received?.arguments, containsPair('locale', 'vi-VN'));
    },
  );
}

class _FakeTranslationAdapter
    implements OfflineTranslationAdapter, OfflineTargetTranslationAdapter {
  _FakeTranslationAdapter({Set<String>? installed, this.vietnameseDownloadGate})
    : installed = installed ?? <String>{};

  final Set<String> installed;
  final Completer<void>? vietnameseDownloadGate;
  final List<String> downloads = <String>[];
  final List<String> translatedTexts = <String>[];
  bool closed = false;

  @override
  Future<bool> isModelDownloaded(String languageCode) async =>
      installed.contains(languageCode);

  @override
  Future<bool> downloadModel(
    String languageCode, {
    required bool wifiOnly,
  }) async {
    if (installed.contains(languageCode)) return true;
    downloads.add('$languageCode:${wifiOnly ? 'wifi' : 'any'}');
    if (languageCode == 'vi') await vietnameseDownloadGate?.future;
    installed.add(languageCode);
    return true;
  }

  @override
  Future<String> translate(String text) async {
    translatedTexts.add(text);
    return 'Can I have some water?';
  }

  @override
  Future<String> translateTo(
    String text,
    TranslationOutputLanguage language,
  ) async {
    translatedTexts.add(text);
    return '${language.apiValue}:$text';
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}
