import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_speaking_flutter_app/core/device/device_connection_service.dart';
import 'package:ai_speaking_flutter_app/domain/device/device_connection.dart';
import 'package:ai_speaking_flutter_app/presentation/device/bloc/device_bloc.dart';

class FakePort implements DeviceConnectionPort {
  @override
  bool android = true;
  @override
  DeviceSnapshot snapshot = const DeviceSnapshot();
  final events = StreamController<void>.broadcast();
  @override
  Stream<void> get changes => events.stream;
  final calls = <String>[];
  DeviceIssue? accessIssue;
  Object? accessError;
  bool mainSucceeds = true;
  bool autoAudioSucceeds = true;
  bool dropMainWhenSelectingMicrophone = false;
  bool paired = false;
  Completer<void>? mainWait;
  Completer<void>? cancelWait;
  List<DeviceMicrophone> microphones = const [
    DeviceMicrophone(
      id: 'mic',
      name: 'HM-D001',
      connected: true,
      needsConfirmation: true,
    ),
  ];
  @override
  Future<DeviceIssue?> prepareAccess({required bool interactive}) async {
    calls.add('access');
    if (accessError case final error?) throw error;
    return accessIssue;
  }

  @override
  Future<void> resumeAutomaticConnection() async {
    calls.add('resume');
  }

  @override
  Future<void> refreshAudioPairing() async {
    calls.add('pairing');
    snapshot = DeviceSnapshot(
      mainReady: snapshot.mainReady,
      mainId: snapshot.mainId,
      audioReady: snapshot.audioReady,
      audioPaired: paired,
      audioConnected: snapshot.audioConnected,
    );
  }

  @override
  Future<bool> connectMain({required bool interactive}) async {
    calls.add('main:$interactive');
    await mainWait?.future;
    if (mainSucceeds) {
      snapshot = DeviceSnapshot(
        mainReady: true,
        mainId: 'main',
        audioReady: snapshot.audioReady,
      );
    }
    return mainSucceeds;
  }

  @override
  Future<void> pairConnectedMain() async {
    calls.add('bond');
  }

  @override
  Future<bool> autoSelectAudio() async {
    calls.add('autoAudio');
    if (autoAudioSucceeds) {
      snapshot = DeviceSnapshot(
        mainReady: snapshot.mainReady,
        mainId: snapshot.mainId,
        audioReady: true,
      );
    }
    return autoAudioSucceeds;
  }

  @override
  Future<List<DeviceMicrophone>> findMicrophones() async {
    calls.add('findMic');
    return microphones;
  }

  @override
  Future<bool> selectMicrophone(DeviceSelection selection) async {
    calls.add('selectMic');
    snapshot = DeviceSnapshot(
      mainReady: !dropMainWhenSelectingMicrophone,
      mainId: dropMainWhenSelectingMicrophone ? null : 'main',
      audioReady: true,
    );
    return true;
  }

  @override
  Future<void> cancelAttempt() async {
    calls.add('cancel');
    await cancelWait?.future;
  }

  @override
  Future<void> dispose() => events.close();
  void loseMain() {
    snapshot = DeviceSnapshot(audioReady: snapshot.audioReady);
    events.add(null);
  }
}

Future<void> drain() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late FakePort port;
  late DeviceConnectionService service;
  setUp(() {
    port = FakePort();
    service = DeviceConnectionService(port: port, delay: (_) async {});
  });
  tearDown(() async => service.dispose());

  test(
    'read-only pairing refresh updates Bloc without scan or mic selection',
    () async {
      final bloc = DeviceBloc(service: service);
      port.paired = true;
      await service.refreshAudioPairing();
      await drain();
      expect(bloc.state.snapshot.audioPaired, isTrue);
      expect(bloc.state.snapshot.ready, isFalse);
      expect(port.calls, ['pairing']);
      await bloc.close();
    },
  );

  test(
    'first installation verifies MAIN before audio, ready does not require idle SCO',
    () async {
      expect(await service.connect(), isTrue);
      expect(port.calls, [
        'access',
        'resume',
        'main:true',
        'pairing',
        'autoAudio',
      ]);
      expect(service.state.stage, DeviceStage.ready);
      expect(service.state.snapshot.routeActive, isFalse);
    },
  );
  test(
    'system bond without BLE remains partial and never opens microphone',
    () async {
      port.mainSucceeds = false;
      port.paired = true;
      expect(await service.connect(), isFalse);
      expect(service.state.snapshot.audioPaired, isTrue);
      expect(service.state.issue, DeviceIssue.mainUnavailable);
      expect(port.calls, isNot(contains('findMic')));
      expect(port.calls, isNot(contains('autoAudio')));
    },
  );
  test(
    'Classic audio blocking MAIN shows the HM-D001 recovery issue',
    () async {
      port.mainSucceeds = false;
      port.snapshot = const DeviceSnapshot(audioConnected: true);

      expect(await service.connect(), isFalse);
      expect(service.state.stage, DeviceStage.incomplete);
      expect(service.state.issue, DeviceIssue.audioBlocksMain);
      expect(port.calls, isNot(contains('autoAudio')));
      expect(port.calls, isNot(contains('findMic')));
    },
  );
  for (final issue in [
    DeviceIssue.consentRequired,
    DeviceIssue.permissionRequired,
    DeviceIssue.bluetoothOff,
    DeviceIssue.unsupported,
  ]) {
    test('$issue prevents transport work', () async {
      port.accessIssue = issue;
      expect(await service.connect(), isFalse);
      expect(port.calls, ['access']);
      expect(service.state.issue, issue);
    });
  }
  test('double tap shares one pending round', () async {
    port.mainWait = Completer<void>();
    final first = service.connect();
    final second = service.connect();
    await drain();
    expect(port.calls.where((s) => s == 'main:true').length, 1);
    port.mainWait!.complete();
    expect(await first, isTrue);
    expect(await second, isTrue);
  });
  test('cancel releases caller and ignores late MAIN success', () async {
    port.mainWait = Completer<void>();
    final pending = service.connect();
    await drain();
    await service.cancel();
    expect(await pending, isFalse);
    port.mainWait!.complete();
    await drain();
    expect(port.calls, isNot(contains('autoAudio')));
    expect(service.state.stage, DeviceStage.cancelled);
  });
  test(
    'retry waits for transport cancellation before starting a new round',
    () async {
      port.mainWait = Completer<void>();
      port.cancelWait = Completer<void>();
      final first = service.connect();
      await drain();
      final cancelled = service.cancel();
      final retry = service.connect();
      await drain();
      expect(port.calls.where((s) => s == 'access').length, 1);
      port.mainWait!.complete();
      port.mainWait = null;
      port.cancelWait!.complete();
      await cancelled;
      expect(await first, isFalse);
      expect(await retry, isTrue);
    },
  );
  test('MAIN lost while picker open rejects stale selection', () async {
    port.autoAudioSucceeds = false;
    final pending = service.connect();
    await drain();
    expect(service.state.stage, DeviceStage.choosingMicrophone);
    final token = service.state.attempt;
    port.loseMain();
    await drain();
    service.selectMicrophone(
      token,
      DeviceSelection(port.microphones.first, confirmAssociation: true),
    );
    expect(await pending, isFalse);
    expect(port.calls, isNot(contains('selectMic')));
    expect(service.state.issue, DeviceIssue.mainUnavailable);
  });
  test(
    'different identity requires explicit confirmation before selection',
    () async {
      port.autoAudioSucceeds = false;
      final pending = service.connect();
      await drain();
      final token = service.state.attempt;
      service.selectMicrophone(token, DeviceSelection(port.microphones.first));
      await drain();
      expect(port.calls, isNot(contains('selectMic')));
      service.selectMicrophone(
        token,
        DeviceSelection(port.microphones.first, confirmAssociation: true),
      );
      expect(await pending, isTrue);
    },
  );
  test('Android rejects disconnected and unknown microphones', () async {
    port.autoAudioSucceeds = false;
    port.microphones = const [
      DeviceMicrophone(id: 'offline', name: 'HM-D001', connected: false),
      DeviceMicrophone(id: 'connected', name: 'HM-D001', connected: true),
    ];
    final pending = service.connect();
    await drain();
    expect(service.state.stage, DeviceStage.choosingMicrophone);
    final attempt = service.state.attempt;

    service.selectMicrophone(attempt, DeviceSelection(port.microphones.first));
    service.selectMicrophone(
      attempt,
      const DeviceSelection(
        DeviceMicrophone(id: 'other', name: 'HM-D001', connected: true),
      ),
    );
    await drain();
    expect(port.calls, isNot(contains('selectMic')));
    expect(service.state.stage, DeviceStage.choosingMicrophone);

    service.selectMicrophone(attempt, DeviceSelection(port.microphones.last));
    expect(await pending, isTrue);
    expect(port.calls.where((call) => call == 'selectMic').length, 1);
  });
  test('missing connected Android mic ends with audio guidance', () async {
    port.autoAudioSucceeds = false;
    port.microphones = const [
      DeviceMicrophone(id: 'offline', name: 'HM-D001', connected: false),
    ];

    expect(await service.connect(), isFalse);
    expect(service.state.issue, DeviceIssue.audioUnavailable);
    expect(service.state.stage, DeviceStage.incomplete);
    expect(port.calls, isNot(contains('selectMic')));
  });
  test('reconnects verified MAIN if microphone selection drops BLE', () async {
    port.autoAudioSucceeds = false;
    port.dropMainWhenSelectingMicrophone = true;
    final pending = service.connect();
    await drain();

    service.selectMicrophone(
      service.state.attempt,
      DeviceSelection(port.microphones.first, confirmAssociation: true),
    );
    expect(await pending, isTrue);
    expect(port.calls, containsAllInOrder(['selectMic', 'main:false']));
    expect(service.state.snapshot.ready, isTrue);
  });
  test('failed MAIN recovery never reports audio-only as ready', () async {
    port.autoAudioSucceeds = false;
    port.dropMainWhenSelectingMicrophone = true;
    final pending = service.connect();
    await drain();
    port.mainSucceeds = false;

    service.selectMicrophone(
      service.state.attempt,
      DeviceSelection(port.microphones.first, confirmAssociation: true),
    );
    expect(await pending, isFalse);
    expect(port.calls, containsAllInOrder(['selectMic', 'main:false']));
    expect(service.state.snapshot.audioReady, isTrue);
    expect(service.state.snapshot.ready, isFalse);
    expect(service.state.issue, DeviceIssue.mainUnavailable);
  });
  test(
    'background/resume round never prompts, pairs, or changes retry preferences',
    () async {
      port.autoAudioSucceeds = false;
      expect(await service.connect(interactive: false), isFalse);
      expect(port.calls, isNot(contains('resume')));
      expect(port.calls, isNot(contains('bond')));
      expect(port.calls, isNot(contains('findMic')));
      expect(service.state.issue, DeviceIssue.audioUnavailable);
    },
  );
  test(
    'transport stream updates ready to partial without phone mic fallback',
    () async {
      expect(await service.connect(), isTrue);
      port.loseMain();
      await drain();
      expect(service.state.stage, DeviceStage.incomplete);
      expect(service.state.snapshot.audioReady, isTrue);
      expect(service.state.snapshot.ready, isFalse);
      expect(port.calls.where((s) => s == 'autoAudio').length, 1);
    },
  );
  test('Bloc accepts Cancel while Connect awaits hardware', () async {
    final bloc = DeviceBloc(service: service);
    port.mainWait = Completer<void>();
    final pending = bloc.connect();
    await drain();
    await bloc.cancelAttempt();
    expect(await pending, isFalse);
    await drain();
    expect(bloc.state.stage, DeviceStage.cancelled);
    port.mainWait!.complete();
    await drain();
    await bloc.close();
  });
  test(
    'Bloc routes selection events and ready state from injected service',
    () async {
      final bloc = DeviceBloc(service: service);
      port.autoAudioSucceeds = false;
      final pending = bloc.connect();
      await drain();
      expect(bloc.state.stage, DeviceStage.choosingMicrophone);
      bloc.add(
        DeviceMicrophoneSelected(
          bloc.state.attempt,
          DeviceSelection(port.microphones.first, confirmAssociation: true),
        ),
      );
      expect(await pending, isTrue);
      await drain();
      expect(bloc.state.stage, DeviceStage.ready);
      await bloc.close();
    },
  );
  test(
    'closing Bloc before queued Connect runs does not touch hardware',
    () async {
      final bloc = DeviceBloc(service: service);
      final pending = bloc.connect();
      await bloc.close();
      expect(await pending, isFalse);
      expect(port.calls, isEmpty);
    },
  );

  test('timeout cancels transport and leaves retry available', () async {
    final timed = DeviceConnectionService(
      port: FakePort()..mainWait = Completer<void>(),
      timeout: const Duration(milliseconds: 10),
    );
    expect(await timed.connect(), isFalse);
    expect(timed.state.issue, DeviceIssue.timedOut);
    await timed.dispose();
  });
  test('transport exception reports failure and allows retry', () async {
    port.accessError = StateError('Bluetooth service unavailable');

    expect(await service.connect(), isFalse);
    expect(service.state.stage, DeviceStage.failed);
    expect(service.state.issue, DeviceIssue.transportFailure);
    expect(port.calls, ['access', 'cancel']);

    port.accessError = null;
    expect(await service.connect(), isTrue);
    expect(service.state.stage, DeviceStage.ready);
  });
}
