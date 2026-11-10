import 'dart:async';
import 'dart:io';

import 'package:ai_speaking_flutter_app/app/ai_speaking_app.dart';
import 'package:ai_speaking_flutter_app/config/app_config.dart';
import 'package:ai_speaking_flutter_app/core/audio/catalog/listening_audio_prefetcher.dart';
import 'package:ai_speaking_flutter_app/features/home/presentation/home_learning_shell.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/android_offline_speech_model_service.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/topic_listening_screen.dart';
import 'package:ai_speaking_flutter_app/features/onboarding/presentation/startup_setup_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final ios = TargetPlatformVariant.only(TargetPlatform.iOS);

  testWidgets(
    'completed setup starts age audio prefetch on Android only',
    (tester) async {
      var wifiChecks = 0;
      final prefetcher = ListeningAudioPrefetcher(
        wifiAvailable: () async {
          wifiChecks += 1;
          return false;
        },
        wifiChanges: () => const Stream<bool>.empty(),
      );
      final native = await _launch(
        tester,
        fullConsent: true,
        listeningAudioPrefetcher: prefetcher,
      );
      expect(
        wifiChecks,
        defaultTargetPlatform == TargetPlatform.android ? 1 : 0,
      );
      await native.close();
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets(
    'step 1 consent starts offline translation while setup remains open',
    (tester) async {
      final native = await _launch(
        tester,
        setupComplete: false,
        fullConsent: true,
        storedConsent: false,
      );
      expect(find.byType(StartupSetupScreen), findsOneWidget);
      expect(native.translationScheduleCalls, isEmpty);
      expect(native.translationDownloads, isEmpty);

      await tester.tap(find.byKey(const Key('startup-confirm-adult-role')));
      await tester.pump();
      await _completeLegalReview(tester);
      final consentButton = find.byKey(
        const Key('startup-grant-privacy-consent'),
      );
      await tester.ensureVisible(consentButton);
      await tester.tap(consentButton);
      await tester.pumpAndSettle();

      expect(find.byType(StartupSetupScreen), findsOneWidget);
      expect(find.text('Bé đang ở độ tuổi nào?'), findsOneWidget);
      if (defaultTargetPlatform == TargetPlatform.android) {
        expect(native.translationScheduleCalls, hasLength(1));
        expect(native.modelRequestCalls, hasLength(1));
      } else {
        expect(
          native.translationDownloads.map(
            (call) => (call.arguments as Map)['model'],
          ),
          unorderedEquals(<String>['vi', 'zh', 'ja', 'ko', 'fr']),
        );
        expect(native.backgroundSpeechCalls, isEmpty);
      }
      await native.close();
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets(
    'unfinished setup resumes offline translation after prior consent',
    (tester) async {
      final native = await _launch(
        tester,
        setupComplete: false,
        fullConsent: true,
      );
      expect(find.byType(StartupSetupScreen), findsOneWidget);
      if (defaultTargetPlatform == TargetPlatform.android) {
        expect(native.translationScheduleCalls, hasLength(1));
      } else {
        expect(native.translationDownloads, hasLength(5));
        expect(native.backgroundSpeechCalls, isEmpty);
      }
      await native.close();
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets(
    'old consent reopens setup and blocks offline work until renewed',
    (tester) async {
      final native = await _launch(
        tester,
        fullConsent: true,
        storedConsentVersion: 3,
      );
      expect(find.byType(StartupSetupScreen), findsOneWidget);
      expect(find.byType(HomeLearningShell), findsNothing);
      expect(native.translationScheduleCalls, isEmpty);
      expect(native.translationDownloads, isEmpty);

      await tester.tap(find.byKey(const Key('startup-confirm-adult-role')));
      await tester.pump();
      await _completeLegalReview(tester);
      await tester.tap(find.byKey(const Key('startup-grant-privacy-consent')));
      await tester.pumpAndSettle();

      if (defaultTargetPlatform == TargetPlatform.android) {
        expect(native.translationScheduleCalls, hasLength(1));
      } else {
        expect(native.translationDownloads, hasLength(5));
      }
      await native.close();
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets(
    'limited mode does not start offline translation',
    (tester) async {
      final native = await _launch(tester, setupComplete: false);
      expect(find.byType(StartupSetupScreen), findsOneWidget);
      expect(native.translationScheduleCalls, isEmpty);
      expect(native.translationDownloads, isEmpty);
      await native.close();
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets(
    'Android limited mode after step 1 cancels queued translation',
    (tester) async {
      final native = await _launch(
        tester,
        setupComplete: false,
        fullConsent: true,
        storedConsent: false,
      );
      await tester.tap(find.byKey(const Key('startup-confirm-adult-role')));
      await tester.pump();
      await _completeLegalReview(tester);
      await tester.tap(find.byKey(const Key('startup-grant-privacy-consent')));
      await tester.pumpAndSettle();
      expect(native.translationScheduleCalls, hasLength(1));

      await tester.tap(find.byKey(const ValueKey('startup-age-8-10')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('startup-next')));
      await tester.pumpAndSettle();
      final limited = find.byKey(
        const Key('startup-continue-without-voice-after-consent'),
      );
      await tester.ensureVisible(limited);
      await tester.tap(limited);
      await tester.pumpAndSettle();
      expect(native.translationCancelCalls, hasLength(1));
      await tester.pump(const Duration(seconds: 35));
      expect(native.translationScheduleCalls, hasLength(1));
      await native.close();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets('iOS limited Home status does not prepare speech assets', (
    tester,
  ) async {
    final native = await _launch(tester);
    final home = tester.widget<HomeLearningShell>(
      find.byType(HomeLearningShell),
    );
    expect(await home.offlineLanguageReady!(), isFalse);
    expect(native.backgroundSpeechCalls, isEmpty);
    await native.close();
  }, variant: ios);

  testWidgets('iOS does not prepare Topic assets before onboarding completes', (
    tester,
  ) async {
    final native = await _launch(tester, setupComplete: false);
    expect(find.byType(StartupSetupScreen), findsOneWidget);
    await tester.pump(const Duration(seconds: 35));
    await native.resume();
    expect(native.topicCalls, isEmpty);
    expect(find.byType(HomeLearningShell), findsNothing);
    await native.close();
  }, variant: ios);

  testWidgets(
    'iOS completed setup starts Vietnamese speech and translation downloads despite an old opt-out',
    (tester) async {
      final native = await _launch(
        tester,
        consent: AndroidOfflineSpeechModelConsent.declined,
        fullConsent: true,
      );
      expect(
        native.backgroundSpeechCalls.single.arguments,
        containsPair('locale', 'vi-VN'),
      );
      expect(
        native.backgroundSpeechCalls.single.method,
        'speech.prepareBackgroundAssets',
      );
      expect(
        native.translationDownloads.map(
          (call) => (call.arguments as Map)['model'],
        ),
        unorderedEquals(<String>['vi', 'zh', 'ja', 'ko', 'fr']),
      );
      expect(
        native.translationDownloads.every(
          (call) => (call.arguments as Map)['wifi'] == true,
        ),
        isTrue,
      );
      expect(native.topicCalls, hasLength(1));
      await native.close();
    },
    variant: ios,
  );

  testWidgets(
    'iOS Home stays interactive during installation and Topic has no download UI',
    (tester) async {
      final installing = Completer<String>();
      final native = await _launch(tester, prepare: () => installing.future);
      expect(find.byType(HomeLearningShell), findsOneWidget);
      expect(native.topicCalls, hasLength(1));
      expect(native.topicCalls.single.arguments, {'locale': 'en-US'});
      await native.openTopics();
      expect(find.byType(TopicListeningScreen), findsOneWidget);
      expect(find.textContaining('Tải model'), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      await native.resume();
      await tester.pump(const Duration(seconds: 35));
      expect(native.topicCalls, hasLength(1));
      installing.complete('installed');
      await tester.pump();
      await tester.pump(const Duration(seconds: 35));
      expect(native.topicCalls, hasLength(1));
      expect(find.byType(TopicListeningScreen), findsOneWidget);
      expect(native.translationDownloads, isEmpty);
      expect(
        await const SharedPreferencesAndroidOfflineSpeechModelConsentStore()
            .read(),
        AndroidOfflineSpeechModelConsent.undecided,
      );
      await native.close();
    },
    variant: ios,
  );

  testWidgets(
    'iOS Wi-Fi recovery prepares assets while user remains in Topic',
    (tester) async {
      var wifi = false;
      final native = await _launch(
        tester,
        prepare: () async => wifi ? 'installed' : 'waitingForWifi',
      );
      await native.openTopics();
      final before = native.topicCalls.length;
      wifi = true;
      await tester.pump(const Duration(seconds: 31));
      expect(native.topicCalls.length, before + 1);
      expect(find.byType(TopicListeningScreen), findsOneWidget);
      await tester.pump(const Duration(seconds: 31));
      expect(native.topicCalls.length, before + 1);
      expect(native.translationDownloads, isEmpty);
      await native.close();
    },
    variant: ios,
  );

  testWidgets(
    'iOS cold start ignores the removed opt-out and rechecks on resume',
    (tester) async {
      final native = await _launch(
        tester,
        consent: AndroidOfflineSpeechModelConsent.declined,
      );
      expect(find.byType(HomeLearningShell), findsOneWidget);
      expect(native.topicCalls, hasLength(1));
      await native.resume();
      await tester.pump(const Duration(seconds: 31));
      expect(native.topicCalls, hasLength(2));
      expect(native.translationDownloads, isEmpty);
      await native.close();
    },
    variant: ios,
  );

  testWidgets(
    'iOS transient native failure recovers on resume without replacing current page',
    (tester) async {
      var failed = true;
      final native = await _launch(
        tester,
        prepare: () async {
          if (failed) {
            throw PlatformException(code: 'ASSET_TEMPORARILY_UNAVAILABLE');
          }
          return 'installed';
        },
      );
      await native.openTopics();
      failed = false;
      await native.resume();
      expect(native.topicCalls, hasLength(2));
      expect(find.byType(TopicListeningScreen), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
      await native.close();
    },
    variant: ios,
  );

  testWidgets(
    'iOS legacy opt-out does not stop deferred checks; disposal stops retries',
    (tester) async {
      final native = await _launch(
        tester,
        consent: AndroidOfflineSpeechModelConsent.declined,
        prepare: () async => 'pending',
      );
      expect(native.topicCalls, hasLength(1));
      await tester.pump(const Duration(seconds: 65));
      expect(native.topicCalls, hasLength(3));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 65));
      expect(native.topicCalls, hasLength(3));
      await native.close();
    },
    variant: ios,
  );
}

Future<_NativeAssets> _launch(
  WidgetTester tester, {
  bool setupComplete = true,
  bool fullConsent = false,
  bool storedConsent = true,
  int storedConsentVersion = 4,
  AndroidOfflineSpeechModelConsent consent =
      AndroidOfflineSpeechModelConsent.undecided,
  Future<String> Function()? prepare,
  ListeningAudioPrefetcher? listeningAudioPrefetcher,
}) async {
  tester.view.physicalSize = const Size(430, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({
    'innotrik.child-age.v1': 6,
    if (setupComplete) 'homi.parent-setup.version': 1,
    'innotrik.user-onboarding.version': 1,
    if (storedConsent)
      'homi.parental-privacy-consent.version': storedConsentVersion,
    // Most cases use browse-only mode; the automatic-download case supplies
    // complete privacy configuration below.
    'homi.parental-privacy-consent.limited-mode': storedConsent && !fullConsent,
    'homi.offline-language-packs-consent.v2': consent.name,
  });
  final native = _NativeAssets(tester, prepare ?? () async => 'installed');
  native.install();
  addTearDown(native.close);
  await tester.pumpWidget(
    AiSpeakingApp(
      listeningAudioPrefetcher: listeningAudioPrefetcher,
      config: fullConsent
          ? AppConfig(
              backendBaseUri: Uri.parse('https://example.com'),
              useDemoBackend: true,
              childAge: 6,
              privacyPolicyUri: Uri.parse('https://example.com/privacy'),
              termsUri: Uri.parse('https://example.com/terms'),
              supportUri: Uri.parse('https://example.com/support'),
              aiSubprocessors: 'HOMI backend',
              dataRetentionSummary: 'Audio được xóa sau 24 giờ.',
            )
          : null,
    ),
  );
  await tester.pumpAndSettle();
  return native;
}

/// Mock only platform boundaries: app lifecycle, Home callback, navigation,
/// SharedPreferences and the preparation service are production implementations.
class _NativeAssets {
  _NativeAssets(this.tester, this.prepare);
  final WidgetTester tester;
  final Future<String> Function() prepare;
  final topicCalls = <MethodCall>[];
  final backgroundSpeechCalls = <MethodCall>[];
  final translationDownloads = <MethodCall>[];
  final translationScheduleCalls = <MethodCall>[];
  final translationCancelCalls = <MethodCall>[];
  final modelRequestCalls = <MethodCall>[];
  final installedTranslationModels = <String>{};
  final directory = Directory.systemTemp.createTempSync('homi-topic-app-');
  static const channels = [
    'ailingo_aiv0_ble_control',
    'ailingo_aiv0_ble_control/events',
    'ailingo_hfp_audio',
    'ailingo_hfp_audio/events',
    'ailingo_background_learning',
    'ailingo_background_learning/events',
    'dexterous.com/flutter/local_notifications',
    'ailingo_speech',
    'ailingo_speech/events',
    'ailingo_voice_prompt',
    'ailingo_offline_intent',
    'com.llfbandit.record/messages',
    'com.ryanheise.audio_session',
    'plugins.flutter.io/path_provider',
    'google_mlkit_on_device_translator',
    'homi_offline_speech',
  ];
  void install() {
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    for (final name in channels) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel(name),
        (call) async {
          if (name == 'plugins.flutter.io/path_provider') return directory.path;
          if (name == 'dexterous.com/flutter/local_notifications') {
            return call.method == 'show' ? null : true;
          }
          if (name == 'google_mlkit_on_device_translator') {
            final args = call.arguments is Map ? call.arguments as Map : null;
            if (args?['task'] == 'download') {
              translationDownloads.add(call);
              installedTranslationModels.add(args!['model'] as String);
              return 'success';
            }
            if (args?['task'] == 'check') {
              return installedTranslationModels.contains(args!['model']);
            }
            return null;
          }
          if (name == 'homi_offline_speech') {
            if (call.method == 'translation.scheduleDownload') {
              translationScheduleCalls.add(call);
              return true;
            }
            if (call.method == 'translation.cancelDownload') {
              translationCancelCalls.add(call);
              return true;
            }
            if (call.method == 'model.status') {
              return <String, Object?>{'state': 'not_installed'};
            }
            if (call.method == 'model.requestDownload') {
              modelRequestCalls.add(call);
              return <String, Object?>{'state': 'requested'};
            }
            if (call.method == 'model.cancelDownload') return null;
          }
          if (call.method == 'speech.prepareTopicAssets') {
            topicCalls.add(call);
            return prepare();
          }
          if (call.method == 'speech.prepareBackgroundAssets') {
            backgroundSpeechCalls.add(call);
            return 'installed';
          }
          if (call.method == 'speech.prepareLocale') {
            throw StateError(
              'Automatic preparation must not request Speech permission',
            );
          }
          return switch (call.method) {
            'initialize' ||
            'cancelConnectionAttempt' => <String, Object?>{'phase': 'idle'},
            'bluetoothAdapterState' => 'poweredOn',
            'findDevices' || 'scan' => <Object?>[],
            'requestPermissions' ||
            'hasPermissions' ||
            'hasPermission' ||
            'requestNotificationPermission' => true,
            _ => null,
          };
        },
      );
    }
  }

  Future<void> resume() async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
  }

  Future<void> openTopics() async {
    await tester.tap(find.byKey(const Key('topic-listening-edge-tab')));
    await tester.pumpAndSettle();
  }

  bool _closed = false;
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 15));
    for (final name in channels) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel(name),
        null,
      );
    }
    directory.deleteSync(recursive: true);
  }
}

Future<void> _completeLegalReview(WidgetTester tester) async {
  final review = find.byKey(const Key('startup-review-legal'));
  await tester.ensureVisible(review);
  await tester.tap(review);
  await tester.pumpAndSettle();

  final reviewed = find.byKey(const Key('startup-legal-reviewed'));
  for (var attempt = 0; attempt < 6; attempt += 1) {
    if (tester.widget<FilledButton>(reviewed).onPressed != null) break;
    await tester.drag(
      find.byKey(const Key('startup-legal-scroll')),
      const Offset(0, -480),
    );
    await tester.pumpAndSettle();
  }
  expect(tester.widget<FilledButton>(reviewed).onPressed, isNotNull);
  await tester.tap(reviewed);
  await tester.pumpAndSettle();
}
