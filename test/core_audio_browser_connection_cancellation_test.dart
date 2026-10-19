import 'dart:async';

import 'package:ai_speaking_flutter_app/core/audio/audio_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/browser_hfp_audio_control.dart';
import 'package:ai_speaking_flutter_app/core/audio/hfp_audio_control.dart';
import 'package:ai_speaking_flutter_app/core/audio/phone_microphone_input.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';

void main() {
  test(
    'browser recognizes HOMI labels and clears a removed selected input',
    () async {
      for (final name in ['HM-D001', 'H20', 'HOMI']) {
        expect(isLikelyBrowserHfpLabel(name), isTrue);
      }
      final input = _Input();
      final control = BrowserHfpAudioControl(enabled: true, audioInput: input);
      addTearDown(control.dispose);
      input.selectedAudioInputDevice = const SelectableAudioInputDevice(
        id: 'gone',
        label: 'HOMI',
      );
      expect(await control.findDevices(), isEmpty);
      expect(input.selectedAudioInputDevice, isNull);
      expect(control.status.isConnected, isFalse);
    },
  );

  test(
    'browser cancellation rejects a late discovery without restoring ready',
    () async {
      final input = _Input()
        ..discovery = Completer<List<SelectableAudioInputDevice>>();
      final control = BrowserHfpAudioControl(enabled: true, audioInput: input);
      addTearDown(control.dispose);
      final pending = control.findDevices();
      final rejected = expectLater(pending, throwsA(isA<HfpAudioException>()));
      await Future<void>.delayed(Duration.zero);
      await control.cancelConnectionAttempt();
      input.discovery!.complete(const []);
      await rejected;
      expect(control.status.phase, BluetoothAudioConnectionPhase.idle);
    },
  );

  test(
    'real selectable input cannot commit a late selection after cancel',
    () async {
      final recorder = _Recorder();
      final input = PhoneMicrophoneInput(recorder: recorder);
      final control = BrowserHfpAudioControl(enabled: true, audioInput: input);
      addTearDown(control.dispose);
      final pending = control.connect(
        const HfpAudioDevice(id: 'mic', name: 'HOMI', isConnected: true),
      );
      final rejected = expectLater(pending, throwsA(isA<HfpAudioException>()));
      await Future<void>.delayed(Duration.zero);
      await control.cancelConnectionAttempt();
      recorder.discovery.complete([
        const InputDevice(id: 'mic', label: 'HOMI'),
      ]);
      await rejected;
      expect(input.selectedAudioInputDevice, isNull);
      expect(control.status.isConnected, isFalse);
    },
  );
}

class _Input
    implements SelectableAudioInputControl, AudioInputSelectionCancellation {
  Completer<List<SelectableAudioInputDevice>>? discovery;
  @override
  SelectableAudioInputDevice? selectedAudioInputDevice;
  @override
  Future<List<SelectableAudioInputDevice>> listAudioInputDevices() async =>
      discovery == null ? [] : discovery!.future;
  @override
  Future<void> selectAudioInputDevice(
    SelectableAudioInputDevice? device,
  ) async {
    selectedAudioInputDevice = device;
  }

  @override
  void cancelAudioInputSelection() {}
}

class _Recorder implements AudioRecorder {
  final discovery = Completer<List<InputDevice>>();
  @override
  Future<List<InputDevice>> listInputDevices() => discovery.future;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
