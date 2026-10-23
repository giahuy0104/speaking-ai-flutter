import 'dart:async';
import 'dart:io';

import 'package:ai_speaking_flutter_app/app/ai_speaking_app.dart';
import 'package:ai_speaking_flutter_app/app/scenic_app_header.dart';
import 'package:ai_speaking_flutter_app/core/audio/hfp_audio_control.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/presentation/vocabulary_home_screen.dart';
import 'package:ai_speaking_flutter_app/l10n/display_language.dart';
import 'package:ai_speaking_flutter_app/presentation/settings/screen/settings_screen.dart';
import 'package:ai_speaking_flutter_app/features/conversation/presentation/conversation_controller.dart';
import 'package:ai_speaking_flutter_app/features/conversation/presentation/conversation_screen.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/presentation/main_voice_assistant_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'HOMI headers follow verified BLE and microphone readiness while phone input stays available',
    (tester) async {
      final app = await _pumpApp(tester);
      expect(app.controller.isInputAvailable, isTrue);
      _expectHomiHeaders(tester, ready: false);

      await app.emitBle('connected');
      await tester.pump(const Duration(seconds: 8));
      await _pumpAsync(tester);
      expect(app.controller.canUseAiv0Ble, isTrue);
      _expectHomiHeaders(tester, ready: false, status: 'Mic chưa kết nối');

      const otherMicrophone = HfpAudioDevice(
        id: 'airpods',
        name: 'AirPods',
        isConnected: true,
      );
      expect(
        (await app.controller.connectHfpDevice(otherMicrophone)).succeeded,
        isTrue,
      );
      await _pumpAsync(tester);
      _expectHomiHeaders(tester, ready: false, status: 'Cần kiểm tra mic');

      const homiMicrophone = HfpAudioDevice(
        id: 'homi-microphone-id',
        name: 'HM-D001',
        isConnected: true,
      );
      expect(
        (await app.controller.connectHfpDevice(homiMicrophone)).succeeded,
        isTrue,
      );
      await _pumpAsync(tester);
      // A matching name alone cannot make either header ready.
      _expectHomiHeaders(tester, ready: false, status: 'Cần kiểm tra mic');
      expect(
        (await app.controller.connectHfpDevice(
          homiMicrophone,
          confirmHomiAssociation: true,
        )).succeeded,
        isTrue,
      );
      await _pumpAsync(tester);
      expect(app.controller.hfpAudioStatus.routeActive, isFalse);
      _expectHomiHeaders(tester, ready: true);

      await app.emitBle('idle');
      _expectHomiHeaders(tester, ready: false, status: 'Mất kết nối MAIN');
      await app.emitBle('connected');
      _expectHomiHeaders(tester, ready: true);

      expect((await app.controller.disconnectHfpDevice()).succeeded, isTrue);
      await _pumpAsync(tester);
      expect(app.controller.isInputAvailable, isTrue);
      _expectHomiHeaders(tester, ready: false, status: 'Mic chưa kết nối');
      app.controller.setDisplayLanguage(DisplayLanguage.simplifiedChinese);
      await _pumpAsync(tester);
      _expectHomiHeaders(tester, ready: false, status: '麦克风未连接');
      await app.close();
    },
    variant: TargetPlatformVariant(<TargetPlatform>{TargetPlatform.android}),
  );

  testWidgets(
    'microphone deselection persists after Settings closes until explicit retry',
    (tester) async {
      final app = await _pumpApp(tester, grantPrivacy: true);
      app.hfpDevices = <Object?>[
        <String, Object?>{
          'id': 'AA:BB:CC:DD:EE:FF',
          'name': 'HM-D001',
          'isConnected': true,
        },
      ];
      await app.emitBle('connected');
      await _pumpAsync(tester);
      expect(app.controller.isHomiReady, isTrue);
      _expectHomiHeaders(tester, ready: true);
      tester
          .widget<ConversationScreen>(find.byType(ConversationScreen))
          .onOpenSettings();
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.byKey(const Key('settings-page')), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(MainVoiceAssistantButton), findsNothing);
      await tester.tap(find.byKey(const Key('settings-audio-hm-d001-section')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Bỏ chọn'));
      await tester.tap(find.text('Bỏ chọn'));
      await _pumpAsync(tester);
      expect(app.controller.usesHfpInput, isFalse);
      final connectsAfterDeselect = app.hfpConnectCalls;
      await tester.pump(const Duration(seconds: 15));
      await _pumpAsync(tester);
      expect(app.hfpConnectCalls, connectsAfterDeselect);
      expect(app.controller.usesHfpInput, isFalse);
      await tester.ensureVisible(find.byTooltip('Đóng'));
      await tester.tap(find.byTooltip('Đóng'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsNothing);
      await tester.pump(const Duration(seconds: 15));
      await _pumpAsync(tester);
      expect(app.hfpConnectCalls, connectsAfterDeselect);
      expect(app.controller.usesHfpInput, isFalse);
      expect(app.controller.isHomiReady, isFalse);
      _expectHomiHeaders(tester, ready: false, status: 'Mic chưa kết nối');
      tester
          .widget<ConversationScreen>(find.byType(ConversationScreen))
          .onOpenSettings();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-audio-hm-d001-section')));
      await tester.pumpAndSettle();
      final connectButton = find.byKey(const Key('settings-homi-connect'));
      await tester.ensureVisible(connectButton);
      await tester.tap(connectButton);
      await _pumpAsync(tester);
      await tester.pump(const Duration(seconds: 6));
      await _pumpAsync(tester);
      expect(app.hfpConnectCalls, greaterThan(connectsAfterDeselect));
      expect(app.controller.usesHfpInput, isTrue);
      expect(app.controller.isHomiReady, isTrue);
      _expectHomiHeaders(tester, ready: true);
      await app.close();
    },
    variant: TargetPlatformVariant(<TargetPlatform>{TargetPlatform.android}),
  );
}

void _expectHomiHeaders(
  WidgetTester tester, {
  required bool ready,
  String? status,
}) {
  final home = find.byType(ScenicAppHeader, skipOffstage: false);
  expect(tester.widget<ScenicAppHeader>(home).isReady, ready);
  expect(
    find.descendant(
      of: home,
      matching: find.text(
        status ?? (ready ? 'Sẵn sàng' : 'Chưa kết nối'),
        skipOffstage: false,
      ),
    ),
    findsOneWidget,
  );
  expect(
    tester
        .widget<VocabularyHomeScreen>(
          find.byType(VocabularyHomeScreen, skipOffstage: false),
        )
        .isReady,
    ready,
  );
}

Future<void> _pumpAsync(WidgetTester tester) async {
  for (var i = 0; i < 8; i += 1) {
    await tester.pump();
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
  await tester.pumpWidget(const AiSpeakingApp());
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

  static const _channels = <MethodChannel>[
    MethodChannel('ailingo_aiv0_ble_control'),
    MethodChannel('ailingo_aiv0_ble_control/events'),
    MethodChannel('ailingo_hfp_audio'),
    MethodChannel('ailingo_hfp_audio/events'),
    MethodChannel('ailingo_background_learning'),
    MethodChannel('ailingo_background_learning/events'),
    MethodChannel('ailingo_speech'),
    MethodChannel('ailingo_speech/events'),
    MethodChannel('ailingo_voice_prompt'),
    MethodChannel('com.llfbandit.record/messages'),
    MethodChannel('com.ryanheise.audio_session'),
    MethodChannel('plugins.flutter.io/path_provider'),
  ];

  void installChannels() {
    final messenger = tester.binding.defaultBinaryMessenger;
    for (final channel in _channels) {
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (channel.name == 'plugins.flutter.io/path_provider') {
          return supportDirectory.path;
        }
        if (channel.name == 'ailingo_hfp_audio') {
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

  Future<void> emitBle(String nextPhase) async {
    phase = nextPhase;
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'ailingo_aiv0_ble_control/events',
      const StandardMethodCodec().encodeSuccessEnvelope(<String, Object?>{
        'type': 'status',
        'phase': phase,
        if (phase == 'connected') 'deviceId': 'AA:BB:CC:DD:EE:FF',
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
