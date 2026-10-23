import 'dart:async';
import 'dart:io';

import 'package:ai_speaking_flutter_app/app/ai_speaking_app.dart';
import 'package:ai_speaking_flutter_app/features/home/presentation/home_learning_shell.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/android_offline_speech_model_service.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/topic_listening_screen.dart';
import 'package:ai_speaking_flutter_app/features/onboarding/presentation/startup_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final ios = TargetPlatformVariant.only(TargetPlatform.iOS);

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
    'iOS cold start respects persisted opt-out and resume rechecks changed choice',
    (tester) async {
      final native = await _launch(
        tester,
        consent: AndroidOfflineSpeechModelConsent.declined,
      );
      expect(find.byType(HomeLearningShell), findsOneWidget);
      await native.resume();
      await tester.pump(const Duration(seconds: 31));
      expect(native.topicCalls, isEmpty);
      // Persisted choice changes through the same store Settings uses.
      await const SharedPreferencesAndroidOfflineSpeechModelConsentStore()
          .write(AndroidOfflineSpeechModelConsent.undecided);
      await native.resume();
      expect(native.topicCalls, hasLength(1));
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
    'iOS explicit opt-out stops deferred checks and app disposal stops retries',
    (tester) async {
      final native = await _launch(tester, prepare: () async => 'pending');
      expect(native.topicCalls, hasLength(1));
      await const SharedPreferencesAndroidOfflineSpeechModelConsentStore()
          .write(AndroidOfflineSpeechModelConsent.declined);
      await tester.pump(const Duration(seconds: 65));
      expect(native.topicCalls, hasLength(1));
      await const SharedPreferencesAndroidOfflineSpeechModelConsentStore()
          .write(AndroidOfflineSpeechModelConsent.undecided);
      await native.resume();
      expect(native.topicCalls, hasLength(2));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 65));
      expect(native.topicCalls, hasLength(2));
      await native.close();
    },
    variant: ios,
  );
}

Future<_NativeAssets> _launch(
  WidgetTester tester, {
  bool setupComplete = true,
  AndroidOfflineSpeechModelConsent consent =
      AndroidOfflineSpeechModelConsent.undecided,
  Future<String> Function()? prepare,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({
    'innotrik.child-age.v1': 6,
    if (setupComplete) 'homi.parent-setup.version': 1,
    'innotrik.user-onboarding.version': 1,
    'homi.parental-privacy-consent.version': 3,
    // Default local test builds lack production privacy URLs. The existing
    // browse-only mode still opens Home; production defines use the grant above.
    'homi.parental-privacy-consent.limited-mode': true,
    'homi.offline-language-packs-consent.v2': consent.name,
  });
  final native = _NativeAssets(tester, prepare ?? () async => 'installed');
  native.install();
  addTearDown(native.close);
  await tester.pumpWidget(const AiSpeakingApp());
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
  final translationDownloads = <MethodCall>[];
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
            if (call.arguments is Map &&
                (call.arguments as Map)['task'] == 'download') {
              translationDownloads.add(call);
            }
            return false;
          }
          if (call.method == 'speech.prepareTopicAssets') {
            topicCalls.add(call);
            return prepare();
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
