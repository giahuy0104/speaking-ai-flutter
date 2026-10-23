import 'dart:async';
import 'dart:io';

import 'package:ai_speaking_flutter_app/app/ai_speaking_app.dart';
import 'package:ai_speaking_flutter_app/config/app_config.dart';
import 'package:ai_speaking_flutter_app/features/conversation/domain/conversation_models.dart';
import 'package:ai_speaking_flutter_app/features/conversation/presentation/conversation_controller.dart';
import 'package:ai_speaking_flutter_app/features/conversation/presentation/conversation_screen.dart';
import 'package:ai_speaking_flutter_app/features/conversation/presentation/widgets/speak_action_bar.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/topic_lesson_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _dialog = Key('device-connection-action-dialog');
const _cancel = Key('device-connection-action-cancel');
const _retry = Key('device-connection-action-retry');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await AssetListeningContentRepository().load();
  });
  testWidgets(
    'Home action observes native retry failure and Cancel reaches native',
    (tester) async {
      final app = await _pumpApp(tester);
      await app.emitBle('reconnecting');
      expect(find.byKey(_dialog), findsNothing);

      await _tapSpeak(tester);
      expect(find.text('Đang tìm thiết bị'), findsOneWidget);
      expect(app.controller.phase, ConversationPhase.idle);

      await app.emitBle('error');
      expect(find.text('Cần kết nối thiết bị'), findsOneWidget);
      await tester.tap(find.byKey(_cancel));
      await _pumpAsync(tester);

      expect(find.byKey(_dialog), findsNothing);
      expect(
        app.bleCalls.where((call) => call.method == 'cancelConnectionAttempt'),
        hasLength(1),
      );
      expect(app.controller.phase, ConversationPhase.idle);
      expect(
        find.byKey(const Key('topic-listening-edge-tab')).hitTestable(),
        findsOneWidget,
      );
    },
    variant: TargetPlatformVariant(<TargetPlatform>{TargetPlatform.android}),
  );

  testWidgets(
    'Retry starts a fresh native scan and unsuccessful completion shows guidance',
    (tester) async {
      final app = await _pumpApp(tester);
      await app.emitBle('error');
      await _tapSpeak(tester);
      await tester.tap(find.byKey(_retry));
      await _pumpAsync(tester);

      expect(app.scans, hasLength(1));
      expect(find.text('Đang tìm thiết bị'), findsOneWidget);
      expect(app.controller.phase, ConversationPhase.idle);
      app.scans.single.complete(<Object?>[]);
      await _pumpAsync(tester);

      expect(find.text('Cần kết nối thiết bị'), findsOneWidget);
      expect(app.controller.phase, ConversationPhase.idle);
      expect(app.bleCalls.where((call) => call.method == 'connect'), isEmpty);
    },
    variant: TargetPlatformVariant(<TargetPlatform>{TargetPlatform.android}),
  );

  testWidgets(
    'Cancel rejects a late scan candidate and a new action can retry immediately',
    (tester) async {
      final app = await _pumpApp(tester);
      await _tapSpeak(tester);
      await tester.tap(find.byKey(_retry));
      await _pumpAsync(tester);
      expect(app.scans, hasLength(1));

      await tester.tap(find.byKey(_cancel));
      await _pumpAsync(tester);
      expect(find.byKey(_dialog), findsNothing);
      await _tapSpeak(tester);
      await tester.tap(find.byKey(_retry));
      await _pumpAsync(tester);
      expect(app.scans, hasLength(2));

      app.scans.first.complete(<Object?>[
        <String, Object?>{
          'id': 'AA:BB:CC:DD:EE:FF',
          'name': 'HM-D001',
          'serviceUuids': <String>['9E3B0001-4A7C-4D6F-8B21-5C17A2D94010'],
        },
      ]);
      await _pumpAsync(tester);
      expect(app.bleCalls.where((call) => call.method == 'connect'), isEmpty);
      expect(find.text('Đang tìm thiết bị'), findsOneWidget);

      app.scans.last.complete(<Object?>[]);
      await _pumpAsync(tester);
      expect(find.text('Cần kết nối thiết bị'), findsOneWidget);
      expect(app.controller.phase, ConversationPhase.idle);
    },
    variant: TargetPlatformVariant(<TargetPlatform>{TargetPlatform.android}),
  );

  testWidgets(
    'a stuck native scan releases Retry after the requested-round deadline',
    (tester) async {
      final app = await _pumpApp(tester);
      await _tapSpeak(tester);
      await tester.tap(find.byKey(_retry));
      await _pumpAsync(tester);
      expect(app.scans, hasLength(1));

      await tester.pump(const Duration(seconds: 75));
      await _pumpAsync(tester);

      expect(find.text('Cần kết nối thiết bị'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byKey(_retry)).onPressed,
        isNotNull,
      );
      expect(find.byKey(_cancel).hitTestable(), findsOneWidget);
      expect(app.controller.phase, ConversationPhase.idle);
      app.scans.single.complete(<Object?>[]);
      await _pumpAsync(tester);
      expect(find.text('Cần kết nối thiết bị'), findsOneWidget);
    },
    variant: TargetPlatformVariant(<TargetPlatform>{TargetPlatform.android}),
  );

  testWidgets(
    'Topic waits through HFP selection and opens once when both links are ready',
    (tester) async {
      final app = await _pumpApp(tester);
      await tester.tap(find.byKey(const Key('topic-listening-edge-tab')));
      await tester.pumpAndSettle();
      final topic = find.byKey(const ValueKey('topic-action-6-7-0'));
      await tester.tap(topic);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Cần kết nối thiết bị'), findsOneWidget);

      app.hfpDevices = <Object?>[
        <String, Object?>{
          'id': 'AA:BB:CC:DD:EE:FF',
          'name': 'HM-D001',
          'isConnected': true,
        },
      ];
      app.hfpConnection = Completer<Map<String, Object?>>();
      await app.emitBle('connected');
      expect(app.hfpConnectCalls, 1);
      expect(app.controller.canUseAiv0Ble, isTrue);
      expect(app.controller.isHomiReady, isFalse);
      expect(find.text('Đang tìm thiết bị'), findsOneWidget);
      expect(find.byType(TopicLessonListScreen), findsNothing);

      app.hfpConnection!.complete(<String, Object?>{
        'phase': 'ready',
        'deviceId': 'AA:BB:CC:DD:EE:FF',
        'deviceName': 'HM-D001',
        'routeActive': false,
      });
      await _pumpAsync(tester);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      // The real app persists Topic progress to a file. Allow each asynchronous
      // filesystem step to finish between fake Flutter frames.
      for (
        var i = 0;
        i < 20 &&
            find
                .byType(TopicLessonListScreen, skipOffstage: false)
                .evaluate()
                .isEmpty;
        i += 1
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(app.controller.isHomiReady, isTrue);
      expect(find.byKey(_dialog), findsNothing);
      expect(
        find.byType(TopicLessonListScreen, skipOffstage: false),
        findsOneWidget,
      );
      expect(app.hfpConnectCalls, 1);
      await app.close();
    },
    variant: TargetPlatformVariant(<TargetPlatform>{TargetPlatform.android}),
  );

  testWidgets(
    'background HFP retry resumes after Cancel on the existing 15-second tick',
    (tester) async {
      final app = await _pumpApp(tester, grantPrivacy: true);
      await app.emitBle('connected');
      await _tapSpeak(tester);
      await tester.tap(find.byKey(_cancel));
      await _pumpAsync(tester);
      final callsAfterCancel = app.hfpFindCalls;
      expect(find.byKey(_dialog), findsNothing);
      expect(app.controller.canUseAiv0Ble, isTrue);

      // The helper drained the first 15-second tick and this test has used
      // only a sub-second dialog transition. A new round must not start now.
      await tester.pump(const Duration(seconds: 10));
      await _pumpAsync(tester);
      expect(app.hfpFindCalls, callsAfterCancel);
      await tester.pump(const Duration(seconds: 5));
      await _pumpAsync(tester);
      expect(app.hfpFindCalls, greaterThan(callsAfterCancel));
      expect(find.byKey(_dialog), findsNothing);
      await app.close();
    },
    skip: !AppConfig.fromEnvironment().privacyReleaseConfigurationComplete,
    variant: TargetPlatformVariant(<TargetPlatform>{TargetPlatform.android}),
  );

  testWidgets(
    'BLE alone does not let the Home speaking action through',
    (tester) async {
      final app = await _pumpApp(tester);
      await app.emitBle('connected');
      // Let the bounded HFP selection complete without a matching microphone.
      for (var attempt = 0; attempt < 6; attempt += 1) {
        await tester.pump(const Duration(seconds: 2));
        await _pumpAsync(tester);
      }
      expect(app.controller.canUseAiv0Ble, isTrue);
      expect(app.controller.isHomiReady, isFalse);
      expect(find.byKey(_dialog), findsNothing);

      await _tapSpeak(tester);

      expect(find.byKey(_dialog), findsOneWidget);
      expect(app.controller.phase, ConversationPhase.idle);
    },
    variant: TargetPlatformVariant(<TargetPlatform>{TargetPlatform.android}),
  );
}

Future<void> _tapSpeak(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(SpeakActionBar),
      matching: find.byType(InkWell),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
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
          if (call.method == 'findDevices') {
            hfpFindCalls += 1;
            return hfpDevices;
          }
          if (call.method == 'connect') {
            hfpConnectCalls += 1;
            return hfpConnection?.future;
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
    for (var attempt = 0; attempt < 10; attempt++) {
      try {
        if (supportDirectory.existsSync()) {
          supportDirectory.deleteSync(recursive: true);
        }
        break;
      } on FileSystemException {
        if (attempt == 9) rethrow;
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pump();
      }
    }
    clearChannels();
  }
}
