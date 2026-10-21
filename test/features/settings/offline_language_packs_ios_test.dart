import 'dart:async';

import 'package:ai_speaking_flutter_app/presentation/navigation/app_view_registry.dart';
import 'package:ai_speaking_flutter_app/core/audio/audio_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/audio_playback_service.dart';
import 'package:ai_speaking_flutter_app/features/conversation/data/demo_conversation_repository.dart';
import 'package:ai_speaking_flutter_app/features/conversation/presentation/conversation_controller.dart';
import 'package:ai_speaking_flutter_app/features/settings/presentation/settings_sheet.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('iOS parent settings no longer exposes offline language packs', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final controller = ConversationController(
      audioInput: _IdleAudio(),
      playbackService: _IdlePlayback(),
      repository: const DemoConversationRepository(),
      childAge: 6,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        onGenerateRoute: createAppRouter().onGenerateRoute,
        home: Scaffold(body: SettingsSheet(controller: controller)),
      ),
    );
    expect(find.byKey(const Key('settings-recognition-section')), findsNothing);
    expect(
      find.byKey(const Key('settings-offline-language-packs')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('settings-offline-language-packs-switch')),
      findsNothing,
    );
    debugDefaultTargetPlatformOverride = null;
  });
}

class _IdleAudio implements AudioInput {
  @override
  Stream<double> get amplitudeDbfs => const Stream.empty();
  @override
  bool get isAvailable => true;
  @override
  bool get isBluetooth => false;
  @override
  String get label => 'Mic iPhone';
  @override
  Future<void> start() async => throw StateError('Settings must not record');
  @override
  Future<AudioCapture> stop() async =>
      throw StateError('Settings must not record');
  @override
  Future<void> cancel() async {}
  @override
  Future<void> dispose() async {}
}

class _IdlePlayback implements AudioPlaybackService {
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
      throw StateError('Settings must not play');
}
