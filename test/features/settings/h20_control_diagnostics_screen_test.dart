import 'package:ai_speaking_flutter_app/core/audio/audio_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/audio_playback_service.dart';
import 'package:ai_speaking_flutter_app/core/device/active_learning_module.dart';
import 'package:ai_speaking_flutter_app/core/device/aiv0_ble_control.dart';
import 'package:ai_speaking_flutter_app/core/device/aivo_control_dispatcher.dart';
import 'package:ai_speaking_flutter_app/core/device/main_button_coordinator.dart';
import 'package:ai_speaking_flutter_app/features/conversation/application/conversation_settings_port.dart';
import 'package:ai_speaking_flutter_app/features/conversation/data/demo_conversation_repository.dart';
import 'package:ai_speaking_flutter_app/features/conversation/presentation/conversation_controller.dart';
import 'package:ai_speaking_flutter_app/features/settings/presentation/h20_control_diagnostics_screen.dart';
import 'package:ai_speaking_flutter_app/features/settings/presentation/settings_sheet.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('${platform.name} settings opens button diagnostics', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final fixture = _Fixture(platform: platform.name);
      final controller = ConversationController(
        audioInput: _AudioInput(),
        playbackService: _Playback(),
        repository: const DemoConversationRepository(),
        childAge: 6,
      );
      addTearDown(controller.dispose);
      addTearDown(fixture.dispose);
      await tester.pumpWidget(
        AivoControlScope(
          controller: fixture.controls,
          child: MaterialApp(
            home: Scaffold(body: SettingsSheet(controller: controller)),
          ),
        ),
      );
      final scroll = find
          .descendant(
            of: find.byKey(const Key('settings-scroll-view')),
            matching: find.byType(Scrollable),
          )
          .first;
      final section = find.byKey(const Key('settings-audio-h20-section'));
      await tester.scrollUntilVisible(section, 350, scrollable: scroll);
      await tester.tap(section);
      await tester.pumpAndSettle();
      final button = find.byKey(const Key('open-h20-control-diagnostics'));
      await tester.scrollUntilVisible(button, 350, scrollable: scroll);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.byType(H20ControlDiagnosticsScreen), findsOneWidget);
      expect(fixture.controls.diagnosticsActive, isTrue);
      expect(fixture.controls.executeTests, isFalse);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(fixture.controls.diagnosticsActive, isFalse);
      expect(fixture.mainCalls, 0);
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('UNKNOWN keeps exact raw; copy and clear use only control log', (
    tester,
  ) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await fixture.controls.dispatch(
      AivoControlInput(
        source: AivoControlSource.ble,
        button: Aiv0Button.unknown,
        gesture: Aiv0ButtonGesture.unknown,
        occurredAt: DateTime(2026, 9, 18, 14, 35, 22, 184),
        rawPayload: 'FE 02 7F 00',
        deviceId: 'not-exported-device',
      ),
    );
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(const Key('h20-last-button')),
        matching: find.text('UNKNOWN'),
      ),
      findsOneWidget,
    );
    expect(find.text('FE 02 7F 00'), findsOneWidget);
    expect(fixture.mainCalls, 0);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.tap(find.byKey(const Key('h20-copy-log')));
    await tester.pump();
    expect(copied, fixture.controls.exportLog());
    expect(copied, contains('raw=FE 02 7F 00'));
    expect(copied, isNot(contains('not-exported-device')));
    await tester.tap(find.byKey(const Key('h20-clear-log')));
    await tester.pump();
    expect(fixture.controls.history, isEmpty);
    expect(find.byKey(const Key('h20-no-events')), findsOneWidget);
    await fixture.unmount(tester);
  });

  testWidgets(
    'simulation does not claim physical support or execute by default',
    (tester) async {
      final fixture = _Fixture(platform: 'ios');
      addTearDown(fixture.dispose);
      await fixture.mount(tester);
      final simulated = find.byKey(const Key('h20-simulate-main-shortPress'));
      await tester.ensureVisible(simulated);
      await tester.tap(simulated);
      await tester.pump();
      expect(fixture.mainCalls, 0);
      expect(
        fixture.controls.history.first.input.source,
        AivoControlSource.simulation,
      );
      expect(
        fixture.controls.capability(
          Aiv0Button.main,
          Aiv0ButtonGesture.shortPress,
        ),
        AivoCapability.untested,
      );
      expect(find.text('Android: Chưa thử\niOS: Chưa thử'), findsNWidgets(5));
      await fixture.unmount(tester);
    },
  );

  testWidgets(
    'physical capability is current-platform only and probe timeout is explicit',
    (tester) async {
      final fixture = _Fixture(platform: 'ios');
      addTearDown(fixture.dispose);
      await fixture.mount(tester);
      await fixture.controls.dispatch(
        AivoControlInput(
          source: AivoControlSource.ble,
          button: Aiv0Button.main,
          gesture: Aiv0ButtonGesture.shortPress,
          occurredAt: DateTime.now(),
          protocol: 'observedV1',
          actionable: true,
        ),
      );
      await tester.pump();
      expect(find.text('Android: Chưa thử\niOS: Đã nhận'), findsOneWidget);
      expect(fixture.mainCalls, 0);
      final probe = find.byKey(const Key('h20-probe-volumeUp-longPress'));
      await tester.ensureVisible(probe);
      await tester.tap(probe);
      await tester.pump();
      expect(
        find.text('Android: Chưa thử\niOS: Đang chờ tín hiệu'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 8));
      expect(
        find.text('Android: Chưa thử\niOS: Không nhận trong 8 giây'),
        findsOneWidget,
      );
      await fixture.unmount(tester);
    },
  );

  testWidgets('test dispatch requires opt-in and resets on exit', (
    tester,
  ) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    final toggle = find.byKey(const Key('h20-execute-tests'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pump();
    expect(fixture.controls.executeTests, isTrue);
    final simulate = find.byKey(const Key('h20-simulate-main-shortPress'));
    await tester.ensureVisible(simulate);
    await tester.tap(simulate);
    await tester.pump();
    expect(fixture.mainCalls, 1);
    await fixture.unmount(tester);
    expect(fixture.controls.executeTests, isFalse);
    expect(fixture.controls.diagnosticsActive, isFalse);
  });

  testWidgets('last event and history redact a non-hex BLE payload', (
    tester,
  ) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await fixture.controls.dispatch(
      AivoControlInput(
        source: AivoControlSource.ble,
        button: Aiv0Button.unknown,
        gesture: Aiv0ButtonGesture.unknown,
        occurredAt: DateTime.now(),
        rawPayload: 'private speech or credential',
      ),
    );
    await tester.pump();
    expect(find.text('private speech or credential'), findsNothing);
    expect(find.text('[redacted]'), findsOneWidget);
    expect(fixture.controls.exportLog(), isNot(contains('private speech')));
    await fixture.unmount(tester);
  });

  testWidgets('connected BLE alone never claims HFP audio route', (
    tester,
  ) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    expect(find.text('Chưa xác định (theo hệ điều hành)'), findsOneWidget);
    fixture.settings.audioStatus = const BluetoothAudioStatus(
      phase: BluetoothAudioConnectionPhase.ready,
      audioRoute: 'BluetoothA2DP: H20',
    );
    fixture.settings.notifyListeners();
    await tester.pump();
    expect(find.text('BluetoothA2DP: H20'), findsOneWidget);
    await fixture.unmount(tester);
  });

  testWidgets('phone layout remains scrollable with large text and long raw', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.4)),
          child: child!,
        ),
        home: H20ControlDiagnosticsScreen(
          controller: fixture.settings,
          controls: fixture.controls,
        ),
      ),
    );
    await tester.pump();
    await fixture.controls.dispatch(
      AivoControlInput(
        source: AivoControlSource.ble,
        button: Aiv0Button.unknown,
        gesture: Aiv0ButtonGesture.unknown,
        occurredAt: DateTime.now(),
        rawPayload: List.filled(80, 'FF').join(' '),
      ),
    );
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const Key('h20-simulate-power-shortPress')),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    await fixture.unmount(tester);
  });
}

class _Fixture {
  _Fixture({String platform = 'android'}) {
    controls = AivoControlDispatcher(
      registry: registry,
      platform: platform,
      onMain: (_) async {
        mainCalls++;
        return MainButtonActionResult.accepted;
      },
      onPause: (_) async => MainButtonActionResult.accepted,
    );
  }
  final registry = ActiveLearningModuleRegistry();
  final settings = _Settings();
  late final AivoControlDispatcher controls;
  int mainCalls = 0;

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: H20ControlDiagnosticsScreen(
          controller: settings,
          controls: controls,
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  void dispose() {
    controls.dispose();
    registry.dispose();
    settings.dispose();
  }
}

class _Settings extends ChangeNotifier implements ConversationSettingsPort {
  BluetoothAudioStatus audioStatus = const BluetoothAudioStatus(
    phase: BluetoothAudioConnectionPhase.ready,
  );
  @override
  BluetoothAudioStatus get hfpAudioStatus => audioStatus;
  @override
  Aiv0BleStatus get aiv0BleStatus => const Aiv0BleStatus(
    phase: Aiv0BlePhase.connected,
    protocolConfirmed: false,
    deviceName: 'H20',
    deviceId: 'local-device',
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AudioInput implements AudioInput {
  @override
  Stream<double> get amplitudeDbfs => const Stream.empty();
  @override
  bool get isAvailable => true;
  @override
  bool get isBluetooth => false;
  @override
  String get label => 'Mic điện thoại';
  @override
  Future<void> cancel() async {}
  @override
  Future<void> dispose() async {}
  @override
  Future<void> start() async {}
  @override
  Future<AudioCapture> stop() async => const AudioCapture(
    filePath: 'unused.wav',
    mimeType: 'audio/wav',
    duration: Duration.zero,
    inputLabel: 'Mic điện thoại',
    isBluetoothInput: false,
    initialNoiseRms: null,
  );
}

class _Playback implements AudioPlaybackService {
  @override
  Stream<bool> get playingStream => const Stream.empty();
  @override
  Future<void> dispose() async {}
  @override
  Future<void> prepare() async {}
  @override
  Future<void> preload(Uri uri) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<PlaybackStartMetrics> play(Uri uri) async =>
      const PlaybackStartMetrics(
        audioLoadDuration: Duration.zero,
        startedAfterRequest: Duration.zero,
        fromDeviceCache: false,
      );
}
