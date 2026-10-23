import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/device/device_connection.dart';
import '../presentation/device/bloc/device_bloc.dart';
import '../presentation/device/device_microphone_sheet.dart';
import 'di/device_dependencies.dart';
import 'di/app_dependencies.dart';
import 'di/settings_dependencies.dart';
import '../presentation/settings/bloc/settings_bloc.dart';
import '../domain/settings/settings_repository.dart';
import '../presentation/app/bloc/app_bloc.dart';
import 'device/legacy_device_connection_port.dart';

import '../config/app_config.dart';
import '../presentation/navigation/app_view_registry.dart';
import '../core/auth/installation_auth_session.dart';
import '../core/audio/audio_playback_service.dart';
import '../core/audio/audio_turn_coordinator.dart';
import '../core/audio/browser_hfp_audio_control.dart';
import '../core/audio/device_audio_cache.dart';
import '../core/audio/hfp_audio_control.dart';
import '../core/audio/hfp_audio_route_coordinator.dart';
import '../core/audio/innotrik_ble_audio_input.dart';
import '../core/audio/offline_intent_recognizer.dart';
import '../core/audio/phone_microphone_input.dart';
import '../core/audio/preferred_audio_input.dart';
import '../core/audio/streaming_speech_input.dart';
import '../core/audio/voice_prompt_service.dart';
import '../core/device/android_device_hardware.dart';
import '../core/device/active_learning_module.dart';
import '../core/device/aiv0_ble_control.dart';
import '../core/device/aivo_control_dispatcher.dart';
import '../core/device/bluetooth_power_controller.dart';
import '../core/device/client_identity.dart';
import '../core/device/device_registration_service.dart';
import '../core/device/device_connection_coordinator.dart';
import '../core/device/device_display_name.dart';
import '../core/device/main_button_coordinator.dart';
import '../core/network/network_availability.dart';
import '../core/pwa/pwa_install_gate.dart';
import '../core/platform/background_learning_session.dart';
import '../core/session/app_flow_coordinator.dart';
import '../core/update/android_update_gate.dart';
import '../features/conversation/data/demo_conversation_repository.dart';
import '../features/conversation/data/next_conversation_repository.dart';
import '../features/conversation/application/offline_language_service.dart';
import '../features/conversation/application/vietnamese_transcript_corrector.dart';
import '../features/conversation/domain/conversation_models.dart';
import '../features/conversation/domain/conversation_repository.dart';
import '../features/conversation/presentation/conversation_controller.dart';
import '../features/home/presentation/home_learning_shell.dart';
import '../features/listening/application/android_offline_speech_model_service.dart';
import '../features/listening/application/android_runtime_platform.dart';
import '../features/listening/domain/listening_catalog.dart';
import '../features/listening/domain/listening_content.dart';
import '../features/listening/presentation/listening_route_names.dart';
import '../features/onboarding/application/onboarding_progress_store.dart';
import '../features/onboarding/application/parent_setup_progress_store.dart';
import '../features/onboarding/presentation/startup_setup_screen.dart';
import '../features/privacy/data/privacy_consent_store.dart';
import '../features/voice_navigation/application/main_speaking_fallback_flow.dart';
import '../features/voice_navigation/application/main_assistant_session.dart';
import '../features/voice_navigation/application/main_button_activation_policy.dart';
import '../features/voice_navigation/application/main_speaking_session_controller.dart';
import '../features/voice_navigation/application/voice_navigation_controller.dart';
import '../features/voice_navigation/data/web_batch_streaming_speech_input.dart';
import '../features/voice_navigation/domain/homi_fallback_catalog.dart';
import '../features/voice_navigation/presentation/main_voice_assistant_button.dart';
import '../l10n/display_language.dart';
import 'app_theme.dart';
import 'device_connection_action_gate.dart';
import 'device_connection_feedback_overlay.dart';
import 'homi_battery_alert_policy.dart';
import 'homi_battery_notifications.dart';
import 'mascot_assets.dart';

enum _HomiAutoConnectReason { background, parentSetup, periodicRetry }

enum _ParentHomiGuidanceAction { cancel, primary }

enum _ParentHfpSelectionResult {
  selected,
  unavailable,
  dismissed,
  guidanceShown,
}

class AiSpeakingApp extends StatefulWidget {
  const AiSpeakingApp({
    super.key,
    this.deviceConnectionNow,
    this.appDependenciesFactory,
    this.useDeviceConnectionService = const bool.fromEnvironment(
      'DEVICE_CONNECTION_SERVICE_ONBOARDING',
      defaultValue: true,
    ),
  });

  /// The app owns and closes the dependency scope returned by this factory.
  final AppDependenciesFactory? appDependenciesFactory;

  /// Pilot/rollback switch. Legacy setup remains intact for comparison.
  final bool useDeviceConnectionService;

  /// Allows retry deadlines to be exercised without changing their cadence.
  @visibleForTesting
  final DateTime Function()? deviceConnectionNow;

  @override
  State<AiSpeakingApp> createState() => _AiSpeakingAppState();
}

class _AiSpeakingAppState extends State<AiSpeakingApp>
    with WidgetsBindingObserver {
  late final AppConfig _config;
  ConversationController? _controller;
  VoiceNavigationController? _voiceNavigationController;
  AndroidStreamingSpeechInput? _nativeStreamingSpeechInput;
  PhoneMicrophoneInput? _phoneMicrophoneInput;
  MethodChannelAiv0BleControl? _aiv0BleControl;
  MethodChannelHfpAudioControl? _nativeHfpAudioControl;
  HfpAudioControl? _mainAssistantHfpAudioControl;
  AudioTurnCoordinator? _audioTurnCoordinator;
  HfpAudioRouteCoordinator? _hfpAudioRouteCoordinator;
  WebBatchStreamingSpeechInput? _webBatchStreamingSpeechInput;
  DeviceAudioCache? _deviceAudioCache;
  ConversationRepository? _repository;
  final ClientIdentity _clientIdentity = ClientIdentity();
  final PrivacyConsentStore _privacyConsentStore = const PrivacyConsentStore();
  final ParentSetupProgressStore _parentSetupProgressStore =
      const ParentSetupProgressStore();
  final AndroidOfflineSpeechModelConsentStore _offlineSpeechModelConsentStore =
      const SharedPreferencesAndroidOfflineSpeechModelConsentStore();
  late final AndroidOfflineSpeechModelCoordinator
  _offlineSpeechModelCoordinator = AndroidOfflineSpeechModelCoordinator(
    consentStore: _offlineSpeechModelConsentStore,
  );
  final OfflineVietnameseEnglishTranslator _offlineTranslator =
      MlKitOfflineVietnameseEnglishTranslator();
  final OfflineEnglishVietnameseTranslator _offlineVocabularyTranslator =
      MlKitOfflineEnglishVietnameseTranslator();
  final AppleOfflineSpeechAssetService _appleOfflineSpeechAssetService =
      const AppleOfflineSpeechAssetService();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();
  final HomiBatteryNotifications _homiBatteryNotifications =
      HomiBatteryNotifications();
  final HomiBatteryAlertPolicy _homiBatteryAlertPolicy =
      HomiBatteryAlertPolicy();
  late final _MainOverlayNavigatorObserver _mainOverlayNavigatorObserver;
  final ActiveLearningModuleRegistry _activeLearningModules =
      ActiveLearningModuleRegistry();
  late final AppFlowCoordinator _appFlowCoordinator;
  late final MainAssistantSession _mainAssistantSession;
  late final MainSpeakingSessionController _mainSpeakingSessionController;
  late final MainButtonCoordinator _mainButtonCoordinator;
  late final AivoControlDispatcher _deviceControlDispatcher;
  final MainSpeakingFallbackFlow _mainSpeakingFallbackFlow =
      MainSpeakingFallbackFlow();
  DeviceRegistrationService? _deviceRegistrationService;
  late final SettingsDependencies _settingsDependencies;
  SettingsBloc get _settingsBloc => _settingsDependencies.bloc;
  ThemeMode get _themeMode => _settingsBloc.state.themeMode;
  bool _isStartingMainSpeakingTurn = false;
  bool _isPreparingMainSpeakingHfpSession = false;
  bool _isFinishingMainSpeakingMode = false;
  bool _isStoppingSpeakingSession = false;
  bool _isHandlingMainSpeakingNoSpeech = false;
  bool _isHandlingMainSpeakingCommand = false;
  bool _hasMainSpeakingTurnStarted = false;
  int _mainSpeakingHfpSessionGeneration = 0;
  bool _isGlobalModalOpen = false;
  bool _showFloatingMainButton = false;
  bool _backgroundWorkStarted = false;
  bool _retryParentHomiSetupOnResume = false;
  bool _parentHomiResumeRetryInProgress = false;
  late final AppDependencies _appDependencies;
  AppBloc get _appBloc => _appDependencies.bloc;
  bool get _startupProfileLoading => _appBloc.state.isLoading;
  bool _startupPermissionRequestInProgress = false;
  int _startupPermissionGeneration = 0;
  bool _microphonePermissionGranted = false;
  bool _bluetoothPermissionGranted = false;
  bool _startupHomiAudioPaired = false;
  bool get _privacyConsentGranted => _appBloc.state.privacyConsentGranted;
  bool get _limitedModeSelected => _appBloc.state.isLimited;
  bool get _parentSetupCompleted => _appBloc.state.isReady;
  int? get _childAge => _settingsBloc.state.childAge;
  int? _pendingStartupAge;
  String? _startupPermissionError;
  DateTime? _lastAiv0AutoConnectAttempt;
  DateTime? _lastIosHfpAutoSelectionAttempt;
  String? _lastIosHfpAutoSelectionBleDeviceId;
  DateTime? _suppressHomiAutoConnectUntil;
  bool _restoreHfpAfterPhysicalMain = false;
  bool _isRestoringHfpAfterPhysicalMain = false;
  bool _offlineSpeechModelPreparationRunning = false;
  bool _offlineSpeechModelPreparationFinished = false;
  bool _disconnectingDepletedHomi = false;
  StreamSubscription<Aiv0BleStatus>? _aiv0BleStatusSubscription;
  StreamSubscription<AudioTurnDiagnostic>? _audioTurnDiagnosticSubscription;
  Timer? _iosBleReconnectNoticeTimer;
  bool _iosBleReconnectNoticeVisible = false;
  bool _iosBleHasConnectedOnce = false;
  Future<bool>? _androidHfpAutoSelectionFuture;
  Timer? _androidHfpAutoSelectionTimer;
  Future<bool>? _iosHfpAutoSelectionFuture;
  Timer? _iosUnifiedConnectionRetryTimer;
  bool _iosBleWasConnected = false;
  bool _iosHfpAutoSelectionPending = false;
  Future<bool>? _androidMainHfpRoutePreparation;
  bool _androidMainHfpRouteHeld = false;
  bool _virtualMainPhoneFallback = false;
  NativeSpeechAudioSource? _mainSpeechAudioSourceOverride;
  AndroidOfflineSpeechModelConsent _offlineSpeechModelConsent =
      AndroidOfflineSpeechModelConsent.undecided;
  Timer? _offlineSpeechModelTimer;
  final _deviceActionState = ValueNotifier<DeviceConnectionActionState>(
    DeviceConnectionActionState.unavailable,
  );
  late final DeviceConnectionActionGate _deviceActionGate;
  DeviceDependencies? _onboardingDevice;

  bool get _usesOnboardingDeviceService =>
      widget.useDeviceConnectionService &&
      !_startupReady &&
      !kIsWeb &&
      _config.enableAiv0BleControl &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  late final DeviceConnectionCoordinator _deviceConnectionCoordinator;
  late final BluetoothPowerController _bluetoothPower;
  Aiv0BlePhase? _lastBluetoothPowerPhase;
  Future<void>? _bleAutoConnectFuture;
  Future<void>? _deviceActionRetryFuture;
  Future<void>? _deviceAttemptCancellation;
  int _deviceAttemptGeneration = 0;
  Completer<void> _deviceAttemptCancelled = Completer<void>();
  bool _deviceRoundCancelled = false;
  bool _deviceActionDialogOpen = false;

  DateTime get _deviceConnectionNow =>
      widget.deviceConnectionNow?.call() ?? DateTime.now();

  bool get _requiresLearningDevice =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS) &&
      _config.enableAiv0BleControl;

  bool get _isLearningDeviceReady =>
      !_requiresLearningDevice ||
      ((!_bluetoothPower.hasChecked ||
              _bluetoothPower.state == Aiv0BluetoothAdapterState.poweredOn) &&
          _controller?.canUseAiv0Ble == true &&
          (!_config.enableHfpAudio || _controller?.isHomiReady == true));

  void _synchronizeBluetoothPower() {
    if (!mounted) return;
    final granted = switch (_bluetoothPower.state) {
      Aiv0BluetoothAdapterState.poweredOn ||
      Aiv0BluetoothAdapterState.poweredOff ||
      Aiv0BluetoothAdapterState.resetting => true,
      Aiv0BluetoothAdapterState.unauthorized => false,
      _ => _bluetoothPermissionGranted,
    };
    if (_bluetoothPermissionGranted != granted) {
      setState(() => _bluetoothPermissionGranted = granted);
    }
    _refreshDeviceActionState();
  }

  void _refreshDeviceActionState() {
    if (!mounted) return;
    final phase = _aiv0BleControl?.status.phase;
    _deviceActionState.value = _isLearningDeviceReady
        ? DeviceConnectionActionState.ready
        : !_deviceRoundCancelled &&
              (_bleAutoConnectFuture != null ||
                  _deviceActionRetryFuture != null ||
                  _androidHfpAutoSelectionFuture != null ||
                  _iosHfpAutoSelectionFuture != null ||
                  _controller?.hfpAudioStatus.isBusy == true ||
                  phase == Aiv0BlePhase.scanning ||
                  phase == Aiv0BlePhase.connecting ||
                  phase == Aiv0BlePhase.reconnecting)
        ? DeviceConnectionActionState.searching
        : DeviceConnectionActionState.unavailable;
    _deviceConnectionCoordinator.updateStatus(
      _isLearningDeviceReady
          ? DeviceConnectionPhase.ready
          : _deviceActionState.value == DeviceConnectionActionState.searching
          ? phase == Aiv0BlePhase.connecting ||
                    phase == Aiv0BlePhase.reconnecting
                ? DeviceConnectionPhase.connecting
                : _controller?.canUseAiv0Ble == true
                ? DeviceConnectionPhase.preparingMicrophone
                : DeviceConnectionPhase.searching
          : DeviceConnectionPhase.disconnected,
    );
  }

  Future<bool> _ensureLearningDeviceConnected() async {
    if (_deviceActionDialogOpen) return false;
    _refreshDeviceActionState();
    if (_isLearningDeviceReady) return true;
    final navigatorContext = _navigatorKey.currentContext;
    if (navigatorContext == null) return false;
    setState(() => _deviceActionDialogOpen = true);
    try {
      return await _deviceActionGate.ensureConnected(navigatorContext);
    } finally {
      if (mounted) setState(() => _deviceActionDialogOpen = false);
    }
  }

  Future<void> _cancelDeviceConnectionAttempt() {
    if (!mounted) return Future<void>.value();
    _deviceAttemptGeneration += 1;
    _deviceAttemptCancelled.complete();
    _deviceAttemptCancelled = Completer<void>();
    _deviceRoundCancelled = true;
    _bleAutoConnectFuture = null;
    _deviceActionRetryFuture = null;
    _androidHfpAutoSelectionFuture = null;
    _iosHfpAutoSelectionFuture = null;
    _iosHfpAutoSelectionPending = false;
    final pending = _deviceAttemptCancellation;
    if (pending != null) return pending;
    final operation =
        _controller?.cancelManualDeviceConnection() ??
        _aiv0BleControl?.cancelConnectionAttempt() ??
        Future<void>.value();
    _deviceAttemptCancellation = operation;
    _refreshDeviceActionState();
    return operation.whenComplete(() {
      if (identical(_deviceAttemptCancellation, operation)) {
        _deviceAttemptCancellation = null;
      }
      _refreshDeviceActionState();
    });
  }

  Future<void> _retryDeviceConnectionForAction() async {
    final cancellation = _cancelDeviceConnectionAttempt();
    final generation = _deviceAttemptGeneration;
    await cancellation;
    if (!mounted || generation != _deviceAttemptGeneration) return;
    if (!await _ensureParentSetupBluetoothReady(interactive: true)) return;
    if (!mounted || generation != _deviceAttemptGeneration) return;
    await _controller?.resumeAutomaticDeviceConnection();
    if (!mounted || generation != _deviceAttemptGeneration) return;
    _deviceRoundCancelled = false;
    _lastAiv0AutoConnectAttempt = _deviceConnectionNow;
    _lastIosHfpAutoSelectionAttempt = null;
    final operation = _runDeviceConnectionActionRetry(generation);
    _deviceActionRetryFuture = operation;
    _refreshDeviceActionState();
    try {
      // Bound the user-facing round even if a platform discovery never replies.
      await Future.any<void>(<Future<void>>[
        operation,
        _deviceAttemptCancelled.future,
      ]).timeout(
        Duration(
          seconds: defaultTargetPlatform == TargetPlatform.android ? 75 : 45,
        ),
      );
    } catch (error) {
      debugPrint('Requested device connection did not complete: $error');
      if (generation == _deviceAttemptGeneration) {
        await _cancelDeviceConnectionAttempt();
      }
    } finally {
      if (identical(_deviceActionRetryFuture, operation)) {
        _deviceActionRetryFuture = null;
      }
      _refreshDeviceActionState();
    }
  }

  Future<void> _runDeviceConnectionActionRetry(int generation) async {
    final control = _aiv0BleControl;
    final controller = _controller;
    if (control == null || controller == null) return;
    final connectedHfpDeviceIds = <String>[];
    if (defaultTargetPlatform == TargetPlatform.android &&
        !controller.canUseAiv0Ble) {
      try {
        final devices =
            await _nativeHfpAudioControl?.findDevices() ??
            const <HfpAudioDevice>[];
        connectedHfpDeviceIds.addAll(
          devices
              .where(
                (device) =>
                    device.isConnected &&
                    selectLikelyHomiHfpDevice(<HfpAudioDevice>[device]) != null,
              )
              .map((device) => device.id),
        );
      } catch (error) {
        debugPrint('Requested HFP discovery was unavailable: $error');
      }
    }
    if (!mounted || generation != _deviceAttemptGeneration) return;
    final pairBeforeMain =
        defaultTargetPlatform == TargetPlatform.android &&
        !controller.canUseAiv0Ble &&
        !controller.isHomiAudioReady &&
        connectedHfpDeviceIds.isEmpty;
    final connected = await control.retryKnownOrNearby(
      requestBond: pairBeforeMain,
      connectedHfpDeviceIds: connectedHfpDeviceIds,
    );
    if (!mounted || generation != _deviceAttemptGeneration || !connected) {
      return;
    }
    if (!pairBeforeMain && !controller.isHomiAudioReady) {
      // A GATT connection alone is not system pairing/HFP. This is an explicit
      // user action; background MAIN recovery never requests a new bond.
      await control.requestSystemPairingForConnectedDevice();
      if (!mounted || generation != _deviceAttemptGeneration) return;
    }
    if (!_config.enableHfpAudio) return;
    if (_isAppAudioPlaybackActive ||
        _audioTurnCoordinator?.currentToken != null ||
        !_canRestoreHfpAfterMainFlow) {
      return;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      await _autoSelectConnectedAndroidHfp(userInitiated: true);
    } else if (_usesIosHfpLifecycle) {
      _iosHfpAutoSelectionPending = true;
      await _autoSelectAvailableIosHfp(userInitiated: true);
    }
  }

  bool get _supportsOfflineLanguagePacks =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  bool get _usesIosHfpLifecycle =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  bool get _bluetoothPermissionRequired {
    return !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS) &&
        (_config.enableAiv0BleControl || _config.enableHfpAudio);
  }

  bool get _startupReady => _appBloc.state.isReady;

  bool get _voiceAccessEnabled =>
      _privacyConsentGranted && _microphonePermissionGranted;

  bool get _isActivatingMainAssistant =>
      _mainAssistantSession.isActivationPending;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appFlowCoordinator = AppFlowCoordinator(registry: _activeLearningModules);
    _mainAssistantSession = MainAssistantSession(
      appFlowCoordinator: _appFlowCoordinator,
      onActivationChanged: (_) {
        if (mounted) setState(() {});
      },
    );
    _mainOverlayNavigatorObserver = _MainOverlayNavigatorObserver(
      onVisibilityChanged: (visible) {
        if (!mounted || _showFloatingMainButton == visible) return;
        setState(() => _showFloatingMainButton = visible);
      },
    );
    _config = AppConfig.fromEnvironment();
    _settingsDependencies = SettingsDependencies(
      validateAge: _validChildAge,
      canChangeVad: () => _controller?.isBusy != true,
      onVadApplied: (value) => _controller?.applyVadSilence(value),
      onLanguageApplied: (value) => _controller?.applyDisplayLanguage(value),
      onChildAgeApplied: (value) {
        _pendingStartupAge = value;
        if (value != null) _propagateChildAge(value);
      },
    );
    _appDependencies =
        widget.appDependenciesFactory?.call(
          initialize: _loadStartupProfile,
          onResumed: _handleAppResumed,
        ) ??
        AppDependencies(
          initialize: _loadStartupProfile,
          onResumed: _handleAppResumed,
          onFailure: (error, stack) =>
              debugPrint('App lifecycle failed: $error'),
        );
    _bluetoothPower = BluetoothPowerController(
      readState: () async =>
          await _aiv0BleControl?.readBluetoothAdapterState() ??
          Aiv0BluetoothAdapterState.unsupported,
      requestEnable: () async =>
          await _aiv0BleControl?.requestEnableBluetooth() ?? false,
      requestPermission: () async {
        final granted = await _aiv0BleControl?.requestPermissions() ?? false;
        if (mounted) setState(() => _bluetoothPermissionGranted = granted);
        return granted;
      },
      openPermissionSettings: () async {
        return await _aiv0BleControl?.openPermissionSettings() ?? false;
      },
      permissionRequiresSettings: () async =>
          await _aiv0BleControl?.bluetoothPermissionRequiresSettings() ?? false,
      canRequestEnable:
          !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
    );
    _deviceConnectionCoordinator = DeviceConnectionCoordinator(
      bluetoothPower: _bluetoothPower,
      onConnect: () async {
        await _retryDeviceConnectionForAction();
        return _isLearningDeviceReady;
      },
      onCancel: _cancelDeviceConnectionAttempt,
      onOpenBluetoothSettings: () async {
        await _aiv0BleControl?.openBluetoothSettings();
      },
    );
    _bluetoothPower.addListener(_synchronizeBluetoothPower);
    _deviceActionGate = DeviceConnectionActionGate(
      state: _deviceActionState,
      language: () =>
          _controller?.displayLanguage ?? DisplayLanguage.vietnamese,
      onRetry: () async {
        await _deviceConnectionCoordinator.connect();
      },
      onCancel: _deviceConnectionCoordinator.cancel,
    );
    _mainSpeakingSessionController = MainSpeakingSessionController();
    _mainSpeakingSessionController.addListener(
      _synchronizePendingMainSpeakingAudioHandoff,
    );
    // Build the lightweight runtime before the first frame so the real home
    // screen appears immediately on both Android and web.
    _createRuntime();
    unawaited(_settingsBloc.loadField(SettingsField.language));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startBackgroundStartup();
      unawaited(_initializeStartupSetup());
      if (_supportsOfflineLanguagePacks) {
        unawaited(_prepareOfflineLanguageModels());
        _offlineSpeechModelTimer = Timer.periodic(
          const Duration(seconds: 30),
          (_) => unawaited(_prepareOfflineLanguageModels()),
        );
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _hideIosBleReconnectNotice();
      return;
    }
    unawaited(_appBloc.dispatch(AppResumed()));
  }

  void _handleAppResumed() {
    if (!mounted) return;
    final bleStatus = _aiv0BleControl?.status;
    if (bleStatus != null) _updateIosBleReconnectNotice(bleStatus);
    if (_bluetoothPower.hasChecked) unawaited(_bluetoothPower.refresh());
    unawaited(_prepareOfflineLanguageModels());
    if (_retryParentHomiSetupOnResume && _privacyConsentGranted) {
      _retryParentHomiSetupOnResume = false;
      unawaited(_retryParentHomiSetupAfterSettings());
      return;
    }
    // Flutter state is recreated after a cold launch/TestFlight update, while
    // iOS keeps the system permission grants. Refresh them whenever the app
    // returns to the foreground so MAIN does not stay hidden after the user
    // grants Microphone/Speech/Bluetooth access in Settings.
    // During onboarding, step 3 owns a read-only refresh; resuming must not
    // trigger permission dialogs or a new background connection round.
    if (_privacyConsentGranted && _parentSetupCompleted) {
      unawaited(_requestStartupPermissions());
    } else if (_parentSetupCompleted && _bluetoothPermissionGranted) {
      unawaited(_autoConnectHomiBle());
    }
  }

  Future<void> _prepareOfflineLanguageModels() async {
    if (!_supportsOfflineLanguagePacks ||
        _offlineSpeechModelPreparationRunning ||
        _offlineSpeechModelPreparationFinished) {
      return;
    }
    if (_offlineSpeechModelConsent !=
        AndroidOfflineSpeechModelConsent.allowed) {
      return;
    }
    _offlineSpeechModelPreparationRunning = true;
    try {
      var speechReady = true;
      if (isAndroidRuntime) {
        final speechResults =
            await Future.wait<AndroidOfflineSpeechModelPreparationResult>([
              _offlineSpeechModelCoordinator.prepare(locale: 'en-US'),
              _offlineSpeechModelCoordinator.prepare(locale: 'vi-VN'),
            ]);
        speechReady = speechResults.every(
          (result) =>
              result == AndroidOfflineSpeechModelPreparationResult.ready,
        );
      } else {
        for (final locale in const <String>['vi-VN', 'en-US']) {
          speechReady =
              await _appleOfflineSpeechAssetService.prepareLocale(locale) &&
              speechReady;
        }
      }

      // Speech preparation can wait for an Apple locale download. Honour a
      // parent's change to the optional download setting before starting the
      // separate translation model download.
      if (_offlineSpeechModelConsent !=
          AndroidOfflineSpeechModelConsent.allowed) {
        return;
      }
      var translationReady = await _offlineTranslator.modelsReady();
      if (!translationReady) {
        if (_offlineSpeechModelConsent !=
            AndroidOfflineSpeechModelConsent.allowed) {
          return;
        }
        translationReady = await _offlineTranslator.downloadModels(
          wifiOnly: true,
        );
      }
      if (speechReady &&
          translationReady &&
          _offlineSpeechModelConsent ==
              AndroidOfflineSpeechModelConsent.allowed) {
        _offlineSpeechModelPreparationFinished = true;
        _offlineSpeechModelTimer?.cancel();
        _offlineSpeechModelTimer = null;
      }
    } catch (error) {
      debugPrint('Offline language pack background setup skipped: $error');
    } finally {
      _offlineSpeechModelPreparationRunning = false;
    }
  }

  Future<void> _setAndroidOfflineSpeechModelDownload(bool enabled) async {
    final consent = enabled
        ? AndroidOfflineSpeechModelConsent.allowed
        : AndroidOfflineSpeechModelConsent.declined;
    await _offlineSpeechModelConsentStore.write(consent);
    if (mounted) {
      setState(() => _offlineSpeechModelConsent = consent);
    }
    if (enabled) {
      _offlineSpeechModelPreparationFinished = false;
      _offlineSpeechModelTimer ??= Timer.periodic(
        const Duration(seconds: 30),
        (_) => unawaited(_prepareOfflineLanguageModels()),
      );
      // Return to the setup UI immediately. Model downloads continue in the
      // background and never open Google's separate language-pack screen.
      unawaited(_prepareOfflineLanguageModels());
    } else {
      _offlineSpeechModelPreparationFinished = false;
      if (isAndroidRuntime) {
        await _offlineSpeechModelCoordinator.cancelDownload();
      }
    }
  }

  void _startBackgroundStartup() {
    unawaited(
      Future.wait<void>(<Future<void>>[
        _runStartupTask(() async {
          await AssetListeningContentRepository().load();
        }),
        _runStartupTask(() => _settingsBloc.loadField(SettingsField.theme)),
        _runStartupTask(_precacheHomeAssets),
      ]),
    );
    unawaited(_warmTopicImagesWhenIdle());
  }

  Future<AppStartupSnapshot> _loadStartupProfile() async {
    const empty = AppStartupSnapshot(
      privacyConsentGranted: false,
      limitedModeSelected: false,
      setupCompleted: false,
      hasValidProfile: false,
    );
    await _controller?.initializeDeviceConnectionPreferences();
    if (!mounted) return empty;
    int? storedAge;
    var storedConsent = false;
    var storedLimitedMode = false;
    var storedParentSetupComplete = false;
    var storedOfflineSpeechModelConsent =
        AndroidOfflineSpeechModelConsent.undecided;
    try {
      final values = await Future.wait<Object?>(<Future<Object?>>[
        _readSettingsChildAge(),
        _privacyConsentStore.readGranted(),
        _privacyConsentStore.readLimitedMode(),
        _parentSetupProgressStore.isComplete(),
        _supportsOfflineLanguagePacks
            ? _offlineSpeechModelConsentStore.read()
            : Future<AndroidOfflineSpeechModelConsent>.value(
                AndroidOfflineSpeechModelConsent.undecided,
              ),
      ]);
      storedAge = _validChildAge(values[0] as int?);
      storedConsent = values[1] as bool;
      storedLimitedMode = values[2] as bool;
      storedParentSetupComplete = values[3] as bool;
      storedOfflineSpeechModelConsent =
          values[4] as AndroidOfflineSpeechModelConsent;
    } catch (error) {
      debugPrint('Could not load startup privacy/profile state: $error');
    }
    if (!mounted) return empty;
    setState(() {
      _pendingStartupAge = storedAge;
      _offlineSpeechModelConsent = storedOfflineSpeechModelConsent;
    });
    return AppStartupSnapshot(
      privacyConsentGranted:
          storedConsent && _config.privacyReleaseConfigurationComplete,
      limitedModeSelected: storedLimitedMode,
      setupCompleted: storedParentSetupComplete,
      hasValidProfile: storedAge != null,
    );
  }

  Future<void> _initializeStartupSetup() async {
    await _appBloc.initialize();
    if (!mounted || _appBloc.state.status == AppStatus.initializationFailed) {
      return;
    }
    if (_privacyConsentGranted && _parentSetupCompleted) {
      _startBackgroundWork();
      _syncAndroidHfpAutoSelectionRetry();
      _syncIosUnifiedConnectionRetry();
      // Stored parental consent allows us to query the existing native grants.
      // Without this refresh `_microphonePermissionGranted` remains false on
      // every cold launch even though iOS already authorized the app, hiding
      // both the virtual MAIN entry point and the physical MAIN action.
      unawaited(_requestStartupPermissions());
    }
    if (_offlineSpeechModelConsent ==
        AndroidOfflineSpeechModelConsent.allowed) {
      unawaited(_prepareOfflineLanguageModels());
    }
  }

  int? _validChildAge(int? age) {
    if (age == null) {
      return null;
    }
    for (final catalog in listeningCatalogs) {
      if (age >= catalog.startAge && age <= catalog.endAge) {
        return age;
      }
    }
    return null;
  }

  void _propagateChildAge(int age) {
    _controller?.setChildAge(age);
    _voiceNavigationController?.setChildAge(age);
    _webBatchStreamingSpeechInput?.setChildAge(age);
  }

  Future<int?> _readSettingsChildAge() async {
    await _settingsBloc.loadField(SettingsField.childAge);
    return _settingsBloc.state.childAge;
  }

  Future<void> _setChildAge(int age) async {
    final validAge = _validChildAge(age);
    if (validAge == null || !mounted) return;
    await _settingsBloc.dispatch(SettingsChildAgeChanged(validAge));
    if (mounted) unawaited(_warmTopicImagesWhenIdle());
  }

  Future<void> _completeParentSetup() async {
    final age = _pendingStartupAge;
    if (age == null || (!_privacyConsentGranted && !_limitedModeSelected)) {
      return;
    }
    if (!_limitedModeSelected &&
        _requiresLearningDevice &&
        _controller?.isHomiReady != true) {
      return;
    }
    await _setChildAge(age);
    if (!mounted) return;
    await _parentSetupProgressStore.markComplete();
    if (!mounted) {
      return;
    }
    await _appBloc.dispatch(
      AppOnboardingCompleted(hasValidProfile: _childAge != null),
    );
    if (!mounted) return;
    if (_privacyConsentGranted) {
      _startBackgroundWork();
      _syncIosUnifiedConnectionRetry();
      if (defaultTargetPlatform == TargetPlatform.android) {
        _syncAndroidHfpAutoSelectionRetry();
        if (_controller?.canUseAiv0Ble == true &&
            _controller?.isHomiReady != true) {
          unawaited(_autoSelectConnectedAndroidHfp());
        }
      }
      if (_usesIosHfpLifecycle &&
          _controller?.canUseAiv0Ble == true &&
          _controller?.usesHfpInput != true) {
        _iosHfpAutoSelectionPending = true;
        unawaited(_autoSelectAvailableIosHfp());
      }
    }
  }

  Future<void> _grantPrivacyConsent() async {
    if (!_config.privacyReleaseConfigurationComplete) {
      return;
    }
    await _privacyConsentStore.grant();
    if (!mounted) {
      return;
    }
    setState(() => _startupPermissionError = null);
    await _appBloc.dispatch(AppConsentGranted());
  }

  Future<void> _continueWithoutVoice() async {
    if (_usesOnboardingDeviceService) {
      await _onboardingDevice?.bloc.cancelAttempt();
    }
    await _privacyConsentStore.chooseLimitedMode();
    if (!mounted) {
      return;
    }
    setState(() {
      _microphonePermissionGranted = false;
      _bluetoothPermissionGranted = false;
      _startupPermissionError = null;
    });
    await _appBloc.dispatch(AppLimitedModeSelected());
  }

  Future<void> _checkStartupPermissions() async {
    if (!_privacyConsentGranted || _startupPermissionRequestInProgress) return;
    final generation = ++_startupPermissionGeneration;
    var microphoneGranted = false;
    var bluetoothGranted = !_bluetoothPermissionRequired;
    final errors = <String>[];
    try {
      microphoneGranted =
          await _phoneMicrophoneInput?.checkPermission() ?? false;
    } catch (_) {
      errors.add('Chưa kiểm tra được quyền Micro.');
    }
    if (_bluetoothPermissionRequired) {
      try {
        bluetoothGranted = _config.enableAiv0BleControl
            ? await _aiv0BleControl?.hasPermissions() ?? false
            : await _nativeHfpAudioControl?.hasPermissions() ?? false;
        if (_config.enableAiv0BleControl) await _bluetoothPower.refresh();
      } catch (_) {
        errors.add('Chưa kiểm tra được quyền Bluetooth.');
      }
    }
    if (!mounted ||
        !_privacyConsentGranted ||
        generation != _startupPermissionGeneration ||
        _startupPermissionRequestInProgress) {
      return;
    }
    setState(() {
      _microphonePermissionGranted = microphoneGranted;
      _bluetoothPermissionGranted = bluetoothGranted;
      _startupPermissionError = errors.isEmpty ? null : errors.join('\n');
    });
    await _refreshStartupHomiAudioPairing(_deviceAttemptGeneration);
    if (mounted &&
        _usesOnboardingDeviceService &&
        _privacyConsentGranted &&
        _bluetoothPermissionGranted &&
        _bluetoothPower.canConnect) {
      await _onboardingDevice?.service.refreshAudioPairing();
    }
  }

  Future<void> _refreshStartupHomiAudioPairing(int generation) async {
    if (!mounted ||
        generation != _deviceAttemptGeneration ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android ||
        !_privacyConsentGranted ||
        !_bluetoothPermissionGranted ||
        _bluetoothPower.state != Aiv0BluetoothAdapterState.poweredOn) {
      return;
    }
    if (_controller?.isHomiAudioReady == true) {
      if (!_startupHomiAudioPaired) {
        setState(() => _startupHomiAudioPaired = true);
      }
      return;
    }
    try {
      // Read the system's bonded audio devices without selecting a mic or
      // opening its picker before MAIN has been verified.
      final devices =
          await _nativeHfpAudioControl?.findDevices() ??
          const <HfpAudioDevice>[];
      if (!mounted ||
          generation != _deviceAttemptGeneration ||
          !_privacyConsentGranted) {
        return;
      }
      final paired = selectLikelyHomiHfpDevice(devices) != null;
      if (_startupHomiAudioPaired != paired) {
        setState(() => _startupHomiAudioPaired = paired);
      }
    } catch (error) {
      debugPrint('Startup HOMI pairing status was unavailable: $error');
    }
  }

  Future<void> _requestStartupPermissions({
    bool parentInitiated = false,
    bool autoConnectHomi = true,
  }) async {
    if (_startupPermissionRequestInProgress || !_privacyConsentGranted) {
      return;
    }
    ++_startupPermissionGeneration;
    if (mounted) {
      setState(() {
        _startupPermissionRequestInProgress = true;
        _startupPermissionError = null;
      });
    }

    var microphoneGranted = false;
    var bluetoothGranted = !_bluetoothPermissionRequired;
    final errors = <String>[];
    try {
      microphoneGranted =
          await _phoneMicrophoneInput?.checkPermission() ?? false;
      if (!microphoneGranted) {
        microphoneGranted =
            await _phoneMicrophoneInput?.requestPermission() ?? false;
      }
      if (!microphoneGranted) {
        errors.add('Cần cấp quyền Micro để nghe trẻ nói.');
      }
    } catch (error) {
      errors.add('Không thể yêu cầu quyền Micro: $error');
    }

    if (_bluetoothPermissionRequired) {
      try {
        if (_config.enableAiv0BleControl) {
          bluetoothGranted = await _aiv0BleControl?.hasPermissions() ?? false;
          if (!bluetoothGranted) {
            bluetoothGranted =
                await _aiv0BleControl?.requestPermissions() ?? false;
          }
        } else {
          bluetoothGranted =
              await _nativeHfpAudioControl?.hasPermissions() ?? false;
          if (!bluetoothGranted) {
            bluetoothGranted =
                await _nativeHfpAudioControl?.requestPermissions() ?? false;
          }
        }
        if (!bluetoothGranted) {
          errors.add(
            'Cần cấp quyền Thiết bị ở gần/Bluetooth để dùng cục AIV0.',
          );
        }
      } catch (error) {
        errors.add('Không thể yêu cầu quyền Bluetooth: $error');
      }
    }

    if (parentInitiated && _homiBatteryNotifications.isSupported) {
      final notificationGranted = await _homiBatteryNotifications
          .requestPermission();
      if (!notificationGranted) {
        errors.add(
          'Cần cấp quyền Thông báo để nhận nhắc sạc HOMI và hiển thị phiên học nền.',
        );
      }
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _microphonePermissionGranted = microphoneGranted;
      _bluetoothPermissionGranted = bluetoothGranted;
      _startupPermissionRequestInProgress = false;
      _startupPermissionError = errors.isEmpty ? null : errors.join('\n');
    });
    if (autoConnectHomi && bluetoothGranted && _config.enableAiv0BleControl) {
      unawaited(_autoConnectHomiBle());
    }
  }

  Future<void> _showPrivacySetup() async {
    // Completing limited mode does not complete voice setup. Otherwise a new
    // consent grant immediately returns to Home before native permissions are
    // refreshed, leaving MAIN disabled even when Android grants are present.
    await Future.wait<void>([
      _privacyConsentStore.clearLimitedMode(),
      _parentSetupProgressStore.clear(),
    ]);
    if (mounted) {
      await _appBloc.dispatch(AppOnboardingReopened());
    }
  }

  Future<void> _revokePrivacyConsent() async {
    final controller = _controller;
    if (controller != null) {
      await controller.clearHistory();
    }
    if (!_config.useDemoBackend) {
      await InstallationAuthRegistry.revoke(
        config: _config,
        clientIdProvider: _clientIdentity.getClientId,
      );
    }
    await _privacyConsentStore.revoke();
    await _settingsBloc.dispatch(SettingsChildAgeCleared());
    if (_settingsBloc.state.failures.containsKey(SettingsField.childAge)) {
      throw StateError('Could not clear the saved child profile.');
    }
    await _parentSetupProgressStore.clear();
    await _clientIdentity.resetClientId();
    await _voiceNavigationController?.pause();
    _backgroundWorkStarted = false;
    _deviceRegistrationService = null;
    if (!mounted) {
      return;
    }
    setState(() {
      _microphonePermissionGranted = false;
      _bluetoothPermissionGranted = false;
      _pendingStartupAge = null;
      _startupPermissionError = null;
    });
    await _appBloc.dispatch(AppConsentRevoked());
    if (!mounted) return;
    _syncAndroidHfpAutoSelectionRetry();
    _syncIosUnifiedConnectionRetry();
  }

  Future<void> _autoConnectHomiBle({
    _HomiAutoConnectReason reason = _HomiAutoConnectReason.background,
  }) {
    if (_usesOnboardingDeviceService) return Future<void>.value();
    if (_deviceAttemptCancellation != null ||
        _deviceConnectionCoordinator.hasManualOperation ||
        _controller?.automaticBleConnectionAllowed != true ||
        _deviceActionRetryFuture != null) {
      return Future<void>.value();
    }
    final pending = _bleAutoConnectFuture;
    if (pending != null) return pending;
    final operation = _runAutoConnectHomiBle(
      reason: reason,
      generation: _deviceAttemptGeneration,
    );
    _bleAutoConnectFuture = operation;
    _refreshDeviceActionState();
    return operation.whenComplete(() {
      if (identical(_bleAutoConnectFuture, operation)) {
        _bleAutoConnectFuture = null;
      }
      _refreshDeviceActionState();
    });
  }

  Future<void> _runAutoConnectHomiBle({
    required int generation,
    required _HomiAutoConnectReason reason,
  }) async {
    final control = _aiv0BleControl;
    final controller = _controller;
    final voiceController = _voiceNavigationController;
    final now = _deviceConnectionNow;
    final controlOnly =
        reason != _HomiAutoConnectReason.parentSetup &&
        controller?.canUseAiv0Ble == false &&
        controller?.isHomiAudioReady == true;
    if (control == null ||
        controller == null ||
        controller.isDeviceConnectionBusy ||
        (!controlOnly &&
            (controller.isBusy ||
                _isAppAudioPlaybackActive ||
                _isActivatingMainAssistant ||
                _mainSpeakingSessionController.isActive ||
                (voiceController?.isMainButtonSessionActive ?? false) ||
                (voiceController?.isActive ?? false))) ||
        (_suppressHomiAutoConnectUntil?.isAfter(now) ?? false)) {
      return;
    }
    final lastAttempt = _lastAiv0AutoConnectAttempt;
    if (lastAttempt != null &&
        now.difference(lastAttempt) < const Duration(seconds: 10)) {
      return;
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      // Permission grants and Activity resume can precede STATE_ON after the
      // system enable dialog. A skipped round must not consume the retry window.
      final adapterState = await control.readBluetoothAdapterState();
      if (!mounted || generation != _deviceAttemptGeneration) return;
      if (adapterState != Aiv0BluetoothAdapterState.poweredOn) return;
    }
    _lastAiv0AutoConnectAttempt = now;
    _deviceRoundCancelled = false;
    if (controlOnly) {
      final knownId = controller.verifiedHomiBleDeviceId;
      if (knownId == null || knownId.trim().isEmpty) return;
      try {
        await control.autoConnectKnownOrNearby(onlyDeviceId: knownId);
      } catch (error) {
        debugPrint('HOMI MAIN recovery was skipped: $error');
      }
      if (generation != _deviceAttemptGeneration) return;
      if (!controller.canUseAiv0Ble &&
          defaultTargetPlatform == TargetPlatform.android &&
          await control.readBluetoothAdapterState() !=
              Aiv0BluetoothAdapterState.poweredOn) {
        _lastAiv0AutoConnectAttempt = null;
      }
      return;
    }
    final bleAlreadyConnected = controller.canUseAiv0Ble;
    final connectedHfpDeviceIds = <String>[];
    if (defaultTargetPlatform == TargetPlatform.android &&
        !bleAlreadyConnected) {
      try {
        final hfpDevices =
            await _nativeHfpAudioControl?.findDevices() ??
            const <HfpAudioDevice>[];
        connectedHfpDeviceIds.addAll(
          hfpDevices
              .where(
                (device) =>
                    device.isConnected &&
                    selectLikelyHomiHfpDevice(<HfpAudioDevice>[device]) != null,
              )
              .map((device) => device.id),
        );
      } catch (error) {
        debugPrint('Connected HM-D001 HFP lookup was skipped: $error');
      }
    }
    if (generation != _deviceAttemptGeneration) return;
    var bleConnected = bleAlreadyConnected;
    try {
      bleConnected =
          bleAlreadyConnected ||
          await control.autoConnectKnownOrNearby(
            userInitiated: reason == _HomiAutoConnectReason.parentSetup,
            requestBond:
                reason == _HomiAutoConnectReason.parentSetup &&
                connectedHfpDeviceIds.isEmpty,
            connectedHfpDeviceIds: connectedHfpDeviceIds,
          );
    } catch (error) {
      debugPrint('Automatic HM-D001 BLE connection was skipped: $error');
    }
    if (generation != _deviceAttemptGeneration) return;
    if (!bleConnected) {
      if (defaultTargetPlatform == TargetPlatform.android &&
          await control.readBluetoothAdapterState() !=
              Aiv0BluetoothAdapterState.poweredOn) {
        // An attempt that could not run must not hold the retry throttle
        // while Bluetooth is off; the next tick retries once it is back.
        _lastAiv0AutoConnectAttempt = null;
      }
      return;
    }
    debugPrint('HM-D001 BLE Control connected automatically.');
    if (_usesIosHfpLifecycle && reason == _HomiAutoConnectReason.parentSetup) {
      // Establish MAIN first. HFP may renegotiate the radio and briefly drop
      // GATT; readiness still requires both links, and a later retry restores
      // MAIN rather than opening a microphone picker without it.
      for (var attempt = 0; attempt < 3; attempt++) {
        if (attempt > 0) {
          await Future<void>.delayed(const Duration(milliseconds: 600));
        }
        if (!mounted ||
            generation != _deviceAttemptGeneration ||
            !controller.canUseAiv0Ble ||
            (_suppressHomiAutoConnectUntil?.isAfter(DateTime.now()) ?? false) ||
            !_canRestoreHfpAfterMainFlow) {
          return;
        }
        final selected = await controller.autoConnectHomiHfp(
          bleDeviceName: control.status.deviceName,
        );
        if (generation != _deviceAttemptGeneration) return;
        if (selected) break;
      }
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      if (reason == _HomiAutoConnectReason.parentSetup) {
        // Launch HFP separately from the BLE operation. Parent setup awaits
        // this selection and verifies both links before reporting success.
        unawaited(_autoSelectConnectedAndroidHfp());
      } else {
        await _autoSelectConnectedAndroidHfp();
      }
    } else if (_usesIosHfpLifecycle &&
        reason == _HomiAutoConnectReason.background &&
        (!bleAlreadyConnected || _iosHfpAutoSelectionPending)) {
      _iosHfpAutoSelectionPending = true;
      unawaited(_autoSelectAvailableIosHfp());
    }
    if (defaultTargetPlatform == TargetPlatform.iOS &&
        !controller.usesHfpInput) {
      debugPrint(
        'BLE is ready while HFP remains unavailable; phone microphone stays active.',
      );
    }
  }

  Future<DeviceIssue?> _prepareOnboardingDeviceAccess(bool interactive) async {
    final attempt = _onboardingDevice?.service.state.attempt;
    bool isCurrent() =>
        mounted &&
        _usesOnboardingDeviceService &&
        _onboardingDevice?.service.state.attempt == attempt;
    if (!_privacyConsentGranted) return DeviceIssue.consentRequired;
    if (interactive) {
      await _requestStartupPermissions(
        parentInitiated: true,
        autoConnectHomi: false,
      );
    } else {
      await _checkStartupPermissions();
    }
    if (!isCurrent() || !_privacyConsentGranted) {
      return DeviceIssue.consentRequired;
    }
    if (!_microphonePermissionGranted ||
        (_bluetoothPermissionRequired && !_bluetoothPermissionGranted)) {
      return DeviceIssue.permissionRequired;
    }
    // Presentation-owned system guidance is reused during migration; transport
    // orchestration lives exclusively in DeviceConnectionService.
    if (!await _ensureParentSetupBluetoothReady(interactive: interactive)) {
      return _bluetoothPower.state == Aiv0BluetoothAdapterState.unsupported
          ? DeviceIssue.unsupported
          : DeviceIssue.bluetoothOff;
    }
    return null;
  }

  Future<bool> _connectOnboardingDevice({
    bool interactive = true,
    bool chooseMicrophone = false,
  }) async {
    final device = _onboardingDevice;
    if (device == null) return false;
    if (mounted) setState(() => _startupPermissionError = null);
    final connected = await device.bloc.connect(
      interactive: interactive,
      chooseMicrophone: chooseMicrophone,
    );
    if (!mounted || !connected || !device.service.state.snapshot.ready) {
      return false;
    }
    return _finishParentHomiSetupSuccess();
  }

  String _deviceIssueMessage(DeviceIssue issue) {
    final language = _controller?.displayLanguage ?? DisplayLanguage.vietnamese;
    return switch (issue) {
      DeviceIssue.mainUnavailable => language.choose(
        'Chưa kết nối được MAIN. Hãy bật HOMI, đặt gần điện thoại rồi thử lại.',
        '尚未连接 MAIN。请开启 HOMI，靠近手机后重试。',
      ),
      DeviceIssue.audioBlocksMain => language.choose(
        'Âm thanh HOMI đã kết nối, nhưng chưa tìm thấy nút MAIN. Bạn có thể thử tạm tắt âm thanh HOMI, kết nối MAIN rồi bật lại.',
        'HOMI 音频已连接，但尚未找到 MAIN 按钮。可以尝试暂时关闭 HOMI 音频，连接 MAIN 后再开启。',
      ),
      DeviceIssue.audioUnavailable => language.choose(
        'MAIN đã kết nối nhưng micro HOMI chưa sẵn sàng. Hãy kiểm tra kết nối âm thanh rồi thử lại.',
        'MAIN 已连接，但 HOMI 麦克风尚未就绪。请检查音频连接后重试。',
      ),
      DeviceIssue.permissionRequired => language.choose(
        'Cần cấp quyền Micro và Bluetooth để kết nối HOMI.',
        '请授予麦克风和蓝牙权限以连接 HOMI。',
      ),
      DeviceIssue.bluetoothOff => language.choose(
        'Bluetooth chưa sẵn sàng. Hãy bật Bluetooth rồi thử lại.',
        '蓝牙尚未就绪。请开启蓝牙后重试。',
      ),
      DeviceIssue.unsupported => language.choose(
        'Máy này không hỗ trợ Bluetooth cần thiết cho HOMI.',
        '此设备不支持 HOMI 所需的蓝牙功能。',
      ),
      DeviceIssue.consentRequired => language.choose(
        'Vui lòng hoàn tất xác nhận quyền riêng tư trước.',
        '请先完成隐私确认。',
      ),
      DeviceIssue.selectionRequired => language.choose(
        'Hãy chọn đúng micro của HOMI để tiếp tục.',
        '请选择对应的 HOMI 麦克风以继续。',
      ),
      DeviceIssue.timedOut => language.choose(
        'Kết nối quá thời gian. Bạn có thể thử lại.',
        '连接超时，请重试。',
      ),
      DeviceIssue.transportFailure => language.choose(
        'Chưa thể kết nối HOMI. Hãy thử lại.',
        '暂时无法连接 HOMI，请重试。',
      ),
    };
  }

  Future<void> _showOnboardingMicrophoneSelection(DeviceState request) async {
    final device = _onboardingDevice;
    final navigatorContext = _navigatorKey.currentContext;
    if (device == null || navigatorContext == null || !mounted) return;
    final language = _controller!.displayLanguage;
    bool current() =>
        mounted &&
        device.service.state.attempt == request.attempt &&
        device.service.state.stage == DeviceStage.choosingMicrophone &&
        device.service.state.snapshot.mainReady;
    final selected = await showModalBottomSheet<DeviceMicrophone>(
      context: navigatorContext,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => BlocProvider.value(
        value: device.bloc,
        child: DeviceMicrophoneSheet(request: request, language: language),
      ),
    );
    if (!current()) return;
    DeviceSelection? selection;
    if (selected != null) {
      if (defaultTargetPlatform == TargetPlatform.android &&
          !selected.connected) {
        final open = await _showParentHomiGuidanceDialog(
          title: language.choose('Kết nối âm thanh HOMI', '连接 HOMI 音频'),
          message: language.choose(
            'Micro đã ghép đôi nhưng chưa kết nối âm thanh. Hãy kết nối trong Cài đặt Bluetooth.',
            '麦克风已配对，但音频未连接。请在蓝牙设置中连接。',
          ),
          primaryLabel: language.choose('Mở Cài đặt', '打开设置'),
        );
        if (open && current()) {
          _retryParentHomiSetupOnResume = true;
          await _aiv0BleControl?.openBluetoothSettings();
        }
      } else {
        final confirmed =
            !selected.needsConfirmation ||
            await _confirmParentHomiMicrophone(
              _controller!,
              HfpAudioDevice(
                id: selected.id,
                name: selected.name,
                isConnected: selected.connected,
              ),
            );
        if (confirmed) {
          selection = DeviceSelection(
            selected,
            confirmAssociation: selected.needsConfirmation,
          );
        }
      }
    }
    if (current() && !device.bloc.isClosed) {
      device.bloc.add(DeviceMicrophoneSelected(request.attempt, selection));
    }
  }

  Future<bool> _configureHomiForParentSetup() async {
    if (_usesOnboardingDeviceService) return _connectOnboardingDevice();
    return _runParentHomiSetup(interactive: true, inlineFeedback: true);
  }

  Future<bool> _chooseHomiMicrophoneForParentSetup() async {
    if (_usesOnboardingDeviceService) {
      return _connectOnboardingDevice(chooseMicrophone: true);
    }
    return _runParentHomiSetup(interactive: true, forceMicrophonePicker: true);
  }

  /// Audio guide action. The setup screen checks the connection itself when
  /// the app resumes, so no app-level resume retry is armed here.
  Future<void> _openBluetoothSettingsForOnboarding() async {
    await _aiv0BleControl?.openBluetoothSettings();
  }

  Future<void> _retryParentHomiSetupAfterSettings() async {
    if (_usesOnboardingDeviceService) {
      await _connectOnboardingDevice(interactive: false);
      return;
    }
    if (_parentHomiResumeRetryInProgress) return;
    _parentHomiResumeRetryInProgress = true;
    try {
      await _runParentHomiSetup(interactive: false);
    } finally {
      _parentHomiResumeRetryInProgress = false;
    }
  }

  Future<bool> _runParentHomiSetup({
    required bool interactive,
    bool forceMicrophonePicker = false,
    bool inlineFeedback = false,
  }) async {
    final generation = _deviceAttemptGeneration;
    bool isCurrent() => mounted && generation == _deviceAttemptGeneration;
    if (!_privacyConsentGranted) {
      return false;
    }
    await _requestStartupPermissions(
      parentInitiated: true,
      autoConnectHomi: false,
    );
    if (!isCurrent()) return false;
    if (!_microphonePermissionGranted ||
        (_bluetoothPermissionRequired && !_bluetoothPermissionGranted)) {
      return false;
    }
    if (!await _ensureParentSetupBluetoothReady(interactive: interactive)) {
      return false;
    }
    if (!isCurrent()) return false;
    final controller = _controller;
    if (controller == null) return false;
    if (interactive) await controller.resumeAutomaticDeviceConnection();
    if (!isCurrent()) return false;

    final bleWasAlreadyConnected = controller.canUseAiv0Ble;
    _lastAiv0AutoConnectAttempt = null;
    await _autoConnectHomiBle(reason: _HomiAutoConnectReason.parentSetup);
    if (!isCurrent()) return false;
    await _androidHfpAutoSelectionFuture;
    if (!isCurrent()) return false;
    await _refreshStartupHomiAudioPairing(generation);
    if (!isCurrent()) return false;
    if (!controller.canUseAiv0Ble) {
      setState(() {
        _startupPermissionError =
            _aiv0BleControl?.status.message ??
            'Chưa kết nối được HOMI. Hãy bật thiết bị, đặt gần điện thoại rồi thử lại.';
      });
      return false;
    }
    if (controller.isHomiReady && !forceMicrophonePicker) {
      return await _finishParentHomiSetupSuccess();
    }
    if (interactive &&
        bleWasAlreadyConnected &&
        controller.canUseAiv0Ble &&
        !controller.isHomiAudioReady) {
      await _aiv0BleControl?.requestSystemPairingForConnectedDevice();
    }

    if (!isCurrent()) return false;
    if (interactive &&
        controller.canUseAiv0Ble &&
        (forceMicrophonePicker || !controller.isHomiAudioReady)) {
      final selected = await _selectParentSetupHfpMicrophone(
        controller,
        interactive: true,
        attemptGeneration: generation,
        showUnavailableGuidance: !inlineFeedback,
      );
      if (!isCurrent()) return false;
      if (selected == _ParentHfpSelectionResult.selected) {
        _lastAiv0AutoConnectAttempt = null;
        await _autoConnectHomiBle(reason: _HomiAutoConnectReason.parentSetup);
      } else if (selected == _ParentHfpSelectionResult.dismissed ||
          selected == _ParentHfpSelectionResult.guidanceShown) {
        return false;
      }
    }

    if (!isCurrent()) return false;
    if (interactive &&
        controller.canUseAiv0Ble &&
        controller.usesHfpInput &&
        !controller.isHomiReady) {
      final status = controller.hfpAudioStatus;
      final selected = HfpAudioDevice(
        id: status.deviceId ?? '',
        name: status.deviceName ?? '',
        isConnected: status.isConnected,
      );
      if (controller.requiresHomiMicrophoneConfirmation(selected)) {
        if (!await _confirmParentHomiMicrophone(controller, selected)) {
          return false;
        }
        if (!isCurrent()) return false;
        final result = await controller.connectHfpDevice(
          selected,
          confirmHomiAssociation: true,
        );
        if (!result.succeeded) return false;
      }
    }
    if (!isCurrent()) return false;
    if (controller.isHomiReady) {
      return await _finishParentHomiSetupSuccess();
    }

    if (interactive && !inlineFeedback) {
      await _showIncompleteParentHomiGuidance(controller);
    } else if (mounted) {
      setState(() {
        _startupPermissionError = controller.canUseAiv0Ble
            ? 'Nút MAIN đã kết nối nhưng micro HM-D001 chưa sẵn sàng. Bấm Kết nối thiết bị để chọn micro.'
            : controller.usesHfpInput
            ? 'Micro HM-D001 đã sẵn sàng nhưng chưa kết nối được nút MAIN qua BLE.'
            : 'Chưa kết nối được HM-D001. Hãy kiểm tra Bluetooth và thiết bị rồi thử lại.';
      });
    }
    if (!isCurrent()) return false;
    if (controller.isHomiReady) {
      return _finishParentHomiSetupSuccess();
    }
    return false;
  }

  Future<bool> _finishParentHomiSetupSuccess() async {
    if (_controller?.isHomiReady != true) return false;
    if (defaultTargetPlatform == TargetPlatform.android) {
      final deviceId = _aiv0BleControl?.status.deviceId?.trim();
      if (deviceId != null && deviceId.isNotEmpty) {
        final associated = await MethodChannelBackgroundLearningSession()
            .associateHomiCompanion(deviceId);
        if (!associated && mounted) {
          setState(() {
            _startupPermissionError =
                'Phụ huynh cần xác nhận HM-D001 trong cửa sổ thiết bị đồng hành của Android để duy trì phiên học nền.';
          });
          return true;
        }
      }
    }
    if (mounted) {
      setState(() => _startupPermissionError = null);
    }
    return true;
  }

  Future<bool> _ensureParentSetupBluetoothReady({
    required bool interactive,
  }) async {
    final control = _aiv0BleControl;
    if (control == null) return false;
    await _bluetoothPower.refresh();
    var state = _bluetoothPower.state;
    if (state == Aiv0BluetoothAdapterState.resetting ||
        state == Aiv0BluetoothAdapterState.unknown) {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await _bluetoothPower.refresh();
      state = _bluetoothPower.state;
    }
    if (interactive && state == Aiv0BluetoothAdapterState.unauthorized) {
      await _bluetoothPower.authorize();
      state = _bluetoothPower.state;
    }
    if (state == Aiv0BluetoothAdapterState.poweredOn) return true;

    final message = switch (state) {
      Aiv0BluetoothAdapterState.poweredOff =>
        'Bluetooth đang tắt. Hãy bật Bluetooth để kết nối với HM-D001.',
      Aiv0BluetoothAdapterState.unauthorized =>
        _bluetoothPower.needsPermissionSettings
            ? 'Hệ điều hành không còn hiện hộp thoại cấp quyền Bluetooth. Hãy bật quyền Bluetooth/Thiết bị ở gần trong Cài đặt HOMI.'
            : 'HOMI chưa được phép sử dụng Bluetooth. Hãy bấm Cho phép Bluetooth để thử lại.',
      Aiv0BluetoothAdapterState.unsupported =>
        'Điện thoại này không hỗ trợ Bluetooth Low Energy cần thiết cho HM-D001.',
      Aiv0BluetoothAdapterState.resetting =>
        'Bluetooth đang khởi động lại. Hãy đợi một chút rồi thử lại.',
      _ => 'Bluetooth chưa sẵn sàng. Hãy kiểm tra Bluetooth rồi thử lại.',
    };
    if (mounted) setState(() => _startupPermissionError = message);
    if (!interactive || state == Aiv0BluetoothAdapterState.unsupported) {
      return false;
    }

    if (defaultTargetPlatform == TargetPlatform.android &&
        state == Aiv0BluetoothAdapterState.poweredOff) {
      final enabled = await _bluetoothPower.enable();
      if (enabled && mounted) {
        setState(() => _startupPermissionError = null);
      }
      return enabled;
    }

    if (defaultTargetPlatform == TargetPlatform.iOS &&
        state == Aiv0BluetoothAdapterState.poweredOff) {
      final checkAgain = await _showParentHomiGuidanceDialog(
        title: 'Bật Bluetooth trên iPhone',
        message:
            'iOS không cho phép HOMI tự bật Bluetooth. Hãy bật Bluetooth trong Trung tâm điều khiển; nếu đã tắt hoàn toàn, bật trong Cài đặt Bluetooth rồi quay lại HOMI.',
        primaryLabel: 'Kiểm tra lại',
      );
      if (!checkAgain) return false;
      await _bluetoothPower.refresh();
      return _bluetoothPower.canConnect;
    }

    final needsPermission = state == Aiv0BluetoothAdapterState.unauthorized;
    // A normal denial/interrupted request should remain in the app, where the
    // parent can request again. Only a confirmed blocked prompt needs Settings.
    if (needsPermission && !_bluetoothPower.needsPermissionSettings) {
      return false;
    }
    final retry = await _showParentHomiGuidanceDialog(
      title: needsPermission ? 'Cho phép Bluetooth' : 'Bluetooth chưa sẵn sàng',
      message: defaultTargetPlatform == TargetPlatform.iOS
          ? '$message\n\nSau khi bật hoặc cho phép Bluetooth, hãy quay lại HOMI. Ứng dụng sẽ tự kiểm tra lại.'
          : message,
      primaryLabel: needsPermission ? 'Mở cài đặt quyền HOMI' : 'Kiểm tra lại',
    );
    if (retry && needsPermission) {
      _retryParentHomiSetupOnResume = true;
      await _bluetoothPower.openPermissionSettings();
    } else if (retry) {
      await _bluetoothPower.refresh();
      return _bluetoothPower.canConnect;
    }
    return false;
  }

  Future<_ParentHfpSelectionResult> _selectParentSetupHfpMicrophone(
    ConversationController controller, {
    required bool interactive,
    int? attemptGeneration,
    bool showUnavailableGuidance = true,
  }) async {
    final mainDeviceId = controller.aiv0BleStatus.deviceId;
    bool isCurrent() =>
        mounted &&
        mainDeviceId != null &&
        controller.canUseAiv0Ble &&
        controller.aiv0BleStatus.deviceId == mainDeviceId &&
        (attemptGeneration == null ||
            attemptGeneration == _deviceAttemptGeneration);
    if (!isCurrent()) return _ParentHfpSelectionResult.dismissed;
    List<HfpAudioDevice> devices;
    try {
      devices = await controller.findHfpDevices();
    } catch (error) {
      if (mounted) {
        setState(() {
          _startupPermissionError = 'Chưa thể kiểm tra micro Bluetooth: $error';
        });
      }
      return _ParentHfpSelectionResult.unavailable;
    }
    if (!isCurrent()) return _ParentHfpSelectionResult.dismissed;
    if (devices.isEmpty) {
      const message =
          'Chưa tìm thấy micro HM-D001. Hãy kết nối thiết bị trong Cài đặt Bluetooth rồi quay lại HOMI.';
      if (mounted) setState(() => _startupPermissionError = message);
      if (interactive && showUnavailableGuidance) {
        final openSettings = await _showParentHomiGuidanceDialog(
          title: 'Chưa tìm thấy micro HOMI',
          message: message,
          primaryLabel: 'Mở Cài đặt',
        );
        if (openSettings && isCurrent()) {
          _retryParentHomiSetupOnResume = true;
          await _aiv0BleControl?.openBluetoothSettings();
        }
      }
      return interactive
          ? _ParentHfpSelectionResult.guidanceShown
          : _ParentHfpSelectionResult.unavailable;
    }
    if (!interactive) {
      final automatic = selectLikelyHomiHfpDevice(
        devices,
        bleDeviceName:
            _aiv0BleControl?.status.deviceName ??
            controller.aiv0BleStatus.deviceName,
      );
      if (automatic == null ||
          (defaultTargetPlatform == TargetPlatform.android &&
              !automatic.isConnected)) {
        return _ParentHfpSelectionResult.unavailable;
      }
      try {
        final result = await controller.connectHfpDevice(automatic);
        return result.succeeded && controller.usesHfpInput
            ? _ParentHfpSelectionResult.selected
            : _ParentHfpSelectionResult.unavailable;
      } catch (_) {
        return _ParentHfpSelectionResult.unavailable;
      }
    }

    final navigatorContext = _navigatorKey.currentContext;
    if (!mounted || navigatorContext == null || !navigatorContext.mounted) {
      return _ParentHfpSelectionResult.dismissed;
    }

    final selected = await showModalBottomSheet<HfpAudioDevice>(
      context: navigatorContext,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.75,
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) => Column(
              children: <Widget>[
                Expanded(
                  child: ListView(
                    key: const Key('parent-homi-microphone-list'),
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    children: <Widget>[
                      Text(
                        'Chọn micro HOMI',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        !isCurrent()
                            ? 'HOMI đã ngắt kết nối. Hãy kết nối lại thiết bị trước khi chọn micro.'
                            : defaultTargetPlatform == TargetPlatform.iOS
                            ? 'iPhone chỉ hiển thị các micro Bluetooth đang khả dụng. Hãy chọn đúng micro HOMI.'
                            : 'Hãy chọn micro HOMI đã ghép đôi. Thiết bị đang kết nối được ưu tiên.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      for (final device in devices) ...<Widget>[
                        ListTile(
                          enabled: isCurrent(),
                          leading: Icon(
                            Icons.headset_mic_rounded,
                            color: device.isConnected
                                ? AppColors.success
                                : Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                          ),
                          title: Text(
                            localizedDeviceName(
                              device.name,
                              controller.displayLanguage,
                              deviceId: device.id,
                            ),
                          ),
                          subtitle: Text(
                            device.isConnected
                                ? 'Đang kết nối'
                                : defaultTargetPlatform == TargetPlatform.iOS
                                ? 'Micro Bluetooth khả dụng'
                                : 'Đã ghép đôi • cần kết nối trong Cài đặt',
                          ),
                          trailing: device.isConnected
                              ? const Icon(
                                  Icons.check_circle_rounded,
                                  color: AppColors.success,
                                )
                              : const Icon(Icons.chevron_right_rounded),
                          onTap: !isCurrent()
                              ? null
                              : () => Navigator.of(sheetContext).pop(device),
                        ),
                        const Divider(height: 1),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      key: const Key('parent-homi-microphone-cancel'),
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      child: const Text('Để sau'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (selected == null || !isCurrent()) {
      return _ParentHfpSelectionResult.dismissed;
    }

    if (defaultTargetPlatform == TargetPlatform.android &&
        !selected.isConnected) {
      final openSettings = await _showParentHomiGuidanceDialog(
        title: 'Kết nối HM-D001',
        message:
            'HM-D001 đã được ghép đôi nhưng chưa kết nối âm thanh. Hãy kết nối thiết bị trong Cài đặt Bluetooth rồi quay lại.',
        primaryLabel: 'Mở Cài đặt Bluetooth',
      );
      if (openSettings && isCurrent()) {
        _retryParentHomiSetupOnResume = true;
        await _aiv0BleControl?.openBluetoothSettings();
      }
      return _ParentHfpSelectionResult.guidanceShown;
    }

    try {
      final needsConfirmation = controller.requiresHomiMicrophoneConfirmation(
        selected,
      );
      if (needsConfirmation &&
          !await _confirmParentHomiMicrophone(controller, selected)) {
        return _ParentHfpSelectionResult.dismissed;
      }
      if (!isCurrent()) return _ParentHfpSelectionResult.dismissed;
      final result = await controller.connectHfpDevice(
        selected,
        confirmHomiAssociation: needsConfirmation,
      );
      if (mounted) {
        setState(
          () => _startupPermissionError = result.succeeded
              ? null
              : controller.displayLanguage.choose(
                  'Chưa thể chọn micro. Hãy thử lại.',
                  '暂时无法选择麦克风，请重试。',
                ),
        );
      }
      return result.succeeded && controller.usesHfpInput
          ? _ParentHfpSelectionResult.selected
          : _ParentHfpSelectionResult.unavailable;
    } catch (error) {
      if (mounted) {
        setState(() {
          _startupPermissionError = 'Chưa thể chọn micro HM-D001: $error';
        });
      }
      return _ParentHfpSelectionResult.unavailable;
    }
  }

  Future<bool> _confirmParentHomiMicrophone(
    ConversationController controller,
    HfpAudioDevice device,
  ) async {
    final language = controller.displayLanguage;
    final bleId = controller.aiv0BleStatus.deviceId;
    final microphone = localizedDeviceName(
      device.name,
      language,
      deviceId: device.id,
    );
    final ble = localizedDeviceName(
      controller.aiv0BleStatus.deviceName,
      language,
      deviceId: controller.aiv0BleStatus.deviceId,
    );
    final confirmed = await _showParentHomiGuidanceDialog(
      title: language.choose('Xác nhận micro của HOMI', '确认 HOMI 麦克风'),
      message: language.choose(
        'Micro $microphone (${device.id}) và thiết bị $ble (${controller.aiv0BleStatus.deviceId}) có mã định danh khác nhau. Chỉ xác nhận nếu đây là micro của chính thiết bị HOMI bạn đang sử dụng.',
        '麦克风 $microphone（${device.id}）与设备 $ble（${controller.aiv0BleStatus.deviceId}）的标识不同。仅当该麦克风属于您正在使用的 HOMI 设备时才确认。',
      ),
      primaryLabel: language.choose('Đúng, đây là micro HOMI', '确认属于 HOMI'),
    );
    return mounted &&
        confirmed &&
        controller.aiv0BleStatus.isConnected &&
        bleId != null &&
        controller.aiv0BleStatus.deviceId == bleId;
  }

  Future<void> _showIncompleteParentHomiGuidance(
    ConversationController controller,
  ) async {
    final homiState = controller.homiConnectionState();
    final bleReady = homiState.bleReady;
    final hfpReady = homiState.hfpReady;
    final bleRequiredForSetup =
        !bleReady &&
        (_usesIosHfpLifecycle ||
            defaultTargetPlatform == TargetPlatform.android);
    final message = bleRequiredForSetup
        ? 'Chưa kết nối được nút MAIN qua BLE. Hãy bật HM-D001, đặt gần điện thoại rồi thử lại.'
        : bleReady && !hfpReady
        ? 'Nút MAIN đã kết nối nhưng micro HM-D001 chưa sẵn sàng. Hãy kết nối HM-D001 trong Cài đặt Bluetooth rồi quay lại.'
        : hfpReady && !bleReady
        ? 'Micro HM-D001 đã sẵn sàng nhưng chưa kết nối được nút MAIN. Hãy bật HM-D001, đặt thiết bị gần điện thoại rồi thử lại.'
        : 'Chưa kết nối được HM-D001. Hãy bật HM-D001, bật Bluetooth và kết nối thiết bị trong Cài đặt Bluetooth.';
    if (mounted) setState(() => _startupPermissionError = message);
    final shouldOpenSettings = !bleRequiredForSetup && !hfpReady;
    final accepted = await _showParentHomiGuidanceDialog(
      title: bleRequiredForSetup
          ? 'Chưa kết nối nút MAIN'
          : bleReady || hfpReady
          ? 'Kết nối HM-D001 chưa hoàn tất'
          : 'Chưa kết nối HM-D001',
      message: message,
      primaryLabel: shouldOpenSettings
          ? defaultTargetPlatform == TargetPlatform.android
                ? 'Mở Cài đặt Bluetooth'
                : 'Mở Cài đặt'
          : 'Thử lại',
    );
    if (!accepted) return;
    if (shouldOpenSettings) {
      _retryParentHomiSetupOnResume = true;
      await _aiv0BleControl?.openBluetoothSettings();
      return;
    }
    _lastAiv0AutoConnectAttempt = null;
    await _autoConnectHomiBle(
      reason: _usesIosHfpLifecycle
          ? _HomiAutoConnectReason.background
          : _HomiAutoConnectReason.parentSetup,
    );
  }

  Future<bool> _showParentHomiGuidanceDialog({
    required String title,
    required String message,
    required String primaryLabel,
  }) async {
    final navigatorContext = _navigatorKey.currentContext;
    if (!mounted || navigatorContext == null) return false;
    final action = await showDialog<_ParentHomiGuidanceAction>(
      context: navigatorContext,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(_ParentHomiGuidanceAction.cancel),
            child: const Text('Để sau'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(_ParentHomiGuidanceAction.primary),
            child: Text(primaryLabel),
          ),
        ],
      ),
    );
    return action == _ParentHomiGuidanceAction.primary;
  }

  void _handleAiv0BleStatus(Aiv0BleStatus status) {
    if (_lastBluetoothPowerPhase != status.phase ||
        _bluetoothPower.state != Aiv0BluetoothAdapterState.poweredOn) {
      _lastBluetoothPowerPhase = status.phase;
      if (_bluetoothPower.hasChecked) unawaited(_bluetoothPower.refresh());
    }
    _refreshDeviceActionState();
    _handleHomiBatteryStatus(status);
    if (_usesOnboardingDeviceService) return;
    if (defaultTargetPlatform == TargetPlatform.android) {
      _syncAndroidHfpAutoSelectionRetry();
    }
    // Transport recovery updates the device state without owning a global
    // modal. Setup and Settings present progress within their own screens.
    if (_deviceRoundCancelled ||
        _deviceConnectionCoordinator.hasManualOperation ||
        _controller?.automaticHfpSelectionAllowed != true ||
        _controller?.automaticBleConnectionAllowed != true) {
      return;
    }
    if (_usesIosHfpLifecycle) {
      _updateIosBleReconnectNotice(status);
      final justConnected = status.isConnected && !_iosBleWasConnected;
      _iosBleWasConnected = status.isConnected;
      if (!status.isConnected) {
        _iosHfpAutoSelectionPending = false;
      } else if (justConnected) {
        _iosHfpAutoSelectionPending = true;
        unawaited(_autoSelectAvailableIosHfp());
      }
      return;
    }
    if (status.isConnected &&
        defaultTargetPlatform == TargetPlatform.android &&
        _controller?.isHomiReady != true) {
      unawaited(_autoSelectConnectedAndroidHfp());
    }
  }

  void _handleHomiBatteryStatus(Aiv0BleStatus status) {
    final actions = _homiBatteryAlertPolicy.observe(
      connected: status.isConnected,
      deviceId: status.deviceId,
      batteryPercent: status.batteryPercent,
    );
    for (final action in actions) {
      switch (action) {
        case HomiBatteryAction.chargeSoon:
        case HomiBatteryAction.chargeLow:
        case HomiBatteryAction.chargeCritical:
          final language =
              _controller?.displayLanguage ?? DisplayLanguage.vietnamese;
          final percent = status.batteryPercent!;
          _showHomiBatteryNotice(
            HomiBatteryNotifications.message(percent, language),
            critical: action == HomiBatteryAction.chargeCritical,
          );
          unawaited(
            _homiBatteryNotifications.show(
              percent: percent,
              language: language,
            ),
          );
        case HomiBatteryAction.disconnectDepleted:
          _showHomiBatteryNotice(
            'Pin HOMI đã hết. Ứng dụng đang ngắt kết nối với HOMI.',
            critical: true,
          );
          unawaited(_disconnectDepletedHomi());
      }
    }
  }

  void _showHomiBatteryNotice(String message, {bool critical = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final messenger = _scaffoldMessengerKey.currentState;
      if (messenger == null) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            duration: Duration(seconds: critical ? 10 : 7),
          ),
        );
    });
  }

  Future<void> _disconnectDepletedHomi() async {
    if (_disconnectingDepletedHomi) return;
    final control = _aiv0BleControl;
    if (control == null || !control.status.isConnected) return;
    _disconnectingDepletedHomi = true;
    try {
      await control.disconnect();
    } catch (error) {
      debugPrint('Could not disconnect depleted HM-D001 BLE: $error');
    } finally {
      _disconnectingDepletedHomi = false;
    }
  }

  void _updateIosBleReconnectNotice(Aiv0BleStatus status) {
    if (!_usesIosHfpLifecycle) return;
    if (status.isConnected) {
      _iosBleHasConnectedOnce = true;
      _hideIosBleReconnectNotice();
      return;
    }
    final recovering =
        status.phase == Aiv0BlePhase.scanning ||
        status.phase == Aiv0BlePhase.connecting ||
        status.phase == Aiv0BlePhase.reconnecting;
    if (!_iosBleHasConnectedOnce ||
        !_startupReady ||
        !recovering ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      _hideIosBleReconnectNotice();
      return;
    }
    if (_iosBleReconnectNoticeVisible || _iosBleReconnectNoticeTimer != null) {
      return;
    }
    _iosBleReconnectNoticeTimer = Timer(const Duration(seconds: 2), () {
      _iosBleReconnectNoticeTimer = null;
      final current = _aiv0BleControl?.status;
      if (!mounted ||
          !_startupReady ||
          current == null ||
          current.isConnected ||
          (current.phase != Aiv0BlePhase.scanning &&
              current.phase != Aiv0BlePhase.connecting &&
              current.phase != Aiv0BlePhase.reconnecting) ||
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        return;
      }
      setState(() => _iosBleReconnectNoticeVisible = true);
    });
  }

  void _hideIosBleReconnectNotice() {
    _iosBleReconnectNoticeTimer?.cancel();
    _iosBleReconnectNoticeTimer = null;
    if (!mounted || !_iosBleReconnectNoticeVisible) return;
    setState(() => _iosBleReconnectNoticeVisible = false);
  }

  bool get _isAppAudioPlaybackActive {
    final mode = _audioTurnCoordinator?.currentToken?.mode;
    return mode == AudioTurnMode.promptPlayback ||
        mode == AudioTurnMode.mediaPlayback ||
        (_controller?.isPlaybackPlaying ?? false) ||
        _mainSpeakingSessionController.state ==
            MainSpeakingSessionState.playing;
  }

  void _synchronizeDeviceConnections() {
    _refreshDeviceActionState();
    if (defaultTargetPlatform == TargetPlatform.android && mounted) {
      _syncAndroidHfpAutoSelectionRetry();
    }
    if (!mounted ||
        !_startupReady ||
        _deviceRoundCancelled ||
        _deviceConnectionCoordinator.hasManualOperation ||
        _controller?.automaticHfpSelectionAllowed != true ||
        _controller?.automaticBleConnectionAllowed != true) {
      return;
    }
    if (_usesIosHfpLifecycle) {
      if (_iosHfpAutoSelectionPending) {
        unawaited(_autoSelectAvailableIosHfp());
      }
      return;
    }
    if (_isAppAudioPlaybackActive) {
      return;
    }
    final status = _aiv0BleControl?.status;
    final controller = _controller;
    final homiReady = controller?.isHomiReady == true;
    final hfpRecoveryPending =
        status?.isConnected == true &&
        !homiReady &&
        (_androidHfpAutoSelectionFuture != null ||
            (controller?.hfpAudioStatus.isBusy ?? false));
    if (!homiReady &&
        defaultTargetPlatform == TargetPlatform.android &&
        status?.isConnected == true &&
        (controller?.usesHfpInput ?? false) &&
        !hfpRecoveryPending) {
      // Recover the selected HFP profile in the background when BLE MAIN
      // remains connected. A Settings disconnect clears usesHfpInput.
      unawaited(_autoSelectConnectedAndroidHfp());
    }
  }

  Future<bool> _autoSelectAvailableIosHfp({bool userInitiated = false}) {
    if (_usesOnboardingDeviceService) return Future<bool>.value(false);
    if ((!userInitiated && _deviceConnectionCoordinator.hasManualOperation) ||
        _controller?.automaticHfpSelectionAllowed != true ||
        _controller?.automaticBleConnectionAllowed != true ||
        _deviceRoundCancelled ||
        !_usesIosHfpLifecycle ||
        !_iosHfpAutoSelectionPending ||
        !_startupReady ||
        !_microphonePermissionGranted ||
        !_bluetoothPermissionGranted) {
      return Future<bool>.value(false);
    }
    final controller = _controller;
    final ble = _aiv0BleControl;
    if (controller == null || ble == null || !controller.canUseAiv0Ble) {
      return Future<bool>.value(false);
    }
    if (controller.usesHfpInput && controller.hfpAudioStatus.isConnected) {
      _iosHfpAutoSelectionPending = false;
      return Future<bool>.value(true);
    }
    final pending = _iosHfpAutoSelectionFuture;
    if (pending != null) return pending;
    final now = DateTime.now();
    if ((_suppressHomiAutoConnectUntil?.isAfter(now) ?? false) ||
        (_lastIosHfpAutoSelectionAttempt != null &&
            _lastIosHfpAutoSelectionBleDeviceId == ble.status.deviceId &&
            now.difference(_lastIosHfpAutoSelectionAttempt!) <
                const Duration(seconds: 30)) ||
        !_canRestoreHfpAfterMainFlow ||
        controller.hfpAudioStatus.isBusy ||
        _isAppAudioPlaybackActive ||
        _audioTurnCoordinator?.currentToken != null ||
        (_isGlobalModalOpen && !userInitiated) ||
        _restoreHfpAfterPhysicalMain) {
      return Future<bool>.value(false);
    }
    final operation = _runIosHfpAutoSelection(
      controller,
      ble,
      _deviceAttemptGeneration,
      userInitiated: userInitiated,
    );
    _iosHfpAutoSelectionFuture = operation;
    _refreshDeviceActionState();
    return operation.whenComplete(() {
      if (identical(_iosHfpAutoSelectionFuture, operation)) {
        _iosHfpAutoSelectionFuture = null;
      }
      _refreshDeviceActionState();
    });
  }

  Future<bool> _runIosHfpAutoSelection(
    ConversationController controller,
    MethodChannelAiv0BleControl ble,
    int generation, {
    required bool userInitiated,
  }) async {
    // A GATT connected event can arrive before the native route and status
    // callbacks finish. Discover only after that transition has settled.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted ||
        generation != _deviceAttemptGeneration ||
        !controller.canUseAiv0Ble ||
        (controller.usesHfpInput && controller.hfpAudioStatus.isConnected) ||
        !_canRestoreHfpAfterMainFlow ||
        controller.hfpAudioStatus.isBusy ||
        _isAppAudioPlaybackActive ||
        _audioTurnCoordinator?.currentToken != null ||
        (_isGlobalModalOpen && !userInitiated)) {
      return false;
    }
    _iosHfpAutoSelectionPending = false;
    _lastIosHfpAutoSelectionAttempt = DateTime.now();
    _lastIosHfpAutoSelectionBleDeviceId = ble.status.deviceId;
    final selected = await controller.autoConnectHomiHfp(
      bleDeviceName:
          ble.status.deviceName ?? controller.aiv0BleStatus.deviceName,
    );
    if (selected) {
      debugPrint(
        'Connected iOS HM-D001 HFP microphone selected automatically.',
      );
    }
    return selected;
  }

  Future<bool> _autoSelectConnectedAndroidHfp({bool userInitiated = false}) {
    if (_usesOnboardingDeviceService) return Future<bool>.value(false);
    if ((!userInitiated && _deviceConnectionCoordinator.hasManualOperation) ||
        _controller?.automaticHfpSelectionAllowed != true ||
        _controller?.automaticBleConnectionAllowed != true ||
        _deviceRoundCancelled ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android) {
      return Future<bool>.value(false);
    }
    final controller = _controller;
    final ble = _aiv0BleControl;
    if (controller == null || ble == null || !controller.canUseAiv0Ble) {
      return Future<bool>.value(false);
    }
    if (controller.isHomiReady) {
      return Future<bool>.value(true);
    }
    final pending = _androidHfpAutoSelectionFuture;
    if (pending != null) return pending;
    final operation = _runAndroidHfpAutoSelection(
      controller,
      ble,
      _deviceAttemptGeneration,
    );
    _androidHfpAutoSelectionFuture = operation;
    _refreshDeviceActionState();
    return operation.whenComplete(() {
      if (identical(_androidHfpAutoSelectionFuture, operation)) {
        _androidHfpAutoSelectionFuture = null;
      }
      _refreshDeviceActionState();
    });
  }

  void _syncIosUnifiedConnectionRetry() {
    if (!_usesIosHfpLifecycle ||
        !_config.enableAiv0BleControl ||
        !_privacyConsentGranted ||
        !_parentSetupCompleted) {
      _iosUnifiedConnectionRetryTimer?.cancel();
      _iosUnifiedConnectionRetryTimer = null;
      return;
    }
    // Bluetooth Classic may connect after HOMI is already open. Keep looking
    // for the verified BLE MAIN link and matching HFP input without asking the
    // parent to scan or select a second device.
    _iosUnifiedConnectionRetryTimer ??= Timer.periodic(
      const Duration(seconds: 15),
      (_) {
        if (!mounted ||
            !_startupReady ||
            !_bluetoothPermissionGranted ||
            WidgetsBinding.instance.lifecycleState !=
                AppLifecycleState.resumed) {
          return;
        }
        final controller = _controller;
        if (controller == null) return;
        if (controller.canUseAiv0Ble) {
          if (!(controller.usesHfpInput &&
                  controller.hfpAudioStatus.isConnected) &&
              !controller.hfpAudioStatus.isBusy) {
            _iosHfpAutoSelectionPending = true;
            unawaited(_autoSelectAvailableIosHfp());
          }
          return;
        }
        final lastAttempt = _lastAiv0AutoConnectAttempt;
        if (lastAttempt != null &&
            DateTime.now().difference(lastAttempt) <
                const Duration(seconds: 60)) {
          return;
        }
        unawaited(
          _autoConnectHomiBle(reason: _HomiAutoConnectReason.periodicRetry),
        );
      },
    );
  }

  void _syncAndroidHfpAutoSelectionRetry() {
    if (kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android ||
        !_privacyConsentGranted ||
        !_parentSetupCompleted ||
        _controller?.isHomiReady == true ||
        _controller?.automaticBleConnectionAllowed != true ||
        (_controller?.canUseAiv0Ble == true &&
            _controller?.automaticHfpSelectionAllowed != true)) {
      _androidHfpAutoSelectionTimer?.cancel();
      _androidHfpAutoSelectionTimer = null;
      return;
    }
    // The headset profile can connect after the initial bounded search while
    // BLE remains connected. Retry quietly until the matching mic is ready.
    _androidHfpAutoSelectionTimer ??= Timer.periodic(
      const Duration(seconds: 15),
      (_) {
        if (!mounted || _controller?.isHomiReady == true) {
          _syncAndroidHfpAutoSelectionRetry();
          return;
        }
        if (WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.paused ||
            _isGlobalModalOpen ||
            _deviceConnectionCoordinator.hasManualOperation ||
            _deviceAttemptCancellation != null ||
            _deviceActionRetryFuture != null ||
            _controller?.hfpAudioStatus.isBusy == true) {
          return;
        }
        final controlOnly =
            _controller?.canUseAiv0Ble != true &&
            _controller?.isHomiAudioReady == true;
        if (!controlOnly &&
            (!_canRestoreHfpAfterMainFlow ||
                _isAppAudioPlaybackActive ||
                _audioTurnCoordinator?.currentToken != null)) {
          return;
        }
        if (_controller?.canUseAiv0Ble != true) {
          // Native BLE has five reconnect attempts; connection timeouts add
          // to their backoff. Keep the existing periodic recovery cadence.
          // A HM-D001 switched on later must reconnect without reopening the
          // app, so keep trying quietly at a cadence the radio can afford.
          final lastAttempt = _lastAiv0AutoConnectAttempt;
          if (lastAttempt != null &&
              _deviceConnectionNow.difference(lastAttempt) <
                  const Duration(seconds: 60)) {
            return;
          }
          unawaited(
            _autoConnectHomiBle(reason: _HomiAutoConnectReason.periodicRetry),
          );
          return;
        }
        _deviceRoundCancelled = false;
        unawaited(_autoSelectConnectedAndroidHfp());
      },
    );
  }

  Future<bool> _runAndroidHfpAutoSelection(
    ConversationController controller,
    MethodChannelAiv0BleControl ble,
    int generation,
  ) async {
    try {
      const retryDelays = <Duration>[
        Duration.zero,
        Duration(milliseconds: 350),
        Duration(milliseconds: 650),
        Duration(milliseconds: 900),
        Duration(milliseconds: 1200),
        Duration(milliseconds: 1600),
      ];
      for (var attempt = 0; attempt < retryDelays.length; attempt += 1) {
        if (attempt > 0) {
          await Future<void>.delayed(retryDelays[attempt]);
        }
        if (!mounted ||
            generation != _deviceAttemptGeneration ||
            !controller.canUseAiv0Ble ||
            _isAppAudioPlaybackActive ||
            _audioTurnCoordinator?.currentToken != null ||
            !_canRestoreHfpAfterMainFlow) {
          return false;
        }
        if (controller.isHomiReady) return true;
        final selected = await controller.autoConnectHomiHfp(
          bleDeviceName:
              ble.status.deviceName ?? controller.aiv0BleStatus.deviceName,
          requireConnected: true,
        );
        if (generation != _deviceAttemptGeneration) return false;
        if (selected && controller.isHomiReady) {
          debugPrint(
            'Connected Android HM-D001 HFP microphone selected automatically.',
          );
          return true;
        }
      }
      debugPrint(
        'Android BLE is ready but the paired HM-D001 HFP microphone is not connected; HM-D001 remains unavailable.',
      );
      return false;
    } catch (error) {
      debugPrint('Android HM-D001 HFP recovery failed: $error');
      return false;
    }
  }

  Future<void> _runStartupTask(Future<void> Function() task) async {
    try {
      await task();
    } catch (error, stackTrace) {
      debugPrint('Startup preload was skipped: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _precacheHomeAssets() async {
    await Future.wait<void>(<Future<void>>[
      precacheImage(const AssetImage(MascotAssets.scenery), context),
      precacheImage(const AssetImage(MascotAssets.avatar), context),
    ]);
  }

  Future<void> _warmTopicImagesWhenIdle() async {
    // Prioritize interactivity, then decode only the first visible topic cards
    // sequentially so entering the catalog does not cause a burst of work.
    await Future<void>.delayed(const Duration(milliseconds: 280));
    if (!mounted) {
      return;
    }
    final childAge = _controller?.childAge ?? _config.childAge;
    var catalogIndex = listeningCatalogs.lastIndexWhere(
      (catalog) => childAge >= catalog.startAge,
    );
    if (catalogIndex < 0) {
      catalogIndex = 0;
    }
    for (final topic in listeningCatalogs[catalogIndex].topics.take(4)) {
      final imagePath = topic.imagePath;
      if (imagePath == null || !mounted) {
        continue;
      }
      await _runStartupTask(
        () => precacheImage(AssetImage(imagePath), context),
      );
    }
  }

  void _createRuntime() {
    final audioTurnCoordinator = AudioTurnCoordinator();
    final ConversationRepository repository = _config.useDemoBackend
        ? const DemoConversationRepository()
        : NextConversationRepository(
            config: _config,
            clientIdProvider: _clientIdentity.getClientId,
            clientIdResetter: _clientIdentity.resetClientId,
          );
    final deviceAudioCache = DeviceAudioCache();
    final supportsAndroidNativeSpeech =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final supportsAppleNativeSpeech =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    final supportsNativeSpeech =
        supportsAndroidNativeSpeech || supportsAppleNativeSpeech;
    final supportsNativeBluetooth =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    final innotrikInput = InnotrikBleAudioInput(
      enabled: supportsAndroidNativeSpeech && _config.enableLegacyBleAudio,
    );
    final phoneMicrophoneInput = PhoneMicrophoneInput();
    final MethodChannelHfpAudioControl? nativeHfpAudioControl;
    final HfpAudioControl rawHfpAudioControl;
    if (kIsWeb) {
      nativeHfpAudioControl = null;
      rawHfpAudioControl = BrowserHfpAudioControl(
        enabled: _config.enableHfpAudio,
        audioInput: phoneMicrophoneInput,
      );
    } else {
      nativeHfpAudioControl = MethodChannelHfpAudioControl(
        enabled: supportsNativeBluetooth && _config.enableHfpAudio,
      );
      rawHfpAudioControl = nativeHfpAudioControl;
    }
    final hfpAudioRouteCoordinator = HfpAudioRouteCoordinator(
      rawHfpAudioControl,
      // MAIN and the destination mount/release on adjacent frames. Retain SCO
      // briefly across this owner gap, then close it when truly idle.
      handoffGrace: supportsAndroidNativeSpeech
          ? const Duration(milliseconds: 750)
          : Duration.zero,
      // Android SpeechRecognizer can restore MODE_NORMAL while SCO stays set.
      revalidateOnAcquire: supportsAndroidNativeSpeech,
    );
    final conversationHfpAudioControl = hfpAudioRouteCoordinator.createScope(
      'continuous-translation',
    );
    final nativeSpeechHfpAudioControl = hfpAudioRouteCoordinator.createScope(
      'native-speech',
    );
    final mainAssistantHfpAudioControl = hfpAudioRouteCoordinator.createScope(
      'main-assistant',
    );
    var nextLearningAudioOwner = 0;
    HfpAudioControl createLearningAudioRouteControl() =>
        hfpAudioRouteCoordinator.createScope(
          'listening-${++nextLearningAudioOwner}',
        );
    final aiv0BleControl = MethodChannelAiv0BleControl(
      enabled: supportsNativeBluetooth && _config.enableAiv0BleControl,
      draftProtocolConfirmed: _config.aiv0DraftProtocolConfirmed,
    );
    final AndroidStreamingSpeechInput? streamingSpeechInput =
        supportsAndroidNativeSpeech
        // MAIN listens for Vietnamese commands. Do not force Android's offline
        // hint here: language-pack setup is optional and may still be pending or
        // unsupported, and several OEM recognizers fail immediately when vi-VN
        // is requested offline without a ready local model. The standard
        // recognizer can still choose an installed local model itself while
        // retaining its network-capable fallback.
        ? AndroidStreamingSpeechInput()
        : supportsAppleNativeSpeech
        ? IOSStreamingSpeechInput(
            audioRouteControl: nativeSpeechHfpAudioControl,
          )
        : null;
    _nativeStreamingSpeechInput = streamingSpeechInput;
    final WebBatchStreamingSpeechInput? webBatchStreamingSpeechInput;
    final StreamingSpeechInput? voiceNavigationSpeechInput;
    final bool voiceNavigationOwnsSpeechInput;
    if (streamingSpeechInput != null) {
      // Android and iOS use the same single native speech pipeline. In
      // particular, iOS MAIN must not silently switch to recorded-audio Batch
      // recognition when Apple Speech or the selected route fails: that hid the
      // original native error and allowed two independent session lifecycles to
      // cancel each other after the assistant prompt.
      webBatchStreamingSpeechInput = null;
      voiceNavigationSpeechInput = streamingSpeechInput;
      voiceNavigationOwnsSpeechInput = false;
    } else if (kIsWeb) {
      webBatchStreamingSpeechInput = WebBatchStreamingSpeechInput(
        audioInput: phoneMicrophoneInput,
        repository: repository,
        childAge: _config.childAge,
      );
      voiceNavigationSpeechInput = webBatchStreamingSpeechInput;
      voiceNavigationOwnsSpeechInput = true;
    } else {
      webBatchStreamingSpeechInput = null;
      voiceNavigationSpeechInput = null;
      voiceNavigationOwnsSpeechInput = false;
    }
    final voiceNavigationController =
        voiceNavigationSpeechInput != null && _config.enableVoiceNavigation
        ? VoiceNavigationController(
            speechInput: voiceNavigationSpeechInput,
            wakeWordEnabled: _config.autoStartVoiceNavigation,
            // Native speech is shared with ConversationController and released
            // explicitly by either controller before the other starts.
            ownsSpeechInput: voiceNavigationOwnsSpeechInput,
            voicePromptService: createVoicePromptService(
              coordinator: audioTurnCoordinator,
              owner: AudioTurnOwner.mainAssistant,
              selectedOutputRoute: supportsNativeBluetooth
                  ? hfpAudioRouteCoordinator.createScope('main-prompt-output')
                  : null,
              useSelectedOutputRoute: () => !_virtualMainPhoneFallback,
            ),
            prepareSelectedOutput: _prepareAndroidMainPromptRoute,
            mainSpeechAudioSource: () => _mainSpeechAudioSourceOverride,
            ownsVoicePromptService: true,
            activeLearningCommandHandler: _handleActiveLearningCommand,
          )
        : null;
    voiceNavigationController?.setChildAge(_config.childAge);
    final controller = ConversationController(
      audioInput: PreferredAudioInput(
        preferred: _config.preferBleStreaming ? innotrikInput : null,
        fallback: phoneMicrophoneInput,
      ),
      streamingSpeechInput: streamingSpeechInput,
      hfpAudioControl: conversationHfpAudioControl,
      learningAudioRouteControlFactory: createLearningAudioRouteControl,
      audioTurnCoordinator: audioTurnCoordinator,
      aiv0BleControl: aiv0BleControl,
      playbackService: JustAudioPlaybackService(
        cache: deviceAudioCache,
        audioTurnCoordinator: audioTurnCoordinator,
        audioTurnOwner: AudioTurnOwner.continuousTranslation,
      ),
      voicePromptService: createVoicePromptService(
        coordinator: audioTurnCoordinator,
        owner: AudioTurnOwner.continuousTranslation,
        selectedOutputRoute: supportsNativeBluetooth
            ? hfpAudioRouteCoordinator.createScope('translation-prompt-output')
            : null,
      ),
      repository: repository,
      offlineIntentRecognizer: supportsAndroidNativeSpeech
          ? MethodChannelOfflineIntentRecognizer()
          : null,
      offlineVietnameseSpeechRecognizer: supportsAndroidNativeSpeech
          ? const AndroidVoskVietnameseSpeechRecognizer()
          : null,
      offlineVietnameseEnglishTranslator: supportsNativeSpeech
          ? _offlineTranslator
          : null,
      offlineEnglishVietnameseTranslator: supportsNativeSpeech
          ? _offlineVocabularyTranslator
          : null,
      vietnameseTranscriptCorrector: supportsNativeSpeech
          ? AssetVietnameseTranscriptCorrector()
          : null,
      onVadSilenceRequested: (value) =>
          unawaited(_settingsBloc.dispatch(SettingsVadSilenceChanged(value))),
      onDisplayLanguageRequested: (value) =>
          unawaited(_settingsBloc.dispatch(SettingsLanguageChanged(value))),
      childAge: _config.childAge,
      preferBleStreaming: _config.preferBleStreaming,
      realtimeBatchFallback: _config.realtimeBatchFallback,
      realtimeFallbackBufferBytes: _config.realtimeFallbackBufferBytes,
      // Open the Batch session on the record gesture on every browser so
      // session creation and chunk upload overlap the child's whole utterance.
      // No-speech turns are discarded by the adaptive upload gate.
      adaptiveWebUploadDelay: Duration.zero,
      initialAsrMode: supportsNativeSpeech
          ? AsrMode.androidStreaming
          : AsrMode.batchChunks,
      // Keep continuous translation on Android's live SpeechRecognizer path.
      // Recording a WAV first and injecting it only after stop adds the 4-5s
      // delay reported on devices. Android never uses cloud ASR as a fallback;
      // the backend still handles text translation and speech synthesis.
      recordAndroidAudioForArchive: false,
      voiceDataProcessingAllowed: () => _voiceAccessEnabled,
      networkTransportAvailable: NetworkAvailability.hasTransport,
      beforeRecordingStart: () async {
        // A MAIN translation handoff arrives only after navigation ASR has
        // finalized its command. Calling pause() from inside that same finish
        // callback waits on itself and can cancel the newly opening Android
        // recognizer. Manual conversation turns still drain navigation first.
        if (_mainSpeakingSessionController.isActive) return;
        await voiceNavigationController?.pause();
      },
      recognizedSpeechCommandMatcher: _matchesMainSpeakingCommand,
      onRecognizedSpeechCommand: _handleMainSpeakingCommand,
    );
    final mainButtonCoordinator = MainButtonCoordinator(
      onScreenShortPress: _handleUnifiedMainShortPress,
      onBleShortPress: _handleUnifiedMainShortPress,
      onLongPress: _handleMainLongPress,
    );
    controller.setMainButtonDispatcher(mainButtonCoordinator.handle);
    _mainButtonCoordinator = mainButtonCoordinator;
    _deviceControlDispatcher = AivoControlDispatcher(
      registry: _activeLearningModules,
      onMain: mainButtonCoordinator.handle,
      onPause: _handleMainLongPress,
      canExecute: () {
        final allowed = _startupReady && _voiceAccessEnabled;
        if (!allowed) {
          final reason = !_startupReady
              ? 'startup_not_ready'
              : !_privacyConsentGranted
              ? 'parental_consent_missing'
              : 'microphone_permission_missing';
          debugPrint(
            'HM-D001 CONTROL BLOCKED: reason=$reason '
            'startupReady=$_startupReady '
            'privacyConsent=$_privacyConsentGranted '
            'limitedMode=$_limitedModeSelected '
            'microphoneGranted=$_microphonePermissionGranted',
          );
        }
        return allowed;
      },
      canResume: () =>
          !_isActivatingMainAssistant &&
          !(_voiceNavigationController?.isMainButtonSessionActive ?? false) &&
          !(_voiceNavigationController?.isActive ?? false),
      onModuleHandled: _appFlowCoordinator.forgetPausedModule,
      platform: defaultTargetPlatform.name,
      operationTimeout: const Duration(seconds: 30),
      onContextChanged: (learning, diagnostics) =>
          aiv0BleControl.setControlContext(
            learningActive: learning,
            diagnosticsActive: diagnostics,
          ),
    );
    _activeLearningModules.addListener(_syncHardwareControlContext);
    controller.setHardwareControlDispatcher((event) async {
      final input = AivoControlInput.fromBle(event);
      final result = await _deviceControlDispatcher.dispatch(input);
      // The legacy MAIN result collapses unavailable/duplicate into ignored.
      // Preserve the real dispatcher result before mapping it for APP State.
      debugPrint(
        'HM-D001 CONTROL: source=${input.source.name} '
        'button=${input.button.name} gesture=${input.gesture.name} '
        'protocol=${input.protocol} seq=${input.sequence ?? "-"} '
        'actionable=${input.actionable} duplicate=${input.duplicate} '
        'result=${result.name} '
        'diagnosticsActive=${_deviceControlDispatcher.diagnosticsActive} '
        'executeTests=${_deviceControlDispatcher.executeTests}',
      );
      return switch (result) {
        AivoControlStatus.accepted => MainButtonActionResult.accepted,
        AivoControlStatus.busy ||
        AivoControlStatus.failed => MainButtonActionResult.busy,
        _ => MainButtonActionResult.ignored,
      };
    });
    _repository = repository;
    _deviceAudioCache = deviceAudioCache;
    _phoneMicrophoneInput = phoneMicrophoneInput;
    _aiv0BleControl = aiv0BleControl;
    _aiv0BleStatusSubscription = aiv0BleControl.statusStream.listen(
      _handleAiv0BleStatus,
    );
    _nativeHfpAudioControl = nativeHfpAudioControl;
    _mainAssistantHfpAudioControl = mainAssistantHfpAudioControl;
    _audioTurnCoordinator = audioTurnCoordinator;
    _audioTurnDiagnosticSubscription = audioTurnCoordinator.diagnostics.listen(
      (_) => _synchronizeDeviceConnections(),
    );
    _hfpAudioRouteCoordinator = hfpAudioRouteCoordinator;
    _webBatchStreamingSpeechInput = webBatchStreamingSpeechInput;
    _controller = controller;
    if (widget.useDeviceConnectionService &&
        !kIsWeb &&
        _config.enableAiv0BleControl &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      _onboardingDevice = DeviceDependencies(
        port: LegacyDeviceConnectionPort(
          ble: aiv0BleControl,
          audio: nativeHfpAudioControl,
          controller: controller,
          android: defaultTargetPlatform == TargetPlatform.android,
          prepare: _prepareOnboardingDeviceAccess,
        ),
      );
    }
    _voiceNavigationController = voiceNavigationController;
    voiceNavigationController?.addListener(_synchronizeMainAssistantSession);
    controller.addListener(_synchronizeMainSpeakingSession);
    controller.addListener(_synchronizeDeviceConnections);
  }

  void _startBackgroundWork() {
    if (_backgroundWorkStarted) {
      return;
    }
    _backgroundWorkStarted = true;
    final nativeStreamingSpeechInput = _nativeStreamingSpeechInput;
    if (nativeStreamingSpeechInput != null && !_usesIosHfpLifecycle) {
      // Android may safely prepare SpeechRecognizer in the background. Apple
      // Speech owns a separate system permission prompt, so iOS waits for an
      // actual MAIN/recording action before asking the user.
      unawaited(nativeStreamingSpeechInput.prewarm());
    }
    final repository = _repository;
    final controller = _controller;
    final deviceAudioCache = _deviceAudioCache;
    if (repository == null || controller == null || deviceAudioCache == null) {
      return;
    }
    final supportsAndroidNativeSpeech =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    if (supportsAndroidNativeSpeech && !_config.useDemoBackend) {
      final registrationService = DeviceRegistrationService(
        config: _config,
        clientIdProvider: _clientIdentity.getClientId,
        clientIdResetter: _clientIdentity.resetClientId,
        hardwareProvider: const AndroidDeviceHardwareReader().read,
      );
      _deviceRegistrationService = registrationService;
      unawaited(_registerDevice(registrationService));
    }
    if (!kIsWeb) {
      unawaited(
        _warmRecentAudioWhenIdle(repository, deviceAudioCache, controller),
      );
    }
  }

  void _setThemeMode(ThemeMode mode) =>
      unawaited(_settingsBloc.dispatch(SettingsThemeChanged(mode)));

  Future<bool> _activateMainAssistant({
    String? inputLabelOverride,
    bool promptAlreadySpoken = false,
    String? noSpeechRetryPrompt,
    String? noSpeechExitPrompt,
  }) async {
    if (_isStoppingSpeakingSession) return false;
    final voiceController = _voiceNavigationController;
    final conversationController = _controller;
    if (voiceController == null || conversationController == null) {
      return false;
    }
    final activated = await _mainAssistantSession.activate(
      startupReady: _startupReady,
      voiceAccessEnabled: _voiceAccessEnabled,
      // isBusy also covers the HM-D001 scan/connect phases, which own no audio.
      // A MAIN press during that search starts the assistant on the phone
      // microphone instead of being dropped without feedback.
      conversationBusy:
          conversationController.isRecordingStartBlocked ||
          conversationController.isPlaybackPlaying,
      assistantFlowBusy: _mainSpeakingSessionController.isActive,
      mainButtonSessionActive: voiceController.isMainButtonSessionActive,
      canContinue: () => mounted,
      prepareActivation: () async {
        final ready = await _prepareAndroidMainHfpRoute();
        if (!ready && mounted && _mainAssistantSession.isActivationPending) {
          conversationController.showHomiConnectionMessage(
            'Chưa kết nối đủ nút MAIN và micro HM-D001. Hãy bật HM-D001 rồi thử lại.',
          );
        }
        return ready;
      },
      activateVoice: ({required activeLearning, required activeLearningKind}) =>
          voiceController.activateFromMainButton(
            activeLearning: activeLearning,
            activeLearningKind: activeLearningKind,
            activeVoiceContext:
                _activeLearningModules.controller is ActiveLearningVoiceContext
                ? _activeLearningModules.controller
                      as ActiveLearningVoiceContext
                : null,
            inputLabelOverride: inputLabelOverride,
            promptAlreadySpoken: promptAlreadySpoken,
            noSpeechRetryPrompt: noSpeechRetryPrompt,
            noSpeechExitPrompt: noSpeechExitPrompt,
          ),
    );
    if (!activated) {
      unawaited(_releaseAndroidMainHfpRouteIfIdle());
    }
    return activated;
  }

  /// Route check before every MAIN prompt. A module's follow-up question
  /// (Topic, lesson or vocabulary choice) starts after the MAIN turn that
  /// opened the module has ended and released its route, so the on-screen
  /// handset fallback is gone by then. Choose the follow-up route again;
  /// otherwise Android refuses the prompt without a ready HM-D001 and the child
  /// gets no microphone.
  Future<bool> _prepareAndroidMainPromptRoute() {
    final route = MainButtonActivationPolicy.followUpAudioRoute(
      isAndroid: !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
      isHomiReady: _controller?.isHomiReady == true,
      isHomiAudioReady: _controller?.isHomiAudioReady == true,
      hasSelectedHfpInput:
          _controller?.hasSelectedHfpInput == true ||
          _controller?.usesHfpInput == true,
    );
    if (route == MainButtonAudioRoute.unavailable) {
      return Future<bool>.value(false);
    }
    if (route == MainButtonAudioRoute.phoneMicrophone &&
        !_androidMainHfpRouteHeld) {
      _virtualMainPhoneFallback = true;
      return Future<bool>.value(true);
    }
    if (route == MainButtonAudioRoute.selectedHfp &&
        defaultTargetPlatform == TargetPlatform.android) {
      _virtualMainPhoneFallback = false;
    }
    return _prepareAndroidMainHfpRoute();
  }

  Future<bool> _prepareAndroidMainHfpRoute() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return Future<bool>.value(true);
    }
    // A build with both HM-D001 transports disabled has no route to prepare; MAIN
    // (including the on-screen button) then uses the phone speaker and mic.
    if (!_config.enableAiv0BleControl && !_config.enableHfpAudio) {
      return Future<bool>.value(true);
    }
    // Temporary tester path: an on-screen MAIN turn may use the handset when
    // HM-D001 is absent. Physical MAIN and connected HM-D001 keep their existing route.
    if (_virtualMainPhoneFallback) {
      return Future<bool>.value(true);
    }
    if (_androidMainHfpRouteHeld &&
        _controller?.hfpAudioStatus.routeActive == true) {
      return Future<bool>.value(true);
    }
    final pending = _androidMainHfpRoutePreparation;
    if (pending != null) return pending;
    final operation = _runAndroidMainHfpRoutePreparation();
    _androidMainHfpRoutePreparation = operation;
    return operation.whenComplete(() {
      if (identical(_androidMainHfpRoutePreparation, operation)) {
        _androidMainHfpRoutePreparation = null;
      }
    });
  }

  Future<bool> _runAndroidMainHfpRoutePreparation() async {
    final controller = _controller;
    final route = _mainAssistantHfpAudioControl;
    if (controller == null || route == null) return false;

    if (!controller.isHomiAudioReady && !controller.canUseAiv0Ble) {
      _lastAiv0AutoConnectAttempt = null;
      await _autoConnectHomiBle();
    } else if (!controller.isHomiAudioReady) {
      await _autoSelectConnectedAndroidHfp();
    }
    if (!controller.isHomiAudioReady) {
      return false;
    }

    try {
      await route.startAudioRoute().timeout(const Duration(seconds: 7));
      final status = controller.hfpAudioStatus;
      if (!status.routeActive || !status.isConnected) {
        throw const HfpAudioException(
          'Android chưa xác nhận đường loa và micro HM-D001.',
        );
      }
      _androidMainHfpRouteHeld = true;
      return true;
    } catch (error) {
      _androidMainHfpRouteHeld = false;
      await route.stopAudioRoute().catchError((Object _) {});
      debugPrint(
        'MAIN did not start because HM-D001 HFP was unavailable: $error',
      );
      return false;
    }
  }

  Future<void> _releaseAndroidMainHfpRouteIfIdle() async {
    if (!_androidMainHfpRouteHeld ||
        _androidMainHfpRoutePreparation != null ||
        _mainAssistantSession.isActivationPending ||
        (_voiceNavigationController?.isMainButtonSessionActive ?? false) ||
        (_voiceNavigationController?.isActive ?? false) ||
        _mainSpeakingSessionController.isActive) {
      return;
    }
    _androidMainHfpRouteHeld = false;
    await _mainAssistantHfpAudioControl?.stopAudioRoute().catchError((
      Object error,
    ) {
      debugPrint('Cannot release MAIN HM-D001 route: $error');
    });
  }

  Future<MainButtonActionResult> _handleUnifiedMainShortPress(
    MainButtonInputEvent event,
  ) async {
    if (_isStoppingSpeakingSession) return MainButtonActionResult.busy;
    final controller = _controller;
    controller?.recordAiv0MainDiagnostic(
      'MAIN_APP_HANDLER_ENTER',
      values: <String, Object?>{
        'source': event.source.name,
        'sequence': event.sequence ?? 0,
        'startupReady': _startupReady,
        'voiceAccessEnabled': _voiceAccessEnabled,
        'mainSpeakingState': _mainSpeakingSessionController.state.name,
        'activatingAssistant': _isActivatingMainAssistant,
        'finishingSpeakingMode': _isFinishingMainSpeakingMode,
      },
    );
    if (!_startupReady || !_voiceAccessEnabled) {
      controller?.recordAiv0MainDiagnostic(
        'MAIN_APP_HANDLER_REJECTED',
        message: 'startup_or_voice_access_not_ready',
      );
      return MainButtonActionResult.busy;
    }
    if (!MainButtonActivationPolicy.canStart(
      isActivationPending: _isActivatingMainAssistant,
      isMainButtonSessionActive:
          _voiceNavigationController?.isMainButtonSessionActive ?? false,
    )) {
      controller?.recordAiv0MainDiagnostic(
        'MAIN_APP_HANDLER_REJECTED',
        message: 'main_assistant_already_active',
      );
      return MainButtonActionResult.busy;
    }
    final route = MainButtonActivationPolicy.audioRoute(
      source: event.source,
      isNativeMobile:
          !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS),
      isIos: _usesIosHfpLifecycle,
      isHomiReady: controller?.isHomiReady == true,
      isHomiAudioReady: controller?.isHomiAudioReady == true,
      hasSelectedHfpInput:
          controller?.hasSelectedHfpInput == true ||
          controller?.usesHfpInput == true,
    );
    if (route == MainButtonAudioRoute.unavailable) {
      controller?.recordAiv0MainDiagnostic(
        'MAIN_APP_HANDLER_REJECTED',
        message: 'selected_homi_microphone_not_ready',
      );
      controller?.showHomiConnectionMessage(
        'Chưa kết nối đủ nút MAIN và micro HM-D001. Hãy bật HM-D001 rồi thử lại.',
      );
      return MainButtonActionResult.busy;
    }
    _virtualMainPhoneFallback = route == MainButtonAudioRoute.phoneMicrophone;
    // Pin the selected source throughout an iOS MAIN turn. A route loss after
    // this gate must fail HFP recognition rather than switch to the phone mic.
    _mainSpeechAudioSourceOverride = _usesIosHfpLifecycle
        ? _virtualMainPhoneFallback
              ? NativeSpeechAudioSource.builtInMic
              : NativeSpeechAudioSource.hfp
        : null;
    // Both buttons share the assistant lifecycle. Only the temporary tester
    // fallback changes the route for on-screen MAIN without HM-D001.
    controller?.recordAiv0MainDiagnostic(
      'MAIN_APP_PATH_SELECTED',
      message: _mainSpeakingSessionController.isActive
          ? 'interrupt_continuous_translation'
          : 'activate_main_assistant',
    );
    final activated = _mainSpeakingSessionController.isActive
        ? await _interruptContinuousTranslationWithMain()
        : await _activateMainAssistant();
    if (!activated) {
      _virtualMainPhoneFallback = false;
      _mainSpeechAudioSourceOverride = null;
    }
    controller?.recordAiv0MainDiagnostic(
      'MAIN_APP_HANDLER_COMPLETED',
      values: <String, Object?>{'activated': activated},
    );
    if (!activated && _restoreHfpAfterPhysicalMain) {
      unawaited(_restoreHfpSelectionAfterPhysicalMain());
    }
    if (!activated && event.source == MainButtonSource.ble) {
      _releasePhysicalMainBleSuppression();
    }
    return activated
        ? MainButtonActionResult.accepted
        : MainButtonActionResult.busy;
  }

  Future<bool> _interruptContinuousTranslationWithMain() async {
    final voiceController = _voiceNavigationController;
    final controller = _controller;
    if (voiceController == null ||
        controller == null ||
        _isActivatingMainAssistant ||
        _isFinishingMainSpeakingMode) {
      controller?.recordAiv0MainDiagnostic(
        'MAIN_INTERRUPT_REJECTED',
        values: <String, Object?>{
          'voiceControllerAvailable': voiceController != null,
          'activatingAssistant': _isActivatingMainAssistant,
          'finishingSpeakingMode': _isFinishingMainSpeakingMode,
        },
      );
      return false;
    }

    _isFinishingMainSpeakingMode = true;
    final canContinue = _mainAssistantSession.captureCancellationGuard();
    _hasMainSpeakingTurnStarted = false;
    _mainSpeakingFallbackFlow.reset();
    if (mounted) {
      _mainAssistantSession.setExternalActivation(true);
    }
    try {
      controller.recordAiv0MainDiagnostic('MAIN_INTERRUPT_STARTED');
      return await _mainSpeakingSessionController.interruptForMainAssistant(
        cancelCurrentAction: () async {
          // MAIN is the explicit cancellation boundary. Do not finalize or
          // translate the interrupted sentence before opening the menu.
          final action = await controller.cancelCurrentMainAction();
          if (!mounted || !canContinue()) return false;
          _invalidateMainSpeakingHfpPreparation();
          await controller.endContinuousHfpSession();
          if (!mounted || !canContinue()) return false;
          controller.recordAiv0MainDiagnostic(
            'MAIN_INTERRUPT_CANCEL_COMPLETED',
            values: <String, Object?>{'result': action.name},
          );
          controller.clearMessage();
          return canContinue() && action != MainButtonActionResult.busy;
        },
        activateAssistant: () async {
          if (!mounted || !canContinue()) return false;
          controller.recordAiv0MainDiagnostic(
            'MAIN_INTERRUPT_ASSISTANT_STARTING',
          );
          final routeReady = await _prepareAndroidMainHfpRoute();
          if (!mounted || !canContinue()) {
            unawaited(_releaseAndroidMainHfpRouteIfIdle());
            return false;
          }
          if (!routeReady) {
            controller.showHomiConnectionMessage(
              'Micro HM-D001 chưa sẵn sàng. Hãy kết nối lại thiết bị rồi nhấn MAIN.',
            );
            return false;
          }
          final activated = await voiceController
              .activateOtherLearningFromSpeaking();
          controller.recordAiv0MainDiagnostic(
            'MAIN_INTERRUPT_ASSISTANT_COMPLETED',
            values: <String, Object?>{'activated': activated},
          );
          return activated;
        },
      );
    } finally {
      _isFinishingMainSpeakingMode = false;
      if (canContinue()) _mainAssistantSession.setExternalActivation(false);
    }
  }

  Future<ActiveLearningCommandResult> _handleActiveLearningCommand(
    ActiveLearningCommand command,
  ) => _appFlowCoordinator.execute(
    command,
    onUnhandledReply: (reply) async {
      await _controller?.speakAssistantPrompt(reply);
    },
  );

  void _synchronizeMainAssistantSession() {
    final voiceController = _voiceNavigationController;
    if (voiceController == null) {
      return;
    }
    if (!voiceController.isMainButtonSessionActive &&
        !_isActivatingMainAssistant) {
      _virtualMainPhoneFallback = false;
      _mainSpeechAudioSourceOverride = null;
    }
    if (!voiceController.isMainButtonSessionActive &&
        !voiceController.isActive) {
      if (!_isActivatingMainAssistant) {
        _releasePhysicalMainBleSuppression();
      }
      if (_restoreHfpAfterPhysicalMain &&
          !_mainSpeakingSessionController.isActive) {
        unawaited(_restoreHfpSelectionAfterPhysicalMain());
      }
      if (_appFlowCoordinator.activeModulePausedForMain &&
          !_isActivatingMainAssistant) {
        unawaited(_resumeActiveModuleAfterMain());
      }
      unawaited(_releaseAndroidMainHfpRouteIfIdle());
    }
  }

  void _releasePhysicalMainBleSuppression({bool reconnect = true}) {
    if (_suppressHomiAutoConnectUntil == null) {
      return;
    }
    _suppressHomiAutoConnectUntil = null;
    _lastAiv0AutoConnectAttempt = null;
    if (!reconnect ||
        !mounted ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    Future<void>.delayed(const Duration(milliseconds: 250), () {
      if (!mounted ||
          (_voiceNavigationController?.isActive ?? false) ||
          (_voiceNavigationController?.isMainButtonSessionActive ?? false)) {
        return;
      }
      unawaited(_autoConnectHomiBle());
    });
  }

  Future<void> _restoreHfpSelectionAfterPhysicalMain() async {
    if (!_restoreHfpAfterPhysicalMain ||
        _isRestoringHfpAfterPhysicalMain ||
        !_canRestoreHfpAfterMainFlow ||
        !mounted) {
      return;
    }
    _isRestoringHfpAfterPhysicalMain = true;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (!_canRestoreHfpAfterMainFlow) {
        return;
      }
      final controller = _controller;
      final ble = _aiv0BleControl;
      if (controller == null ||
          ble == null ||
          controller.isBusy ||
          !controller.canUseAiv0Ble) {
        return;
      }
      for (var attempt = 0; attempt < 3; attempt += 1) {
        if (attempt > 0) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        if (!_canRestoreHfpAfterMainFlow) {
          return;
        }
        final restored = await controller.autoConnectHomiHfp(
          bleDeviceName:
              ble.status.deviceName ?? controller.aiv0BleStatus.deviceName,
        );
        if (restored) {
          _restoreHfpAfterPhysicalMain = false;
          return;
        }
      }
    } finally {
      _isRestoringHfpAfterPhysicalMain = false;
    }
  }

  bool get _canRestoreHfpAfterMainFlow {
    final voiceController = _voiceNavigationController;
    final conversationController = _controller;
    return !_mainSpeakingSessionController.isActive &&
        !_isStartingMainSpeakingTurn &&
        !_isFinishingMainSpeakingMode &&
        !_isHandlingMainSpeakingNoSpeech &&
        !_isActivatingMainAssistant &&
        !(conversationController?.isBusy ?? false) &&
        !(conversationController?.isPlaybackPlaying ?? false) &&
        !(voiceController?.isMainButtonSessionActive ?? false) &&
        !(voiceController?.isActive ?? false);
  }

  void _synchronizePendingMainSpeakingAudioHandoff() {
    if (mounted) setState(() {});
    if (!_mainSpeakingSessionController.isActive &&
        _restoreHfpAfterPhysicalMain) {
      unawaited(_restoreHfpSelectionAfterPhysicalMain());
    }
    if (!_mainSpeakingSessionController.isActive) {
      unawaited(_releaseAndroidMainHfpRouteIfIdle());
    }
  }

  Future<void> _resumeActiveModuleAfterMain() async {
    await _appFlowCoordinator.resumeAfterMainAssistant();
  }

  Future<MainButtonActionResult> _handleMainLongPress(
    MainButtonInputEvent event,
  ) async {
    if (!_startupReady) {
      return MainButtonActionResult.busy;
    }
    final cancelledActivation = _mainAssistantSession.isActivationPending;
    // LONG has priority over pending route preparation / lesson cleanup.
    // Invalidate that activation before awaiting anything so it cannot later
    // open a microphone after the user has already requested a pause.
    _mainAssistantSession.cancelForNavigation();
    final voiceController = _voiceNavigationController;
    if (voiceController?.isMainButtonSessionActive ?? false) {
      // Keep an interrupted lesson paused. Otherwise the controller listener
      // would resume it while the child is still hearing "Đã dừng.".
      _appFlowCoordinator.forgetPausedModule();
      await voiceController!.pause();
      await _controller?.speakAssistantPrompt('Đã dừng.');
      return MainButtonActionResult.accepted;
    }

    final learningResult = await _pauseActiveLearningFromLongPress();
    if (learningResult != null) {
      if (cancelledActivation &&
          learningResult == MainButtonActionResult.ignored) {
        return MainButtonActionResult.accepted;
      }
      return learningResult;
    }

    final controller = _controller;
    if (controller == null) {
      return MainButtonActionResult.ignored;
    }
    final endedMainSpeakingSession = _mainSpeakingSessionController.isActive;
    if (endedMainSpeakingSession) {
      _hasMainSpeakingTurnStarted = false;
      _mainSpeakingFallbackFlow.reset();
      _mainSpeakingSessionController.exit();
      _invalidateMainSpeakingHfpPreparation();
    }
    final result = await controller.stopCurrentMainAction();
    if (endedMainSpeakingSession) {
      await controller.endContinuousHfpSession();
    }
    if (result != MainButtonActionResult.ignored) {
      await controller.speakAssistantPrompt('Đã dừng.');
      return result;
    }
    if (endedMainSpeakingSession) {
      await controller.speakAssistantPrompt('Đã dừng.');
      if (_restoreHfpAfterPhysicalMain) {
        unawaited(_restoreHfpSelectionAfterPhysicalMain());
      }
      return MainButtonActionResult.accepted;
    }

    return cancelledActivation
        ? MainButtonActionResult.accepted
        : MainButtonActionResult.ignored;
  }

  Future<MainButtonActionResult?> _pauseActiveLearningFromLongPress() async {
    if (!_activeLearningModules.hasActiveModule) {
      return null;
    }

    if (_activeLearningModules.isActiveModulePaused) {
      // LONG is pause-only. SHORT resumes through the shared dispatcher.
      return MainButtonActionResult.ignored;
    }

    final stopped = await _activeLearningModules.execute(
      ActiveLearningCommand.stop,
    );
    if (!stopped.wasHandled) {
      return MainButtonActionResult.ignored;
    }
    _appFlowCoordinator.forgetPausedModule();
    await _controller?.speakAssistantPrompt('Đã dừng.');
    return MainButtonActionResult.accepted;
  }

  Future<void> _handleScreenMainLongPress() async {
    await _dispatchScreenControl(Aiv0ButtonGesture.longPress);
  }

  Future<void> _handleScreenMainShortPress() async {
    await _dispatchScreenControl(Aiv0ButtonGesture.shortPress);
  }

  Future<void> _dispatchScreenControl(Aiv0ButtonGesture gesture) async {
    await _deviceControlDispatcher.dispatch(
      AivoControlInput(
        source: AivoControlSource.virtualButton,
        button: Aiv0Button.main,
        gesture: gesture,
        occurredAt: DateTime.now(),
        actionable: true,
        protocol: 'virtual',
      ),
    );
  }

  void _syncHardwareControlContext() =>
      unawaited(_deviceControlDispatcher.syncNativeContext());

  Future<void> _handleScreenMainRelease() async {
    await _mainButtonCoordinator.handle(
      const MainButtonInputEvent(
        source: MainButtonSource.screen,
        gesture: MainButtonGesture.release,
      ),
    );
  }

  Future<void> _requestVocabularyVoiceChoice({
    String? noSpeechRetryPrompt,
    String? noSpeechExitPrompt,
  }) async {
    // The MAIN turn that opened the vocabulary has already ended, which
    // cleared its handset fallback. Choose the route again for this follow-up
    // question so a phone without a ready HM-D001 still opens a microphone.
    final route = MainButtonActivationPolicy.followUpAudioRoute(
      isAndroid: !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
      isHomiReady: _controller?.isHomiReady == true,
      isHomiAudioReady: _controller?.isHomiAudioReady == true,
      hasSelectedHfpInput:
          _controller?.hasSelectedHfpInput == true ||
          _controller?.usesHfpInput == true,
    );
    if (route == MainButtonAudioRoute.unavailable) return;
    final usesPhone = route == MainButtonAudioRoute.phoneMicrophone;
    _virtualMainPhoneFallback = usesPhone;
    final activated = await _activateMainAssistant(
      promptAlreadySpoken: true,
      noSpeechRetryPrompt: noSpeechRetryPrompt,
      noSpeechExitPrompt: noSpeechExitPrompt,
    );
    if (!activated && usesPhone) {
      _virtualMainPhoneFallback = false;
    }
  }

  Future<void> _startMainSpeakingMode() async {
    if (!_voiceAccessEnabled || _isStoppingSpeakingSession) {
      return;
    }
    // A stable partial and the final native transcript can both resolve the
    // same accepted command before navigation fully settles. The first transfer
    // enters synchronously, so a duplicate must reuse that session instead of
    // opening a second iOS HFP lease. Otherwise the stale preparation can close
    // the newer lease and leave the conversation screen visible without a mic.
    if (_mainSpeakingSessionController.isActive) {
      _synchronizeMainSpeakingSession();
      return;
    }
    // A navigation choice that leaves listening is a transfer, not a temporary
    // MAIN interruption. Do not let the paused lesson resume after the
    // conversation screen has already taken ownership of audio.
    _appFlowCoordinator.forgetPausedModule();
    if (!mounted || !_voiceAccessEnabled) {
      return;
    }
    _hasMainSpeakingTurnStarted = false;
    _isHandlingMainSpeakingNoSpeech = false;
    // A prior confirmation may have been interrupted by MAIN, a long press,
    // or the idle timeout. Never let it consume the first sentence of a new
    // continuous-translation session.
    _mainSpeakingFallbackFlow.reset();
    _voiceNavigationController?.clearStoppedTranslationContext();
    _mainSpeakingSessionController.enter();
    if (!_usesIosHfpLifecycle) {
      // Preserve the established Android lifecycle from main. Android opens
      // its HFP/SpeechRecognizer route per turn; only iOS needs one explicit
      // continuous AVAudioSession lease before the first turn.
      await _startNextMainSpeakingTurn();
      return;
    }
    final generation = ++_mainSpeakingHfpSessionGeneration;
    _isPreparingMainSpeakingHfpSession = true;
    await _prepareMainSpeakingHfpSession(generation);
  }

  Future<void> _prepareMainSpeakingHfpSession(int generation) async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.beginContinuousHfpSession();
      // A superseded preparation must not close a shared lease while a newer
      // continuous-translation activation still owns it.
      if (!_mainSpeakingSessionController.isActive) {
        await controller.endContinuousHfpSession();
      }
    } finally {
      if (generation == _mainSpeakingHfpSessionGeneration) {
        _isPreparingMainSpeakingHfpSession = false;
        _synchronizeMainSpeakingSession();
      }
    }
  }

  void _invalidateMainSpeakingHfpPreparation() {
    _mainSpeakingHfpSessionGeneration += 1;
    _isPreparingMainSpeakingHfpSession = false;
  }

  void _synchronizeMainSpeakingSession() {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    // A real HFP profile loss ends the session. Idle SCO release and a missing
    // BLE MAIN link do not, since both leave the selected mic connected.
    if (_mainSpeakingSessionController.isActive &&
        controller.usesHfpInput &&
        !controller.hfpAudioStatus.isConnected &&
        !controller.hfpAudioStatus.isBusy) {
      unawaited(_finishMainSpeakingMode(sayGoodbye: false));
      return;
    }
    _mainSpeakingSessionController.synchronize(
      isRecording: controller.isRecording,
      isBusy: controller.isRecordingStartBlocked,
      isPlaying: controller.isPlaybackPlaying,
    );
    if (!_mainSpeakingSessionController.isActive ||
        _isPreparingMainSpeakingHfpSession ||
        _isFinishingMainSpeakingMode ||
        _isHandlingMainSpeakingNoSpeech ||
        _isHandlingMainSpeakingCommand) {
      if (!_mainSpeakingSessionController.isActive &&
          _restoreHfpAfterPhysicalMain) {
        unawaited(_restoreHfpSelectionAfterPhysicalMain());
      }
      if (!_mainSpeakingSessionController.isActive &&
          controller.isContinuousHfpSessionActive) {
        _invalidateMainSpeakingHfpPreparation();
        unawaited(controller.endContinuousHfpSession());
      }
      return;
    }

    final turnEndReason = controller.lastTurnEndReason;
    if (turnEndReason == ConversationTurnEndReason.completed) {
      _mainSpeakingSessionController.markSpeechTurnCompleted();
    }
    // Only a command handled inside this session holds it. A reason left over
    // from an earlier session (MAIN pressed during translation, then back to
    // translation) would otherwise block the first iOS turn with no retry.
    if (_hasMainSpeakingTurnStarted &&
        turnEndReason == ConversationTurnEndReason.commandHandled) {
      return;
    }
    if (_hasMainSpeakingTurnStarted &&
        controller.phase == ConversationPhase.idle &&
        (turnEndReason == ConversationTurnEndReason.noSpeech ||
            turnEndReason == ConversationTurnEndReason.tooShort)) {
      unawaited(_handleMainSpeakingNoSpeech());
      return;
    }
    if (_hasMainSpeakingTurnStarted &&
        (controller.phase == ConversationPhase.error ||
            turnEndReason == ConversationTurnEndReason.failed)) {
      unawaited(_finishMainSpeakingMode(sayGoodbye: false));
      return;
    }
    if (_mainSpeakingSessionController.isReady &&
        !_isStartingMainSpeakingTurn) {
      unawaited(_startNextMainSpeakingTurn());
    }
  }

  Future<void> _startNextMainSpeakingTurn() async {
    final controller = _controller;
    if (controller == null ||
        !_mainSpeakingSessionController.isActive ||
        _isPreparingMainSpeakingHfpSession ||
        _isStartingMainSpeakingTurn ||
        _isFinishingMainSpeakingMode ||
        _isHandlingMainSpeakingCommand ||
        controller.isRecordingStartBlocked ||
        controller.isPlaybackPlaying) {
      return;
    }
    if (!controller.isInputAvailable) {
      await _finishMainSpeakingMode(sayGoodbye: false);
      return;
    }

    _isStartingMainSpeakingTurn = true;
    var recordingStarted = false;
    try {
      await controller.startRecording(
        noSpeechTimeout: const Duration(seconds: 6),
        speakNoSpeechPrompt: false,
      );
      recordingStarted = controller.isRecording;

      _hasMainSpeakingTurnStarted = recordingStarted;
    } finally {
      _isStartingMainSpeakingTurn = false;
    }

    if (!recordingStarted && _mainSpeakingSessionController.isActive) {
      await _finishMainSpeakingMode(
        sayGoodbye: true,
        goodbyeText:
            'HOMI chưa mở được micro để dịch liên tục. Bạn kiểm tra quyền micro rồi thử lại nhé.',
      );
    }
  }

  Future<void> _handleMainSpeakingNoSpeech() async {
    final controller = _controller;
    if (controller == null ||
        !_mainSpeakingSessionController.isActive ||
        _isHandlingMainSpeakingNoSpeech ||
        _isFinishingMainSpeakingMode) {
      return;
    }

    _isHandlingMainSpeakingNoSpeech = true;
    _hasMainSpeakingTurnStarted = false;
    final action = _mainSpeakingSessionController.registerNoSpeechTurn();
    var retry = false;
    try {
      if (action == MainSpeakingNoSpeechAction.retry) {
        controller.clearMessage();
        await controller.speakAssistantPrompt(
          'HOMI chưa nghe rõ. Bạn nói lại nhé.',
        );
        retry = true;
      } else {
        await _finishMainSpeakingMode(
          sayGoodbye: true,
          goodbyeText: 'Mình tạm dừng nhé.',
        );
      }
    } finally {
      _isHandlingMainSpeakingNoSpeech = false;
    }

    if (retry &&
        _mainSpeakingSessionController.isActive &&
        !_isFinishingMainSpeakingMode) {
      controller.clearMessage();
      await _startNextMainSpeakingTurn();
    }
  }

  Future<void> _stopSpeakingSessionFromScreen() async {
    if (_isStoppingSpeakingSession) return;
    setState(() => _isStoppingSpeakingSession = true);
    // Invalidate the session before awaiting cleanup. A late transcript,
    // backend reply or microphone-open completion cannot start the next turn.
    _mainAssistantSession.cancelForNavigation();
    _isFinishingMainSpeakingMode = true;
    _hasMainSpeakingTurnStarted = false;
    _mainSpeakingFallbackFlow.reset();
    _mainSpeakingSessionController.exit();
    _invalidateMainSpeakingHfpPreparation();
    try {
      // Invalidate both owners before waiting for either native cleanup. A
      // slow recognizer pause must not let a late conversation response play.
      await Future.wait<void>([
        if (_controller != null)
          _controller!.cancelCurrentMainAction().then<void>((_) {}),
        if (_voiceNavigationController != null)
          _voiceNavigationController!.pause(stopPrompt: true),
      ]);
    } finally {
      await _controller?.endContinuousHfpSession();
      _virtualMainPhoneFallback = false;
      _mainSpeechAudioSourceOverride = null;
      _isFinishingMainSpeakingMode = false;
      await _releaseAndroidMainHfpRouteIfIdle();
      if (mounted) setState(() => _isStoppingSpeakingSession = false);
    }
  }

  Future<void> _finishMainSpeakingMode({
    required bool sayGoodbye,
    String? goodbyeText,
    String? goodbyeAudioKey,
  }) async {
    final controller = _controller;
    if (!_mainSpeakingSessionController.isActive ||
        _isFinishingMainSpeakingMode) {
      return;
    }
    _isFinishingMainSpeakingMode = true;
    _hasMainSpeakingTurnStarted = false;
    _mainSpeakingFallbackFlow.reset();
    _mainAssistantSession.setExternalActivation(true);
    _mainSpeakingSessionController.exit();
    _invalidateMainSpeakingHfpPreparation();
    try {
      await controller?.endContinuousHfpSession();
      if (sayGoodbye && controller != null) {
        controller.clearMessage();
        await controller.speakAssistantPrompt(
          goodbyeText ?? HomiFallbackCatalog.silencePromptById['SIL-004']!,
          audioKey: goodbyeAudioKey,
        );
      }
    } finally {
      _isFinishingMainSpeakingMode = false;
      _mainAssistantSession.setExternalActivation(false);
      if (_restoreHfpAfterPhysicalMain) {
        unawaited(_restoreHfpSelectionAfterPhysicalMain());
      }
    }
  }

  bool _matchesMainSpeakingCommand(String recognizedText) {
    // Stop translation belongs only to the automatic continuous session.
    // A one-shot Vietnamese sentence may naturally contain the same words and
    // must keep flowing through normal translation.
    return _mainSpeakingSessionController.isActive &&
        _mainSpeakingFallbackFlow.canHandle(recognizedText);
  }

  Future<void> _handleMainSpeakingCommand(String recognizedText) async {
    final voiceController = _voiceNavigationController;
    final controller = _controller;
    if (voiceController == null ||
        controller == null ||
        !_mainSpeakingSessionController.isActive ||
        _isFinishingMainSpeakingMode) {
      return;
    }

    final turn = _mainSpeakingFallbackFlow.handle(recognizedText);
    if (turn == null) {
      return;
    }

    _isHandlingMainSpeakingCommand = true;
    try {
      await voiceController.waitForMainAfterTranslationStop();
      await _finishMainSpeakingMode(
        sayGoodbye: true,
        goodbyeText: turn.promptText,
        goodbyeAudioKey: turn.audioKey,
      );
    } finally {
      _isHandlingMainSpeakingCommand = false;
    }
  }

  void _setGlobalModalOpen(bool isOpen) {
    if (!mounted || _isGlobalModalOpen == isOpen) return;
    setState(() => _isGlobalModalOpen = isOpen);
  }

  Future<void> _registerDevice(
    DeviceRegistrationService registrationService,
  ) async {
    try {
      await registrationService.register();
      debugPrint('Android device hardware registered.');
    } catch (error, stackTrace) {
      debugPrint('Android device registration was skipped: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _warmRecentAudioWhenIdle(
    ConversationRepository repository,
    DeviceAudioCache deviceCache,
    ConversationController controller,
  ) async {
    await Future<void>.delayed(const Duration(seconds: 10));
    while (mounted && controller.isBusy) {
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    if (!mounted) {
      return;
    }
    try {
      // Backend warm-up is capped at 200 reviewed rules and runs in the
      // background. It creates each shared TTS asset at most once.
      await repository.warmAudioCache();
      // Keep the child's most useful recent audio on the device as well.
      await _warmCommonRuleAudio(repository, deviceCache);
    } catch (error, stackTrace) {
      debugPrint('Audio cache warm-up was skipped: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _warmCommonRuleAudio(
    ConversationRepository repository,
    DeviceAudioCache deviceCache,
  ) async {
    final history = await repository.fetchHistory();
    const fastSources = <String>{
      'phrase_rule',
      'corpus_rule',
      'keyword_rule',
      'promoted_rule',
      'semantic_cache',
      'text_cache',
    };
    final ranked = <String, ({Uri uri, int score})>{};
    for (var index = 0; index < history.length; index += 1) {
      final item = history[index];
      final uri = item.audioUri;
      if (uri == null || !fastSources.contains(item.textSource)) {
        continue;
      }
      final key = uri.toString();
      final current = ranked[key];
      ranked[key] = (
        uri: uri,
        score: (current?.score ?? 0) + 100 - index.clamp(0, 99).toInt(),
      );
    }
    final commonUris = ranked.values.toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    await deviceCache.warm(commonUris.map((item) => item.uri), limit: 12);
  }

  @override
  void dispose() {
    unawaited(_appDependencies.dispose());
    unawaited(_settingsDependencies.dispose());
    unawaited(_onboardingDevice?.dispose());
    _deviceAttemptGeneration += 1;
    _deviceAttemptCancelled.complete();
    _deviceActionGate.dispose();
    _deviceConnectionCoordinator.dispose();
    _bluetoothPower.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _offlineSpeechModelTimer?.cancel();
    _androidHfpAutoSelectionTimer?.cancel();
    _iosUnifiedConnectionRetryTimer?.cancel();
    _iosBleReconnectNoticeTimer?.cancel();
    unawaited(_aiv0BleStatusSubscription?.cancel());
    unawaited(_audioTurnDiagnosticSubscription?.cancel());
    unawaited(_offlineTranslator.close());
    unawaited(_offlineVocabularyTranslator.close());
    _controller?.removeListener(_synchronizeMainSpeakingSession);
    _controller?.removeListener(_synchronizeDeviceConnections);
    _mainSpeakingSessionController.removeListener(
      _synchronizePendingMainSpeakingAudioHandoff,
    );
    _mainSpeakingSessionController.dispose();
    _voiceNavigationController?.removeListener(
      _synchronizeMainAssistantSession,
    );
    _voiceNavigationController?.dispose();
    _controller?.dispose();
    _deviceRegistrationService?.dispose();
    _deviceAudioCache?.dispose();
    _activeLearningModules.removeListener(_syncHardwareControlContext);
    _deviceControlDispatcher.dispose();
    _activeLearningModules.dispose();
    unawaited(_hfpAudioRouteCoordinator?.dispose());
    unawaited(_audioTurnCoordinator?.dispose());
    _deviceActionState.dispose();
    super.dispose();
  }

  late final _appRouter = createAppRouter();

  @override
  Widget build(BuildContext context) => BlocProvider<AppBloc>.value(
    value: _appBloc,
    child: BlocProvider<SettingsBloc>.value(
      value: _settingsBloc,
      child: BlocBuilder<AppBloc, AppState>(
        builder: (context, state) => BlocBuilder<SettingsBloc, SettingsState>(
          buildWhen: (previous, next) =>
              previous.themeMode != next.themeMode ||
              previous.displayLanguage != next.displayLanguage ||
              previous.childAge != next.childAge,
          builder: (context, settings) => _buildApp(context),
        ),
      ),
    ),
  );

  Widget _buildApp(BuildContext context) {
    final controller = _controller!;

    return MaterialApp(
      onGenerateRoute: _appRouter.onGenerateRoute,
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: _scaffoldMessengerKey,
      navigatorObservers: <NavigatorObserver>[_mainOverlayNavigatorObserver],
      title: 'HOMI App',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      darkTheme: buildDarkAppTheme(),
      themeMode: _themeMode,
      builder: (context, child) {
        final voiceController = _voiceNavigationController;
        return ActiveLearningModuleScope(
          registry: _activeLearningModules,
          onNavigationExit: () {
            _mainAssistantSession.cancelForNavigation();
            unawaited(_voiceNavigationController?.pause());
          },
          child: AivoControlScope(
            controller: _deviceControlDispatcher,
            // Builder content is a sibling of Navigator, so its floating UI
            // cannot use Navigator's Overlay. Keep an Overlay above both.
            child: Overlay.wrap(
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  child ?? const SizedBox.shrink(),
                  if (voiceController != null &&
                      !_isGlobalModalOpen &&
                      !_deviceActionDialogOpen &&
                      _startupReady &&
                      _voiceAccessEnabled &&
                      _showFloatingMainButton)
                    Positioned(
                      right: 16,
                      bottom: 0,
                      child: SafeArea(
                        minimum: const EdgeInsets.only(bottom: 88),
                        child: MainVoiceAssistantButton(
                          voiceController: voiceController,
                          audioState: controller,
                          speakingSessionController:
                              _mainSpeakingSessionController,
                          isActivationPending: _isActivatingMainAssistant,
                          onPressed: _handleScreenMainShortPress,
                          onLongPressed: _handleScreenMainLongPress,
                          onLongPressReleased: _handleScreenMainRelease,
                        ),
                      ),
                    ),
                  if (_iosBleReconnectNoticeVisible)
                    const Positioned(
                      top: 0,
                      left: 16,
                      right: 16,
                      child: SafeArea(
                        bottom: false,
                        child: Center(child: IosBleReconnectNotice()),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
      home: _appBloc.state.status == AppStatus.initializationFailed
          ? Scaffold(
              body: SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          controller.displayLanguage.choose(
                            'Chưa thể khởi động HOMI. Vui lòng thử lại.',
                            '暂时无法启动 HOMI，请重试。',
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          key: const Key('app-startup-retry'),
                          onPressed: _initializeStartupSetup,
                          child: Text(
                            controller.displayLanguage.choose('Thử lại', '重试'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          : _startupReady
          ? AndroidUpdateGate(
              config: _config,
              child: PwaInstallGate(
                child: HomeLearningShell(
                  settingsBloc: _settingsBloc,
                  controller: controller,
                  config: _config,
                  connectionCoordinator: _requiresLearningDevice
                      ? _deviceConnectionCoordinator
                      : null,
                  ensureDeviceConnected: _ensureLearningDeviceConnected,
                  isDeviceConnectionReady: () => _isLearningDeviceReady,
                  voiceNavigationController: _voiceNavigationController,
                  speakingSessionController: _mainSpeakingSessionController,
                  sessionActive:
                      _mainSpeakingSessionController.isActive ||
                      controller.isContinuousHfpSessionActive,
                  isStoppingSession: _isStoppingSpeakingSession,
                  onStopSession: _stopSpeakingSessionFromScreen,
                  themeMode: _themeMode,
                  onThemeModeChanged: _setThemeMode,
                  onChildAgeChanged: _setChildAge,
                  onActiveLearningExitCommitted:
                      _appFlowCoordinator.forgetPausedModule,
                  onMainSpeakingModeStarted: _startMainSpeakingMode,
                  onScreenMainPressed: _voiceAccessEnabled
                      ? _handleScreenMainShortPress
                      : null,
                  onVocabularyVoiceChoiceRequested: _voiceAccessEnabled
                      ? _requestVocabularyVoiceChoice
                      : null,
                  onModalVisibilityChanged: _setGlobalModalOpen,
                  privacyConsentGranted: _privacyConsentGranted,
                  voiceAccessEnabled: _voiceAccessEnabled,
                  onRequestVoiceAccess: () =>
                      unawaited(_requestStartupPermissions()),
                  onManagePrivacyConsent: () => unawaited(_showPrivacySetup()),
                  onRevokePrivacyConsent: _revokePrivacyConsent,
                  onboardingStore:
                      const SharedPreferencesOnboardingProgressStore(),
                ),
              ),
            )
          : AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                final hfpStatus = controller.hfpAudioStatus;
                final bleStatus = controller.aiv0BleStatus;
                Widget buildSetup(
                  DeviceState? deviceState,
                ) => StartupSetupScreen(
                  profileLoading: _startupProfileLoading,
                  permissionRequestInProgress:
                      _startupPermissionRequestInProgress,
                  privacyConfigurationComplete:
                      _config.privacyReleaseConfigurationComplete,
                  privacyConsentGranted: _privacyConsentGranted,
                  limitedModeSelected: _limitedModeSelected,
                  microphoneGranted: _microphonePermissionGranted,
                  bluetoothRequired: _bluetoothPermissionRequired,
                  bluetoothGranted: _bluetoothPermissionGranted,
                  homiBleConnected:
                      deviceState?.snapshot.mainReady ?? bleStatus.isConnected,
                  homiHfpConfigured:
                      deviceState?.snapshot.audioReady ??
                      controller.isHomiAudioReady,
                  homiAudioPaired:
                      deviceState?.snapshot.audioPaired ??
                      _startupHomiAudioPaired,
                  onOpenBluetoothSettings: _openBluetoothSettingsForOnboarding,
                  homiAudioBlocksMain:
                      deviceState?.issue == DeviceIssue.audioBlocksMain,
                  bluetoothPower: _bluetoothPermissionRequired
                      ? _bluetoothPower
                      : null,
                  homiDeviceName: hfpStatus.deviceName ?? bleStatus.deviceName,
                  selectedAge: _pendingStartupAge,
                  aiSubprocessors: _config.disclosedAiSubprocessors,
                  dataRetentionSummary: _config.disclosedDataRetention,
                  privacyPolicyUri: _config.privacyPolicyUri,
                  termsUri: _config.termsUri,
                  supportUri: _config.supportUri,
                  permissionError: deviceState?.issue == null
                      ? _startupPermissionError
                      : _deviceIssueMessage(deviceState!.issue!),
                  androidOfflineEnglishModelOptionAvailable:
                      _supportsOfflineLanguagePacks &&
                      _privacyConsentGranted &&
                      !_limitedModeSelected,
                  androidOfflineEnglishModelDownloadAllowed:
                      _offlineSpeechModelConsent ==
                      AndroidOfflineSpeechModelConsent.allowed,
                  onAndroidOfflineEnglishModelDownloadChanged:
                      _setAndroidOfflineSpeechModelDownload,
                  onGrantPrivacyConsent: _grantPrivacyConsent,
                  onContinueWithoutVoice: _continueWithoutVoice,
                  onCheckPermissions: _checkStartupPermissions,
                  onRetryPermissions: () => unawaited(
                    _requestStartupPermissions(
                      parentInitiated: true,
                      autoConnectHomi:
                          !kIsWeb &&
                          defaultTargetPlatform == TargetPlatform.iOS,
                    ),
                  ),
                  onSetupHomi: _configureHomiForParentSetup,
                  onCancelHomiSetup: _usesOnboardingDeviceService
                      ? () => _onboardingDevice!.bloc.cancelAttempt()
                      : _cancelDeviceConnectionAttempt,
                  onChooseHomiMicrophone: _usesIosHfpLifecycle
                      ? _chooseHomiMicrophoneForParentSetup
                      : null,
                  onAgeSelected: (age) =>
                      setState(() => _pendingStartupAge = age),
                  onCompleteSetup: _completeParentSetup,
                );
                final device = _onboardingDevice;
                if (!_usesOnboardingDeviceService || device == null) {
                  return buildSetup(null);
                }
                return BlocProvider<DeviceBloc>.value(
                  value: device.bloc,
                  child: BlocConsumer<DeviceBloc, DeviceState>(
                    listenWhen: (previous, next) =>
                        next.stage == DeviceStage.choosingMicrophone &&
                        (previous.stage != next.stage ||
                            previous.attempt != next.attempt),
                    listener: (context, state) =>
                        unawaited(_showOnboardingMicrophoneSelection(state)),
                    builder: (context, state) {
                      device.service.diagnostics.state('ui', state);
                      return buildSetup(state);
                    },
                  ),
                );
              },
            ),
    );
  }
}

class _MainOverlayNavigatorObserver extends NavigatorObserver {
  _MainOverlayNavigatorObserver({required this.onVisibilityChanged});

  final ValueChanged<bool> onVisibilityChanged;
  final Set<Route<dynamic>> _pageRoutes = <Route<dynamic>>{};

  void _notify() {
    final topRoute = _pageRoutes.isEmpty ? null : _pageRoutes.last;
    final topName = topRoute?.settings.name;
    final hideFloatingMainButton =
        topName == ListeningRouteNames.topicCatalog ||
        topName == ListeningRouteNames.topicLessons ||
        topName == ListeningRouteNames.lessonPractice;
    onVisibilityChanged(_pageRoutes.length > 1 && !hideFloatingMainButton);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (route is PageRoute<dynamic>) {
      _pageRoutes.add(route);
      _notify();
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (_pageRoutes.remove(route)) {
      _notify();
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    if (_pageRoutes.remove(route)) {
      _notify();
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (oldRoute != null) {
      _pageRoutes.remove(oldRoute);
    }
    if (newRoute is PageRoute<dynamic>) {
      _pageRoutes.add(newRoute);
    }
    _notify();
  }
}
