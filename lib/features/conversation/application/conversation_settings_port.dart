import 'package:flutter/foundation.dart';

import '../../../core/audio/audio_input.dart';
import '../../../core/audio/hfp_audio_control.dart';
import '../../../core/audio/streaming_speech_input.dart';
import '../../../core/device/aiv0_ble_control.dart';
import '../../../core/device/device_connection_history.dart';
import '../../../core/device/h20_connection_state.dart';
import '../../../l10n/display_language.dart';
import '../domain/conversation_models.dart';

enum DeviceConnectionOutcome { success, busy, cancelled, unavailable, failed }

final class DeviceConnectionResult {
  const DeviceConnectionResult(this.outcome, {this.message});

  final DeviceConnectionOutcome outcome;
  final String? message;
  bool get succeeded => outcome == DeviceConnectionOutcome.success;
}

final class DeviceConnectionBusyException implements Exception {
  const DeviceConnectionBusyException();

  @override
  String toString() => 'A device or audio operation is already in progress.';
}

enum H20HardwareTestPhase {
  idle,
  openingRoute,
  recording,
  playing,
  completed,
  error,
}

final class H20HardwareTestResult {
  const H20HardwareTestResult({
    required this.completedAt,
    required this.inputRouteVerified,
    required this.outputRouteVerified,
    this.recordedDuration,
    this.inputDeviceName,
    this.outputDeviceName,
    this.playbackAudible,
  });

  final DateTime completedAt;
  final bool inputRouteVerified;
  final bool outputRouteVerified;
  final Duration? recordedDuration;
  final String? inputDeviceName;
  final String? outputDeviceName;
  final bool? playbackAudible;

  H20HardwareTestResult copyWith({bool? playbackAudible}) {
    return H20HardwareTestResult(
      completedAt: completedAt,
      inputRouteVerified: inputRouteVerified,
      outputRouteVerified: outputRouteVerified,
      recordedDuration: recordedDuration,
      inputDeviceName: inputDeviceName,
      outputDeviceName: outputDeviceName,
      playbackAudible: playbackAudible ?? this.playbackAudible,
    );
  }
}

abstract interface class ConversationHistoryPort {
  DisplayLanguage get displayLanguage;

  Future<List<ConversationHistoryItem>> loadHistory();

  Future<void> playHistoryItem(ConversationHistoryItem item);

  Future<void> playHistoryUserAudio(ConversationHistoryItem item);

  Future<ConversationLearningOutcome> reviewHistoryItem(
    ConversationHistoryItem item,
    bool approved,
  );

  Future<void> deleteHistoryItem(ConversationHistoryItem item);

  Future<void> clearHistory();
}

abstract interface class ConversationSettingsPort
    implements Listenable, ConversationHistoryPort {
  int get childAge;
  bool get isBusy;
  bool get isDeviceConnectionBusy;
  bool get automaticHfpSelectionAllowed;
  bool get automaticBleConnectionAllowed;
  ConnectionDeviceRecord? get lastConnectedBleDevice;
  ConnectionDeviceRecord? get lastConnectedMicrophone;
  String get inputLabel;
  bool get usesHfpInput;
  bool get supportsBrowserHfp;
  AsrMode get asrMode;
  ConversationPhase get phase;
  int get vadSilenceMs;
  NativeSpeechDiagnostic? get nativeSpeechDiagnostic;
  List<NativeSpeechDiagnostic> get nativeSpeechDiagnosticLog;
  Aiv0BleStatus get aiv0BleStatus;
  List<Aiv0ButtonEvent> get aiv0ButtonEventLog;
  String get aiv0MainDispatchStatus;
  DateTime? get aiv0MainDispatchAt;
  BluetoothAudioStatus get hfpAudioStatus;
  bool get canUseAiv0Ble;
  bool get h20HardwareTestModeEnabled;
  H20HardwareTestPhase get h20HardwareTestPhase;
  H20HardwareTestResult? get h20HardwareTestResult;
  String? get h20HardwareTestMessage;

  H20ConnectionState h20ConnectionState({bool mainTurnActive = false});

  void setDisplayLanguage(DisplayLanguage language);
  void setVadSilence(int milliseconds);
  void confirmH20PlaybackAudible(bool audible);

  Future<void> setH20HardwareTestMode(bool enabled);
  Future<void> toggleH20OfflineRecordingTest();
  Future<void> playH20BundledSpeakerTest();
  Future<void> testInnotrikMicrophone();
  Future<List<Aiv0BleDevice>> scanAiv0Devices();
  Future<DeviceConnectionResult> connectAiv0Device(Aiv0BleDevice device);
  Future<DeviceConnectionResult> disconnectAiv0Device();
  Future<List<BluetoothAudioDevice>> scanInnotrikDevices();
  Future<void> connectInnotrikDevice(BluetoothAudioDevice device);
  Future<List<HfpAudioDevice>> findHfpDevices();
  bool requiresHomiMicrophoneConfirmation(HfpAudioDevice device);
  Future<DeviceConnectionResult> connectHfpDevice(
    HfpAudioDevice device, {
    bool confirmHomiAssociation = false,
  });
  Future<DeviceConnectionResult> disconnectHfpDevice();
  Future<void> cancelManualDeviceConnection();
}
