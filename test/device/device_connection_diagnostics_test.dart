import 'dart:async';

import 'package:ai_speaking_flutter_app/core/device/device_connection_diagnostics.dart';
import 'package:ai_speaking_flutter_app/core/device/device_connection_service.dart';
import 'package:ai_speaking_flutter_app/domain/device/device_connection.dart';
import 'package:ai_speaking_flutter_app/presentation/device/bloc/device_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'device_connection_service_test.dart' show FakePort, drain;

class ProfilePort extends FakePort {
  bool audioConnected = false;
  bool loseMainOnAudio = false;
  final nativeAttemptIds = <Object?>[];

  @override
  Future<bool> connectMain({required bool interactive}) async {
    nativeAttemptIds.add(
      DeviceConnectionDiagnostics.channelFields['attemptId'],
    );
    final result = await super.connectMain(interactive: interactive);
    nativeAttemptIds.add(
      DeviceConnectionDiagnostics.channelFields['attemptId'],
    );
    return result;
  }

  @override
  Future<void> refreshAudioPairing() async {
    await super.refreshAudioPairing();
    snapshot = DeviceSnapshot(
      mainReady: snapshot.mainReady,
      mainId: snapshot.mainId,
      audioPaired: paired,
      audioConnected: audioConnected,
      audioReady: snapshot.audioReady,
    );
  }

  @override
  Future<bool> autoSelectAudio() async {
    final result = await super.autoSelectAudio();
    if (loseMainOnAudio) {
      snapshot = const DeviceSnapshot(
        audioPaired: true,
        audioConnected: true,
        audioReady: true,
      );
      events.add(null);
    }
    return result;
  }
}

void main() {
  test(
    'late async request retains its originating ID across a newer attempt',
    () async {
      final diagnostics = DeviceConnectionDiagnostics(
        enabled: true,
        sessionId: 'session',
      );
      final gate = Completer<void>();
      final old = diagnostics.run(1, () async {
        await gate.future;
        return DeviceConnectionDiagnostics.channelFields['attemptId'];
      });
      expect(
        diagnostics.run(2, () => DeviceConnectionDiagnostics.channelFields),
        {'attemptId': 'session-2'},
      );
      expect(DeviceConnectionDiagnostics.channelFields, isEmpty);
      gate.complete();
      expect(await old, 'session-1');
    },
  );

  test('disabled diagnostics leave channel arguments and output unchanged', () {
    final records = <Map<String, Object?>>[];
    final diagnostics = DeviceConnectionDiagnostics(sink: records.add);
    diagnostics.run(1, () {
      expect(DeviceConnectionDiagnostics.channelFields, isEmpty);
      diagnostics.event(1, 'test');
    });
    expect(records, isEmpty);
  });

  test('service, Bloc and native requests share one attempt ID', () async {
    final records = <Map<String, Object?>>[];
    final port = ProfilePort();
    final service = DeviceConnectionService(
      port: port,
      diagnostics: DeviceConnectionDiagnostics(
        enabled: true,
        sessionId: 'session',
        sink: records.add,
      ),
    );
    final bloc = DeviceBloc(service: service);
    addTearDown(() async {
      await bloc.close();
      await service.dispose();
    });
    expect(await bloc.connect(), isTrue);
    await drain();
    expect(bloc.state.snapshot.ready, isTrue);
    expect(port.nativeAttemptIds, ['session-1', 'session-1']);
    for (final layer in ['service.state', 'bloc.state']) {
      expect(
        records
            .where((r) => r['event'] == layer && r['stage'] == 'ready')
            .single['attemptId'],
        'session-1',
      );
    }
    expect(records.map((r) => r['attemptId']).toSet(), {'session-1'});
    expect(
      records.singleWhere((r) => r['event'] == 'attempt.complete')['ready'],
      isTrue,
    );
  });

  test('logger failure never changes connection outcome', () async {
    final service = DeviceConnectionService(
      port: ProfilePort(),
      diagnostics: DeviceConnectionDiagnostics(
        enabled: true,
        sink: (_) => throw StateError('sink unavailable'),
      ),
    );
    addTearDown(service.dispose);
    expect(await service.connect(), isTrue);
    expect(service.state.stage, DeviceStage.ready);
  });

  test(
    'cancel, retry and late native callback have distinct correlation',
    () async {
      final records = <Map<String, Object?>>[];
      final port = ProfilePort()..mainWait = Completer<void>();
      final oldGate = port.mainWait!;
      final service = DeviceConnectionService(
        port: port,
        diagnostics: DeviceConnectionDiagnostics(
          enabled: true,
          sessionId: 'session',
          sink: records.add,
        ),
      );
      addTearDown(service.dispose);
      final first = service.connect();
      await drain();
      await service.cancel();
      expect(await first, isFalse);
      expect(
        records.singleWhere(
          (r) => r['event'] == 'service.state' && r['stage'] == 'cancelled',
        )['attemptId'],
        'session-1',
      );
      port.mainWait = null;
      expect(await service.connect(), isTrue);
      oldGate.complete();
      await drain();
      expect(port.nativeAttemptIds, [
        'session-1',
        'session-3',
        'session-3',
        'session-1',
      ]);
      expect(service.state.stage, DeviceStage.ready);
      expect(
        records
            .where(
              (r) => r['event'] == 'service.state' && r['stage'] == 'ready',
            )
            .single['attemptId'],
        'session-3',
      );
    },
  );

  test(
    'HFP connected without MAIN remains incomplete and never selects a mic',
    () async {
      final port = ProfilePort()
        ..mainSucceeds = false
        ..paired = true
        ..audioConnected = true;
      final service = DeviceConnectionService(port: port);
      final bloc = DeviceBloc(service: service);
      addTearDown(() async {
        await bloc.close();
        await service.dispose();
      });
      expect(await bloc.connect(), isFalse);
      await drain();
      expect(bloc.state.snapshot.audioConnected, isTrue);
      expect(bloc.state.snapshot.mainReady, isFalse);
      expect(bloc.state.stage, DeviceStage.incomplete);
      expect(bloc.state.issue, DeviceIssue.audioBlocksMain);
      expect(port.calls, ['access', 'resume', 'main:true', 'pairing']);
    },
  );

  test(
    'audio arrival dropping MAIN cannot produce ready or phone fallback',
    () async {
      final port = ProfilePort()..loseMainOnAudio = true;
      final states = <DeviceConnectionState>[];
      final service = DeviceConnectionService(port: port, delay: (_) async {});
      final subscription = service.states.listen(states.add);
      addTearDown(() async {
        await subscription.cancel();
        await service.dispose();
      });
      expect(await service.connect(), isFalse);
      await drain();
      expect(service.state.issue, DeviceIssue.mainUnavailable);
      expect(service.state.snapshot.audioReady, isTrue);
      expect(states.any((s) => s.stage == DeviceStage.ready), isFalse);
      expect(port.calls, [
        'access',
        'resume',
        'main:true',
        'pairing',
        'autoAudio',
      ]);
    },
  );

  for (final android in [true, false]) {
    test(
      'diagnostics preserve ${android ? 'Android' : 'iOS'} audio retry cadence',
      () async {
        final delays = <int>[];
        final port = ProfilePort()
          ..android = android
          ..autoAudioSucceeds = false;
        final service = DeviceConnectionService(
          port: port,
          diagnostics: DeviceConnectionDiagnostics(enabled: true),
          delay: (duration) async => delays.add(duration.inMilliseconds),
        );
        addTearDown(service.dispose);
        expect(await service.connect(interactive: false), isFalse);
        expect(delays, android ? [350, 650, 900, 1200, 1600] : [600, 600]);
        expect(
          port.calls.where((c) => c == 'autoAudio').length,
          android ? 6 : 3,
        );
        expect(service.state.issue, DeviceIssue.audioUnavailable);
      },
    );
  }
}
