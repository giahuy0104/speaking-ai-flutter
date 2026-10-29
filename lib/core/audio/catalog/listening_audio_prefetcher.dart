import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import 'audio_pack_repository.dart';

typedef AudioPackRepositoryFactory =
    AudioPackRepository Function(List<String> manifestAssets);

/// Warms the selected age group's lesson audio while the app is open on Wi-Fi.
/// Cached files survive app restarts, so each attempt resumes from missing files.
final class ListeningAudioPrefetcher {
  ListeningAudioPrefetcher({
    Future<bool> Function()? wifiAvailable,
    Stream<bool> Function()? wifiChanges,
    AudioPackRepositoryFactory? repositoryFactory,
    this.retryDelay = const Duration(minutes: 1),
  }) : _wifiAvailable = wifiAvailable ?? _checkWifi,
       _wifiChanges = wifiChanges ?? _watchWifi,
       _repositoryFactory =
           repositoryFactory ??
           ((assets) => AudioPackRepository(bundledManifestAssets: assets));

  final Future<bool> Function() _wifiAvailable;
  final Stream<bool> Function() _wifiChanges;
  final AudioPackRepositoryFactory _repositoryFactory;
  final Duration retryDelay;
  StreamSubscription<bool>? _wifiSubscription;
  Timer? _retryTimer;
  Future<void>? _work;
  String? _ageGroup;
  String? _completedGroup;
  bool _started = false;
  bool _foreground = true;
  bool _checkingWifi = false;
  bool? _wifiConnected;
  int _wifiRevision = 0;
  bool _retryRequested = false;
  bool _disposed = false;

  void start() {
    if (_started || _disposed) return;
    _started = true;
    _wifiSubscription = _wifiChanges().listen((available) {
      _wifiRevision += 1;
      _wifiConnected = available;
      if (available) {
        _retryTimer?.cancel();
        unawaited(_tryPreload());
      } else {
        _retryTimer?.cancel();
      }
    }, onError: (_) {});
    unawaited(_tryPreload());
  }

  void selectAgeGroup(String? ageGroup) {
    if (_ageGroup == ageGroup || _disposed) return;
    _ageGroup = ageGroup;
    _completedGroup = null;
    _retryTimer?.cancel();
    if (_started) unawaited(_tryPreload());
  }

  void pause() {
    _foreground = false;
    _retryTimer?.cancel();
  }

  void resume() {
    _foreground = true;
    if (_started) unawaited(_tryPreload());
  }

  Future<void> _tryPreload() async {
    if (!_started ||
        !_foreground ||
        _disposed ||
        _ageGroup == null ||
        _ageGroup == _completedGroup) {
      return;
    }
    if (_checkingWifi || _work != null) {
      _retryRequested = true;
      return;
    }
    final requestedGroup = _ageGroup;
    _checkingWifi = true;
    try {
      final wifiRevision = _wifiRevision;
      final wifiAvailable = await _wifiAvailable();
      if (_wifiRevision != wifiRevision && _wifiConnected == false) return;
      _wifiConnected = wifiAvailable;
      if (!wifiAvailable) return;
      final group = _ageGroup;
      if (group == null || !_foreground || _disposed || _work != null) return;
      final suffix = group.replaceAll('-', '_');
      final repository = _repositoryFactory(<String>[
        'assets/data/listening_${suffix}_audio.json',
        'assets/data/challenge_${suffix}_audio.json',
      ]);
      final work = _preload(repository, group);
      _work = work;
      await work;
    } catch (_) {
      _scheduleRetry();
    } finally {
      _checkingWifi = false;
      _work = null;
      if (_retryRequested ||
          (_ageGroup != requestedGroup && _ageGroup != _completedGroup)) {
        _retryRequested = false;
        _retryTimer?.cancel();
        unawaited(_tryPreload());
      }
    }
  }

  Future<void> _preload(AudioPackRepository repository, String group) async {
    try {
      final result = await repository.preloadAgeGroup(
        group,
        shouldContinue: () =>
            !_disposed &&
            _foreground &&
            _wifiConnected != false &&
            _ageGroup == group,
      );
      if (result.isComplete && _ageGroup == group) {
        _completedGroup = group;
      } else if (_ageGroup == group) {
        _scheduleRetry();
      }
    } finally {
      repository.dispose();
    }
  }

  void _scheduleRetry() {
    if (_disposed ||
        !_foreground ||
        _wifiConnected == false ||
        _ageGroup == null) {
      return;
    }
    _retryTimer?.cancel();
    _retryTimer = Timer(retryDelay, () => unawaited(_tryPreload()));
  }

  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    unawaited(_wifiSubscription?.cancel());
  }

  static Future<bool> _checkWifi() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.contains(ConnectivityResult.wifi) ||
          results.contains(ConnectivityResult.ethernet);
    } catch (_) {
      return false;
    }
  }

  static Stream<bool> _watchWifi() => Connectivity().onConnectivityChanged.map(
    (results) =>
        results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet),
  );
}
