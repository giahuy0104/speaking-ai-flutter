import 'dart:async';
import 'dart:io';
import 'package:ai_speaking_flutter_app/app/ai_speaking_app.dart';
import 'package:ai_speaking_flutter_app/core/audio/hfp_audio_control.dart';
import 'package:ai_speaking_flutter_app/core/device/aivo_control_dispatcher.dart';
import 'package:ai_speaking_flutter_app/features/conversation/presentation/conversation_controller.dart';
import 'package:ai_speaking_flutter_app/features/conversation/presentation/conversation_screen.dart';
import 'package:ai_speaking_flutter_app/features/home/presentation/home_learning_shell.dart';
import 'package:ai_speaking_flutter_app/features/onboarding/presentation/startup_setup_screen.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/presentation/main_voice_assistant_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const mic = HfpAudioDevice(
  id: 'AA:BB:CC:DD:EE:FF',
  name: 'HM-D001',
  isConnected: true,
);

void main() {
  testWidgets(
    'live BLE battery telemetry delivers deduplicated system reminders',
    (tester) async {
      final app = await _pumpApp(tester, grantPrivacy: true);
      await app.finishStartupScans();
      for (final percent in [20, 19, 19, 10, 9, 9, 5, 4, 4]) {
        await app.emitBle('connected', batteryPercent: percent);
      }
      expect(
        app.nativeCalls.where(
          (call) => call == 'dexterous.com/flutter/local_notifications.show',
        ),
        hasLength(3),
      );
      expect(
        app.nativeCalls.where(
          (call) =>
              call ==
              'dexterous.com/flutter/local_notifications.requestNotificationsPermission',
        ),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await app.close();
    },
    variant: TargetPlatformVariant({TargetPlatform.android}),
  );

  testWidgets(
    'floating MAIN has an Overlay on child routes and survives app rebuilds',
    (tester) async {
      final app = await _pumpApp(tester, grantPrivacy: true);
      await app.finishStartupScans();
      final shell = tester.widget<HomeLearningShell>(
        find.byType(HomeLearningShell),
      );
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      final main = find.byType(MainVoiceAssistantButton);
      expect(main, findsNothing);
      void pushPage() => unawaited(
        navigator.push<void>(
          MaterialPageRoute<void>(
            builder: (_) =>
                const Scaffold(body: Text('MAIN overlay regression route')),
          ),
        ),
      );
      pushPage();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(main, findsOneWidget);
      expect(Overlay.maybeOf(tester.element(main)), isNotNull);
      final tooltip = find.descendant(of: main, matching: find.byType(Tooltip));
      expect(
        tester.state<TooltipState>(tooltip).ensureTooltipVisible(),
        isTrue,
      );
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('Chế độ tiêu chuẩn: Main'), findsOneWidget);
      expect(tester.takeException(), isNull);

      shell.onThemeModeChanged!(ThemeMode.dark);
      await tester.pumpAndSettle();
      expect(
        tester.state<NavigatorState>(find.byType(Navigator).first),
        same(navigator),
      );
      expect(Theme.of(tester.element(main)).brightness, Brightness.dark);
      expect(find.text('MAIN overlay regression route'), findsOneWidget);
      navigator.pop();
      await tester.pumpAndSettle();
      expect(main, findsNothing);
      expect(find.text('Chế độ tiêu chuẩn: Main'), findsNothing);
      pushPage();
      await tester.pumpAndSettle();
      expect(main, findsOneWidget);
      expect(tester.takeException(), isNull);
      navigator.pop();
      await tester.pumpAndSettle();
      await app.close();
    },
    variant: TargetPlatformVariant({TargetPlatform.android}),
  );

  testWidgets(
    'reenabling voice from limited mode completes permission refresh before Home',
    (tester) async {
      final app = await _pumpApp(tester);
      var shell = tester.widget<HomeLearningShell>(
        find.byType(HomeLearningShell),
      );
      expect(shell.voiceAccessEnabled, isFalse);
      shell.onManagePrivacyConsent!();
      await _pumpAsync(tester);
      var setup = tester.widget<StartupSetupScreen>(
        find.byType(StartupSetupScreen),
      );
      expect(setup.privacyConfigurationComplete, isTrue);
      // Exercise the real callbacks exposed by Settings and the parent wizard.
      // Native permission mocks return granted, matching the reported phone.
      await setup.onGrantPrivacyConsent();
      await _pumpAsync(tester);
      expect(find.byType(StartupSetupScreen), findsOneWidget);
      expect(find.byType(HomeLearningShell), findsNothing);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getInt('homi.parent-setup.version'), isNull);
      setup = tester.widget<StartupSetupScreen>(
        find.byType(StartupSetupScreen),
      );
      setup.onRetryPermissions();
      await _pumpAsync(tester);
      await app.finishStartupScans();
      await app.emitBle('connected');
      await app.controller.connectHfpDevice(mic);
      await _pumpAsync(tester);
      setup = tester.widget<StartupSetupScreen>(
        find.byType(StartupSetupScreen),
      );
      expect(setup.microphoneGranted, isTrue);
      expect(setup.bluetoothGranted, isTrue);
      expect(setup.h20BleConnected, isTrue);
      expect(setup.h20HfpConfigured, isTrue);
      await setup.onCompleteSetup();
      await _pumpAsync(tester);
      shell = tester.widget<HomeLearningShell>(find.byType(HomeLearningShell));
      expect(shell.privacyConsentGranted, isTrue);
      expect(shell.voiceAccessEnabled, isTrue);
      expect(shell.onScreenMainPressed, isNotNull);
      expect(preferences.getInt('homi.parental-privacy-consent.version'), 3);
      expect(
        preferences.getBool('homi.parental-privacy-consent.limited-mode'),
        isNull,
      );
      expect(preferences.getInt('homi.parent-setup.version'), 1);
      await app.close();
    },
    variant: TargetPlatformVariant({TargetPlatform.android}),
  );

  testWidgets(
    'reported MAIN packet reaches Dart but limited mode blocks voice before HFP',
    (tester) async {
      final app = await _pumpApp(tester);
      await app.emitBle('connected');
      await app.controller.connectHfpDevice(mic);
      expect(app.controller.isH20Ready, isTrue);
      final shell = tester.widget<HomeLearningShell>(
        find.byType(HomeLearningShell),
      );
      expect(shell.privacyConsentGranted, isFalse);
      expect(shell.voiceAccessEnabled, isFalse);
      final messages = <String>[];
      final previousPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) {
        if (message != null) messages.add(message);
      };
      app.speechCalls.clear();
      app.hfpCalls.clear();
      try {
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          'ailingo_aiv0_ble_control/events',
          const StandardMethodCodec().encodeSuccessEnvelope(<String, Object?>{
            'type': 'button',
            'deviceId': mic.id,
            'bytes': <int>[1, 1, 1, 0, 10, 0, 42, 0, 244, 215, 21, 0],
            'duplicate': false,
          }),
          (_) {},
        );
        await _pumpAsync(tester);
      } finally {
        debugPrint = previousPrint;
      }
      final controls = tester
          .widget<AivoControlScope>(find.byType(AivoControlScope))
          .notifier!;
      expect(controls.history.first.status, AivoControlStatus.unavailable);
      expect(controls.history.first.input.sequence, 10);
      expect(controls.history.first.input.actionable, isTrue);
      expect(controls.history.first.input.duplicate, isFalse);
      expect(controls.history.first.input.protocol, 'observedHmD001');
      expect(messages, contains(contains('reason=parental_consent_missing')));
      expect(messages, contains(contains('result=unavailable')));
      expect(messages, contains('H20 MAIN: main • ignored'));
      expect(app.speechCalls.where((c) => c.method == 'speech.start'), isEmpty);
      expect(app.hfpCalls.where((c) => c.method == 'startAudioRoute'), isEmpty);
      await app.close();
    },
    variant: TargetPlatformVariant({TargetPlatform.android}),
  );

  testWidgets(
    'BLE-only recovery runs during recording at the unchanged 15s/60s cadence',
    (tester) async {
      final app = await _pumpApp(tester, grantPrivacy: true);
      for (final scan in app.scans) {
        if (!scan.isCompleted) scan.complete([]);
      }
      await _pumpAsync(tester);
      await app.emitBle('connected');
      expect((await app.controller.connectHfpDevice(mic)).succeeded, isTrue);
      expect(app.controller.isH20Ready, isTrue);
      // The initial connection round already elapsed. Keep the domain clock
      // deterministic while the existing Timer.periodic remains real Dart code.
      app.now = app.now.add(const Duration(seconds: 75));
      await app.emitBle('error');
      expect(app.controller.isHomiAudioReady, isTrue);
      final scansBefore = app.scans.length;
      app.bleCalls.clear();
      await app.advance(const Duration(seconds: 10));
      await app.startRecording();
      final hfpBefore = app.hfpCalls.length;
      await app.advance(const Duration(seconds: 4));
      expect(app.bleCalls.where((c) => c.method == 'connect'), isEmpty);
      await app.advance(const Duration(seconds: 1));
      expect(app.bleCalls.where((c) => c.method == 'connect'), hasLength(1));
      expect(app.bleCalls.firstWhere((c) => c.method == 'connect').arguments, {
        'deviceId': mic.id,
      });
      expect(app.scans.length, scansBefore);
      expect(app.hfpCalls.length, hfpBefore);
      expect(
        app.controller.isRecording,
        isTrue,
        reason: '${app.controller.errorMessage}; methods=${app.nativeCalls}',
      );
      expect(
        find.byKey(const Key('device-connection-action-dialog')),
        findsNothing,
      );
      await app.drain(app.controller.cancelCurrentMainAction());
      // A recording has a separate 12s safety limit. Start the next genuine
      // capture just before the retry tick instead of forging a 75s recording.
      for (var i = 0; i < 3; i++) {
        await app.advance(const Duration(seconds: 15));
        expect(app.bleCalls.where((c) => c.method == 'connect'), hasLength(1));
      }
      await app.advance(const Duration(seconds: 10));
      await app.startRecording();
      final nextHfpBefore = app.hfpCalls.length;
      await app.advance(const Duration(seconds: 4));
      expect(app.bleCalls.where((c) => c.method == 'connect'), hasLength(1));
      await app.advance(const Duration(seconds: 1));
      expect(app.bleCalls.where((c) => c.method == 'connect'), hasLength(2));
      expect(app.controller.isRecording, isTrue);
      expect(app.hfpCalls.length, nextHfpBefore);
      expect(app.scans.length, scansBefore);
      await app.drain(app.controller.cancelCurrentMainAction());
      await app.close();
    },
    variant: TargetPlatformVariant({TargetPlatform.android}),
  );

  testWidgets(
    'Stop session after MAIN loss ends the session and cannot restart capture',
    (tester) async {
      final app = await _pumpApp(tester, grantPrivacy: true);
      for (final scan in app.scans) {
        if (!scan.isCompleted) scan.complete([]);
      }
      await _pumpAsync(tester);
      await app.emitBle('connected');
      await app.controller.connectHfpDevice(mic);
      tester
          .widget<HomeLearningShell>(find.byType(HomeLearningShell))
          .speakingSessionController!
          .enter();
      await app.startRecording();
      expect(
        app.controller.isRecording,
        isTrue,
        reason: '${app.controller.errorMessage}; methods=${app.nativeCalls}',
      );
      // The public session controller represents the continuous-session owner;
      // capture itself above is started through the actual native Dart adapter.
      final session = tester
          .widget<HomeLearningShell>(find.byType(HomeLearningShell))
          .speakingSessionController!;
      session.enter();
      await _pumpAsync(tester);
      await app.emitBle('error');
      final starts = app.speechCalls
          .where((c) => c.method == 'speech.start')
          .length;
      expect(starts, greaterThan(0));
      app.speechCancellation = Completer<void>();
      await tester.ensureVisible(find.text('Dừng phiên'));
      await tester.tap(find.text('Dừng phiên'));
      await _pumpAsync(tester);
      final stoppingShell = tester.widget<HomeLearningShell>(
        find.byType(HomeLearningShell),
      );
      expect(stoppingShell.isStoppingSession, isTrue);
      expect(session.isActive, isFalse);
      expect(
        app.speechCalls.where((c) => c.method == 'speech.cancel'),
        isNotEmpty,
      );
      await app.drain(stoppingShell.onScreenMainPressed!());
      await app.drain(stoppingShell.onMainSpeakingModeStarted!());
      expect(session.isActive, isFalse);
      expect(
        app.speechCalls.where((c) => c.method == 'speech.start'),
        hasLength(starts),
      );
      app.speechCancellation!.complete();
      await _pumpAsync(tester);
      await tester.pump(const Duration(seconds: 1));
      await _pumpAsync(tester);
      expect(session.isActive, isFalse);
      expect(app.controller.isRecording, isFalse);
      expect(app.controller.isContinuousHfpSessionActive, isFalse);
      await app.advance(const Duration(seconds: 30));
      expect(
        app.speechCalls.where((c) => c.method == 'speech.start'),
        hasLength(starts),
      );
      expect(
        find.byKey(const Key('device-connection-action-dialog')),
        findsNothing,
      );
      await app.close();
    },
    variant: TargetPlatformVariant({TargetPlatform.android}),
  );

  testWidgets(
    'failed BLE attempt for another device recovers only the verified HOMI',
    (tester) async {
      final app = await _pumpApp(tester, grantPrivacy: true);
      await app.finishStartupScans();
      await app.emitBle('connected');
      await app.controller.connectHfpDevice(mic);
      expect(app.controller.verifiedHomiBleDeviceId, mic.id);
      app.now = app.now.add(const Duration(seconds: 75));
      await app.emitBle('error', deviceId: '11:22:33:44:55:66');
      expect(app.controller.verifiedHomiBleDeviceId, mic.id);
      expect(app.controller.isHomiAudioReady, isTrue);
      final beforeHfp = app.hfpCalls.length;
      final beforeScans = app.scans.length;
      app.bleCalls.clear();
      await app.advance(const Duration(seconds: 15));
      final connects = app.bleCalls
          .where((call) => call.method == 'connect')
          .toList();
      expect(connects, hasLength(1));
      expect(connects.single.arguments, {'deviceId': mic.id});
      expect(app.hfpCalls.length, beforeHfp);
      expect(app.scans.length, beforeScans);
      await app.close();
    },
    variant: TargetPlatformVariant({TargetPlatform.android}),
  );

  testWidgets(
    'vocabulary follow-up keeps verified HFP after MAIN disconnects',
    (tester) async {
      final app = await _pumpApp(tester, grantPrivacy: true);
      await app.finishStartupScans();
      await app.emitBle('connected');
      await app.controller.connectHfpDevice(mic);
      await app.emitBle('error');
      expect(app.controller.isHomiAudioReady, isTrue);
      final shell = tester.widget<HomeLearningShell>(
        find.byType(HomeLearningShell),
      );
      final routeStarts = app.hfpCalls
          .where((call) => call.method == 'startAudioRoute')
          .length;
      await app.drain(shell.onVocabularyVoiceChoiceRequested!());
      final starts = app.speechCalls
          .where((call) => call.method == 'speech.start')
          .toList();
      expect(starts, isNotEmpty);
      // Android selects communication audio through HfpAudioBridge, not the
      // iOS-only speech audioSource override. Verify that route at speech.start.
      expect(app.speechRouteIds.last, mic.id);
      expect(
        app.hfpCalls.where((call) => call.method == 'startAudioRoute').length,
        greaterThan(routeStarts),
      );
      expect(starts.last.arguments, containsPair('commandMode', true));
      expect(app.controller.usesHfpInput, isTrue);
      expect(
        app.hfpCalls.where((call) => call.method == 'disconnect'),
        isEmpty,
      );
      expect(
        find.byKey(const Key('device-connection-action-dialog')),
        findsNothing,
      );
      await app.drain(shell.voiceNavigationController!.pause());
      await app.close();
    },
    variant: TargetPlatformVariant({TargetPlatform.android}),
  );
}

Future<void> _pumpAsync(WidgetTester tester) async {
  for (var i = 0; i < 8; i += 1) {
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  }
}

Future<_NativeAppHarness> _pumpApp(
  WidgetTester tester, {
  bool grantPrivacy = false,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues(<String, Object>{
    'innotrik.child-age.v1': 6,
    'homi.parent-setup.version': 1,
    'innotrik.user-onboarding.version': 1,
    if (grantPrivacy) 'homi.parental-privacy-consent.version': 3,
    if (!grantPrivacy) 'homi.parental-privacy-consent.limited-mode': true,
  });
  final app = _NativeAppHarness(tester);
  app.installChannels();
  addTearDown(app.close);
  await tester.pumpWidget(AiSpeakingApp(deviceConnectionNow: () => app.now));
  await tester.pumpAndSettle();
  // Drain the optional backend preload deadline before testing connection
  // actions; widget tests intentionally block network traffic.
  await tester.pump(const Duration(seconds: 15));
  await tester.pumpAndSettle();
  app.controller = tester
      .widget<ConversationScreen>(find.byType(ConversationScreen))
      .controller;
  return app;
}

class _NativeAppHarness {
  _NativeAppHarness(this.tester);

  final WidgetTester tester;
  final supportDirectory = Directory.systemTemp.createTempSync(
    'homi-device-gate-test-',
  );
  final bleCalls = <MethodCall>[];
  final scans = <Completer<List<Object?>>>[];
  List<Object?> hfpDevices = <Object?>[];
  Completer<Map<String, Object?>>? hfpConnection;
  int hfpConnectCalls = 0;
  int hfpFindCalls = 0;
  bool _closed = false;
  late ConversationController controller;
  String phase = 'idle';
  DateTime now = DateTime(2026, 10, 19, 12);
  final hfpCalls = <MethodCall>[];
  final speechCalls = <MethodCall>[];
  final speechRouteIds = <String?>[];
  final nativeCalls = <String>[];
  bool failBleConnect = true;
  Completer<void>? speechCancellation;

  Future<void> finishStartupScans() async {
    for (final scan in scans) {
      if (!scan.isCompleted) scan.complete(<Object?>[]);
    }
    await _pumpAsync(tester);
  }

  Future<void> drain(Future<Object?> operation) async {
    var completed = false;
    Object? error;
    unawaited(
      operation.then(
        (_) => completed = true,
        onError: (Object value) {
          error = value;
          completed = true;
        },
      ),
    );
    for (var i = 0; i < 30 && !completed; i++) {
      await _pumpAsync(tester);
    }
    expect(error, isNull);
    expect(
      completed,
      isTrue,
      reason: 'Native operation did not settle: $nativeCalls',
    );
  }

  Future<void> startRecording() async {
    await drain(
      controller.startRecording(noSpeechTimeout: const Duration(minutes: 5)),
    );
    expect(
      controller.isRecording,
      isTrue,
      reason: '${controller.errorMessage}; $nativeCalls',
    );
    expect(speechCalls.where((c) => c.method == 'speech.start'), isNotEmpty);
  }

  Future<void> advance(Duration duration) async {
    now = now.add(duration);
    await tester.pump(duration);
    await _pumpAsync(tester);
  }

  static const _channels = <MethodChannel>[
    MethodChannel('dexterous.com/flutter/local_notifications'),
    MethodChannel('ailingo_aiv0_ble_control'),
    MethodChannel('ailingo_aiv0_ble_control/events'),
    MethodChannel('ailingo_hfp_audio'),
    MethodChannel('ailingo_hfp_audio/events'),
    MethodChannel('ailingo_background_learning'),
    MethodChannel('ailingo_background_learning/events'),
    MethodChannel('ailingo_speech'),
    MethodChannel('ailingo_speech/events'),
    MethodChannel('ailingo_voice_prompt'),
    MethodChannel('ailingo_offline_intent'),
    MethodChannel('ailingo_offline_intent/events'),
    MethodChannel('com.llfbandit.record/messages'),
    MethodChannel('com.ryanheise.audio_session'),
    MethodChannel('plugins.flutter.io/path_provider'),
  ];

  void installChannels() {
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    final messenger = tester.binding.defaultBinaryMessenger;
    for (final channel in _channels) {
      messenger.setMockMethodCallHandler(channel, (call) async {
        nativeCalls.add('${channel.name}.${call.method}');
        if (channel.name == 'dexterous.com/flutter/local_notifications') {
          return call.method == 'show' ? null : true;
        }
        if (channel.name == 'plugins.flutter.io/path_provider') {
          return supportDirectory.path;
        }
        if (channel.name == 'ailingo_speech') {
          speechCalls.add(call);
          if (call.method == 'speech.cancel') {
            await speechCancellation?.future;
            return null;
          }
          if (call.method == 'speech.prepare' ||
              call.method == 'speech.isAvailable') {
            return true;
          }
          if (call.method == 'speech.start') {
            speechRouteIds.add(
              controller.hfpAudioStatus.routeActive
                  ? controller.hfpAudioStatus.deviceId
                  : null,
            );
            final args = call.arguments as Map<Object?, Object?>;
            await messenger.handlePlatformMessage(
              'ailingo_speech/events',
              const StandardMethodCodec().encodeSuccessEnvelope({
                'type': 'speech.ready',
                'turnId': args['turnId'],
              }),
              (_) {},
            );
            return null;
          }
        }
        if (channel.name == 'ailingo_hfp_audio') {
          hfpCalls.add(call);
          if (call.method == 'startAudioRoute') {
            return {
              'phase': 'ready',
              'deviceId': 'AA:BB:CC:DD:EE:FF',
              'deviceName': 'HM-D001',
              'routeActive': true,
              'inputDeviceName': 'HM-D001',
              'outputDeviceName': 'HM-D001',
            };
          }
          if (call.method == 'stopAudioRoute') {
            return {
              'phase': 'ready',
              'deviceId': 'AA:BB:CC:DD:EE:FF',
              'deviceName': 'HM-D001',
              'routeActive': false,
            };
          }

          if (call.method == 'disconnect') {
            return null;
          }
          if (call.method == 'findDevices') {
            hfpFindCalls += 1;
            return hfpDevices;
          }
          if (call.method == 'connect') {
            hfpConnectCalls += 1;
            final arguments = call.arguments as Map<Object?, Object?>;
            return <String, Object?>{
              'phase': 'ready',
              'deviceId': arguments['deviceId'],
              'deviceName': arguments['deviceName'],
              'routeActive': false,
            };
          }
        }
        if (channel.name == 'ailingo_aiv0_ble_control') {
          bleCalls.add(call);
          if (call.method == 'connect') {
            if (failBleConnect) throw PlatformException(code: 'CONNECT_FAILED');
            return {
              'phase': 'connected',
              'deviceId': 'AA:BB:CC:DD:EE:FF',
              'deviceName': 'HM-D001',
            };
          }

          if (call.method == 'scan') {
            final result = Completer<List<Object?>>();
            scans.add(result);
            return result.future;
          }
          if (call.method == 'cancelConnectionAttempt') {
            if (phase != 'connected') phase = 'idle';
            return <String, Object?>{
              'phase': phase,
              if (phase == 'connected') 'deviceId': 'AA:BB:CC:DD:EE:FF',
            };
          }
          if (call.method == 'bluetoothAdapterState') return 'poweredOn';
        }
        return switch (call.method) {
          'initialize' => <String, Object?>{'phase': 'idle'},
          'findDevices' => <Object?>[],
          'requestPermissions' || 'hasPermission' => true,
          _ => null,
        };
      });
    }
  }

  Future<void> emitBle(
    String nextPhase, {
    String? deviceId,
    int? batteryPercent,
  }) async {
    phase = nextPhase;
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'ailingo_aiv0_ble_control/events',
      const StandardMethodCodec().encodeSuccessEnvelope(<String, Object?>{
        'type': 'status',
        'phase': phase,
        'batteryPercent': ?batteryPercent,
        if (phase == 'connected' || deviceId != null)
          'deviceId': deviceId ?? mic.id,
        if (phase == 'connected') 'deviceName': 'HM-D001',
      }),
      (_) {},
    );
    await _pumpAsync(tester);
  }

  void clearChannels() {
    final messenger = tester.binding.defaultBinaryMessenger;
    for (final channel in _channels) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (speechCancellation?.isCompleted == false) {
      speechCancellation!.complete();
    }
    await tester.pumpWidget(const SizedBox.shrink());
    for (final scan in scans) {
      if (!scan.isCompleted) scan.complete(<Object?>[]);
    }
    await tester.pump(const Duration(seconds: 15));
    await tester.pumpAndSettle();
    clearChannels();
    if (supportDirectory.existsSync()) {
      supportDirectory.deleteSync(recursive: true);
    }
  }
}
