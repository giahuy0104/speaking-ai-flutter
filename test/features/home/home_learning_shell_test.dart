import 'dart:async';

import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/config/app_config.dart';
import 'package:ai_speaking_flutter_app/core/audio/audio_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/audio_playback_service.dart';
import 'package:ai_speaking_flutter_app/core/audio/streaming_speech_input.dart';
import 'package:ai_speaking_flutter_app/core/platform/background_learning_session.dart';
import 'package:ai_speaking_flutter_app/features/conversation/data/demo_conversation_repository.dart';
import 'package:ai_speaking_flutter_app/features/conversation/domain/conversation_models.dart';
import 'package:ai_speaking_flutter_app/features/conversation/presentation/conversation_controller.dart';
import 'package:ai_speaking_flutter_app/features/conversation/presentation/conversation_screen.dart';
import 'package:ai_speaking_flutter_app/features/home/presentation/home_learning_shell.dart';
import 'package:ai_speaking_flutter_app/features/listening/data/active_listening_session_store.dart';
import 'package:ai_speaking_flutter_app/features/listening/data/listening_progress_store.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/topic_listening_screen.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:ai_speaking_flutter_app/features/settings/application/parent_media_settings.dart';
import 'package:ai_speaking_flutter_app/features/settings/presentation/history_sheet.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/presentation/vocabulary_home_screen.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/application/main_voice_assistant_flow.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/application/main_speaking_session_controller.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/application/voice_navigation_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'opens vocabulary, returns to communication, and opens topics',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = _controller();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_app(controller));
      await tester.pumpAndSettle();

      expect(find.byType(ConversationScreen).hitTestable(), findsOneWidget);
      expect(
        find.byKey(const Key('vocabulary-edge-tab')).hitTestable(),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('topic-listening-edge-tab')).hitTestable(),
        findsOneWidget,
      );
      final vocabularyTabRect = tester.getRect(
        find.byKey(const Key('vocabulary-edge-tab')),
      );
      final topicTabRect = tester.getRect(
        find.byKey(const Key('topic-listening-edge-tab')),
      );
      expect(vocabularyTabRect.width, closeTo(50, 0.01));
      expect(vocabularyTabRect.height, closeTo(176, 0.01));
      expect(topicTabRect.width, closeTo(50, 0.01));
      expect(topicTabRect.height, closeTo(176, 0.01));
      expect(topicTabRect.top - vocabularyTabRect.top, closeTo(18, 0.01));
      expect(vocabularyTabRect.top, closeTo(844 * 0.27, 0.01));
      expect(find.byKey(const Key('conversation-bottom-tab')), findsNothing);
      expect(
        find.byKey(const Key('main-voice-assistant-button')),
        findsNothing,
      );
      expect(find.byKey(const Key('history-bottom-tab')), findsNothing);
      expect(find.text('Câu tiếng Việt'), findsOneWidget);
      expect(find.text('Câu tiếng Anh'), findsOneWidget);
      expect(find.text('Con nói tiếng Việt'), findsNothing);
      expect(find.text('Mình sẽ giúp nói bằng tiếng Anh'), findsNothing);
      expect(find.text('Câu bạn nói sẽ hiện ở đây'), findsOneWidget);
      expect(find.byKey(const Key('topic-listening-shortcut')), findsNothing);
      expect(find.text('50 chủ đề'), findsNothing);

      await tester.tap(find.byKey(const Key('vocabulary-edge-tab')));
      await tester.pumpAndSettle();
      expect(find.byType(VocabularyHomeScreen).hitTestable(), findsOneWidget);
      expect(
        find.byKey(const Key('vocabulary-home-back-button')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('search-vocabulary-button')), findsNothing);
      expect(find.byKey(const Key('vocabulary-landing-homi')), findsOneWidget);
      expect(find.byKey(const Key('vocabulary-edge-tab')), findsNothing);
      expect(find.byKey(const Key('topic-listening-edge-tab')), findsNothing);

      await tester.tap(find.byKey(const Key('vocabulary-home-back-button')));
      await tester.pumpAndSettle();
      expect(find.byType(ConversationScreen).hitTestable(), findsOneWidget);

      await tester.tap(find.byKey(const Key('topic-listening-edge-tab')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));
      expect(find.text('Chủ đề'), findsWidgets);
      await tester.pumpAndSettle();
      expect(find.byType(TopicListeningScreen), findsOneWidget);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets('system Back closes vocabulary detail before leaving the tab', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _controller();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('vocabulary-edge-tab')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('vocabulary-family-card')));
    await tester.pumpAndSettle();
    expect(find.text('Ba mẹ đã thêm'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('vocabulary-family-card')), findsOneWidget);
    expect(find.byType(VocabularyHomeScreen).hitTestable(), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(ConversationScreen).hitTestable(), findsOneWidget);
  });

  testWidgets('protects settings with the parent access gate', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _controller();
    addTearDown(controller.dispose);
    var gateRequests = 0;

    await tester.pumpWidget(
      _app(
        controller,
        parentAccessGate: (_) async {
          gateRequests += 1;
          return false;
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(gateRequests, 1);
    expect(find.text('Thiết lập phụ huynh'), findsNothing);
  });

  testWidgets('Android opens settings directly when no gate is injected', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _controller();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_app(controller, useDefaultParentAccessGate: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Thiết lập phụ huynh'), findsOneWidget);
    expect(find.text('Không thể xác thực'), findsNothing);
    Navigator.of(tester.element(find.text('Thiết lập phụ huynh'))).pop();
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Android opens recent history without device authentication', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _controller();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_app(controller, useDefaultParentAccessGate: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Lịch sử gần đây'));
    await tester.pumpAndSettle();

    expect(find.byType(HistorySheet), findsOneWidget);
    expect(find.text('Không thể xác thực'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'Android changes the listening age group without device authentication',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = _controller();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _app(
          controller,
          useDefaultParentAccessGate: true,
          listeningContentFuture: AssetListeningContentRepository(
            bundle: rootBundle,
          ).load(),
          onChildAgeChanged: (_) {},
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('topic-listening-edge-tab')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('topic-age-selector')));
      await tester.pumpAndSettle();

      expect(find.text('Chọn nhóm bài học'), findsOneWidget);
      expect(find.text('Không thể xác thực'), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('reports settings modal visibility until the sheet closes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = _controller();
    addTearDown(controller.dispose);
    final visibilityChanges = <bool>[];

    await tester.pumpWidget(
      _app(controller, onModalVisibilityChanged: visibilityChanges.add),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Thiết lập phụ huynh'), findsOneWidget);
    expect(visibilityChanges, <bool>[true]);

    Navigator.of(tester.element(find.text('Thiết lập phụ huynh'))).pop();
    await tester.pumpAndSettle();

    expect(visibilityChanges, <bool>[true, false]);
  });

  testWidgets('iOS keeps header, side navigation, and hardware MAIN flow', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final speechInput = _FakeStreamingSpeechInput();
    final voiceNavigationController = VoiceNavigationController(
      speechInput: speechInput,
      ownsSpeechInput: true,
    );
    final speakingSessionController = MainSpeakingSessionController();
    final controller = _controller();
    addTearDown(controller.dispose);
    addTearDown(voiceNavigationController.dispose);
    addTearDown(speakingSessionController.dispose);

    await tester.pumpWidget(
      _app(
        controller,
        autoStartVoiceNavigation: true,
        voiceNavigationController: voiceNavigationController,
        speakingSessionController: speakingSessionController,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ConversationScreen).hitTestable(), findsOneWidget);
    expect(speechInput.startCount, 0);

    await tester.tap(find.byTooltip('Lịch sử gần đây'));
    await tester.pumpAndSettle();
    expect(find.text('Lịch sử gần đây'), findsWidgets);
    Navigator.of(tester.element(find.text('Lịch sử gần đây').last)).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Cài đặt'));
    await tester.pumpAndSettle();
    expect(find.text('Thiết lập phụ huynh'), findsOneWidget);
    final settingsScroll = find
        .descendant(
          of: find.byKey(const Key('settings-scroll-view')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings-recognition-section')),
      360,
      scrollable: settingsScroll,
    );
    await tester.tap(find.byKey(const Key('settings-recognition-section')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ios-native-recognition')), findsOneWidget);
    expect(find.byKey(const Key('android-standard-recognition')), findsNothing);
    Navigator.of(tester.element(find.text('Thiết lập phụ huynh'))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('vocabulary-edge-tab')));
    await tester.pumpAndSettle();
    expect(find.byType(VocabularyHomeScreen).hitTestable(), findsOneWidget);

    await tester.tap(find.byKey(const Key('vocabulary-practice-button')));
    await tester.pumpAndSettle();
    expect(find.byType(ConversationScreen).hitTestable(), findsOneWidget);

    expect(find.byKey(const Key('main-voice-assistant-button')), findsNothing);
    expect(await voiceNavigationController.activateFromMainButton(), isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(speechInput.startCount, 1);
    expect(voiceNavigationController.isMainButtonSessionActive, isTrue);
    expect(voiceNavigationController.isListening, isTrue);
    expect(find.text('MAIN'), findsNothing);

    // BLE/HFP status and diagnostics are surfaced through ConversationController
    // notifications. On iOS they must not cancel the explicit MAIN recognizer;
    // only Android owns the optional always-on navigation lifecycle here.
    controller.setChildAge(7);
    await tester.pump();
    await tester.pump();
    expect(voiceNavigationController.isMainButtonSessionActive, isTrue);
    expect(voiceNavigationController.isListening, isTrue);
    expect(speechInput.cancelCount, 0);
    expect(find.text('MAIN'), findsNothing);

    await voiceNavigationController.pause();
    await tester.pump();
    await tester.tap(find.byKey(const Key('topic-listening-edge-tab')));
    await tester.pumpAndSettle();
    expect(find.byType(TopicListeningScreen), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'opens vocabulary from a recognized voice command',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final speechInput = _FakeStreamingSpeechInput();
      final voiceNavigationController = VoiceNavigationController(
        speechInput: speechInput,
        ownsSpeechInput: true,
      );
      final controller = _controller();
      addTearDown(controller.dispose);
      addTearDown(voiceNavigationController.dispose);

      await tester.pumpWidget(
        _app(
          controller,
          voiceNavigationController: voiceNavigationController,
          listeningContentFuture: AssetListeningContentRepository(
            bundle: rootBundle,
          ).load(),
        ),
      );
      await tester.pumpAndSettle();
      expect(await voiceNavigationController.activateFromMainButton(), isTrue);
      final handled = await voiceNavigationController.dispatchRecognizedText(
        'Con muốn học từ vựng',
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(handled, isTrue);
      expect(find.byType(VocabularyHomeScreen).hitTestable(), findsOneWidget);
      expect(find.textContaining('Đã nhận lệnh giọng nói'), findsOneWidget);

      await tester.tap(find.byKey(const Key('vocabulary-practice-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('topic-listening-edge-tab')));
      await tester.pumpAndSettle();
      expect(find.byType(TopicListeningScreen), findsOneWidget);

      expect(await voiceNavigationController.activateFromMainButton(), isTrue);
      final returnToVocabulary = voiceNavigationController
          .dispatchRecognizedText('Con muốn học từ vựng');
      await tester.pumpAndSettle();

      expect(await returnToVocabulary, isTrue);
      expect(find.byType(TopicListeningScreen), findsNothing);
      expect(find.byType(VocabularyHomeScreen).hitTestable(), findsOneWidget);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets('starts continuous voice navigation on Android', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final speechInput = _FakeStreamingSpeechInput();
    final voiceNavigationController = VoiceNavigationController(
      speechInput: speechInput,
    );
    final controller = _controller();

    await tester.pumpWidget(
      _app(
        controller,
        autoStartVoiceNavigation: true,
        voiceNavigationController: voiceNavigationController,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 901));

    expect(speechInput.startCount, 1);
    expect(voiceNavigationController.isListening, isTrue);
    expect(controller.isRecording, isFalse);
    expect(find.text('Bắt đầu nói'), findsOneWidget);
    expect(find.textContaining('Hey HOMI'), findsOneWidget);

    await tester.tap(find.byKey(const Key('topic-listening-edge-tab')));
    await tester.pumpAndSettle();

    expect(find.byType(TopicListeningScreen), findsOneWidget);
    expect(voiceNavigationController.isListening, isTrue);
    expect(controller.isRecording, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    voiceNavigationController.dispose();
    controller.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'pauses Android voice navigation whenever the app leaves foreground',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final backgroundSession = _FakeBackgroundLearningSession();
      final speechInput = _FakeStreamingSpeechInput();
      final voiceNavigationController = VoiceNavigationController(
        speechInput: speechInput,
      );
      final controller = _controller();
      addTearDown(backgroundSession.dispose);
      addTearDown(voiceNavigationController.dispose);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _app(
          controller,
          autoStartVoiceNavigation: true,
          voiceNavigationController: voiceNavigationController,
          backgroundLearningSession: backgroundSession,
          parentMediaSettingsStore: const _FakeParentMediaSettingsStore(true),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 901));

      expect(backgroundSession.startCount, 1);
      expect(voiceNavigationController.isListening, isTrue);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(milliseconds: 400));

      expect(voiceNavigationController.isListening, isFalse);
      expect(speechInput.cancelCount, 1);
      expect(backgroundSession.stopCount, 0);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'keeps an explicit Android MAIN mic when the parent setting is disabled',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      final backgroundSession = _FakeBackgroundLearningSession();
      final speechInput = _FakeStreamingSpeechInput();
      final voiceNavigationController = VoiceNavigationController(
        speechInput: speechInput,
      );
      final controller = _controller();
      addTearDown(backgroundSession.dispose);
      addTearDown(voiceNavigationController.dispose);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _app(
          controller,
          voiceNavigationController: voiceNavigationController,
          backgroundLearningSession: backgroundSession,
          parentMediaSettingsStore: _FakeParentMediaSettingsStore(false),
        ),
      );
      await tester.pump();
      expect(await voiceNavigationController.activateFromMainButton(), isTrue);
      expect(voiceNavigationController.isListening, isTrue);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(milliseconds: 400));

      expect(voiceNavigationController.isListening, isTrue);
      expect(speechInput.cancelCount, 0);
      expect(backgroundSession.stopCount, 0);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(backgroundSession.stopCount, 0);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('keeps an explicit Android MAIN mic when the display is locked', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    final backgroundSession = _FakeScreenAwareBackgroundLearningSession(
      screenInteractive: false,
    );
    final speechInput = _FakeStreamingSpeechInput();
    final voiceNavigationController = VoiceNavigationController(
      speechInput: speechInput,
    );
    final controller = _controller();
    addTearDown(backgroundSession.dispose);
    addTearDown(voiceNavigationController.dispose);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _app(
        controller,
        voiceNavigationController: voiceNavigationController,
        backgroundLearningSession: backgroundSession,
        parentMediaSettingsStore: const _FakeParentMediaSettingsStore(true),
      ),
    );
    await tester.pump();
    expect(await voiceNavigationController.activateFromMainButton(), isTrue);
    expect(voiceNavigationController.isListening, isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(milliseconds: 400));

    expect(backgroundSession.screenStateReadCount, 1);
    expect(voiceNavigationController.isListening, isTrue);
    expect(speechInput.cancelCount, 0);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'rearms an Android background session without opening a busy microphone',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final backgroundSession = _FakeBackgroundLearningSession();
      final speechInput = _FakeStreamingSpeechInput();
      final voiceNavigationController = VoiceNavigationController(
        speechInput: speechInput,
      );
      final controller = _controller();
      addTearDown(backgroundSession.dispose);
      addTearDown(voiceNavigationController.dispose);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _app(
          controller,
          autoStartVoiceNavigation: true,
          voiceNavigationController: voiceNavigationController,
          backgroundLearningSession: backgroundSession,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 901));
      expect(voiceNavigationController.isListening, isTrue);

      backgroundSession.interrupt('audio_focus_loss');
      await tester.pump(const Duration(milliseconds: 100));
      expect(voiceNavigationController.isListening, isFalse);

      backgroundSession.resume();
      await tester.pump(const Duration(milliseconds: 400));
      expect(voiceNavigationController.isListening, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'promotes a companion-restored Android session when the app is visible',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      final backgroundSession = _FakeBackgroundLearningSession();
      final controller = _controller();
      addTearDown(backgroundSession.dispose);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _app(controller, backgroundLearningSession: backgroundSession),
      );
      await tester.pump();
      expect(backgroundSession.startCount, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      backgroundSession.resume('microphone_requires_visible_resume');
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(backgroundSession.startCount, 2);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('MAIN rejects free lesson selection before a module is chosen', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final speechInput = _FakeStreamingSpeechInput();
    final voiceNavigationController = VoiceNavigationController(
      speechInput: speechInput,
      ownsSpeechInput: true,
    );
    final controller = _controller();
    addTearDown(controller.dispose);
    addTearDown(voiceNavigationController.dispose);

    await tester.pumpWidget(
      _app(
        controller,
        voiceNavigationController: voiceNavigationController,
        listeningContentFuture: AssetListeningContentRepository(
          bundle: rootBundle,
        ).load(),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      await voiceNavigationController.dispatchRecognizedText('Hey HOMI'),
      isTrue,
    );
    expect(
      await voiceNavigationController.dispatchRecognizedText(
        'Con muốn học bài 1 trong chủ đề Những con số quanh mình',
      ),
      isTrue,
    );

    for (var index = 0; index < 14; index += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    for (var index = 0; index < 20; index += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final openedLessonScreenCount = <Key>[
      const Key('lesson-intro-screen'),
      const Key('lesson-review-screen'),
      const Key('lesson-practice-screen'),
    ].fold<int>(0, (count, key) => count + find.byKey(key).evaluate().length);
    expect(openedLessonScreenCount, 0);
    expect(find.byType(ConversationScreen).hitTestable(), findsOneWidget);
  });

  testWidgets(
    'iOS restores an active lesson checkpoint only after returning foreground',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await const ActiveListeningSessionStore().save(
        childAge: 6,
        topicNumber: 1,
        lessonNumber: 1,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);

      final controller = _controller();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _app(
          controller,
          childAge: 6,
          listeningContentFuture: AssetListeningContentRepository(
            bundle: rootBundle,
          ).load(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(ConversationScreen).hitTestable(), findsOneWidget);
      expect(find.byType(TopicListeningScreen), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      for (var index = 0; index < 60; index += 1) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final openedLessonScreenCount = <Key>[
        const Key('lesson-intro-screen'),
        const Key('lesson-review-screen'),
        const Key('lesson-practice-screen'),
      ].fold<int>(0, (count, key) => count + find.byKey(key).evaluate().length);
      expect(openedLessonScreenCount, 1);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'Main flow uses the saved age and topic owner to open the first lesson',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final contentFuture = AssetListeningContentRepository(
        bundle: rootBundle,
      ).load();
      final speechInput = _FakeStreamingSpeechInput();
      final voiceNavigationController = VoiceNavigationController(
        speechInput: speechInput,
        ownsSpeechInput: true,
        mainAssistantFlow: MainVoiceAssistantFlow(
          contentLoader: () => contentFuture,
        ),
      );
      final controller = _controller();
      addTearDown(controller.dispose);
      addTearDown(voiceNavigationController.dispose);

      await tester.pumpWidget(
        _app(
          controller,
          childAge: 4,
          voiceNavigationController: voiceNavigationController,
          listeningContentFuture: contentFuture,
        ),
      );
      await tester.pumpAndSettle();

      expect(await voiceNavigationController.activateFromMainButton(), isTrue);
      expect(
        await voiceNavigationController.dispatchRecognizedText(
          'Con muốn học theo chủ đề',
        ),
        isTrue,
      );
      // The topic screen now resolves the current Level from real progress, then
      // re-opens MAIN with only that Level's topic numbers (1, 2, 3 here).
      for (var index = 0; index < 20; index += 1) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(TopicListeningScreen), findsOneWidget);
      expect(
        await voiceNavigationController.dispatchRecognizedText(
          'Con muốn học chủ đề số 3',
        ),
        isTrue,
      );
      for (var index = 0; index < 20; index += 1) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final openedLessonScreenCount = <Key>[
        const Key('lesson-intro-screen'),
        const Key('lesson-review-screen'),
        const Key('lesson-practice-screen'),
      ].fold<int>(0, (count, key) => count + find.byKey(key).evaluate().length);
      expect(openedLessonScreenCount, 1);
      expect(
        find.byKey(const Key('topic-lesson-list-screen'), skipOffstage: false),
        findsOneWidget,
      );
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets(
    'Main speaking choice hands off to the automatic speaking session',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final speechInput = _FakeStreamingSpeechInput();
      final voiceNavigationController = VoiceNavigationController(
        speechInput: speechInput,
        ownsSpeechInput: true,
      );
      final speakingSessionController = MainSpeakingSessionController();
      final controller = _controller();
      var didStartMainSpeakingMode = false;

      await tester.pumpWidget(
        _app(
          controller,
          voiceNavigationController: voiceNavigationController,
          speakingSessionController: speakingSessionController,
          onMainSpeakingModeStarted: () async {
            didStartMainSpeakingMode = true;
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(await voiceNavigationController.activateFromMainButton(), isTrue);
      expect(
        await voiceNavigationController.dispatchRecognizedText(
          'Con ghi muốn luyện nói',
        ),
        isTrue,
      );
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump();

      expect(find.byType(ConversationScreen).hitTestable(), findsOneWidget);
      expect(didStartMainSpeakingMode, isTrue);
      expect(controller.isRecording, isFalse);

      controller.dispose();
      voiceNavigationController.dispose();
      speakingSessionController.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets(
    'translation choice enters continuous translation directly',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final speechInput = _FakeStreamingSpeechInput();
      final speakingSessionController = MainSpeakingSessionController();
      late final VoiceNavigationController voiceNavigationController;
      final controller = _controller(
        streamingSpeechInput: speechInput,
        beforeRecordingStart: () async {
          if (speakingSessionController.isActive) return;
          await voiceNavigationController.pause();
        },
      );
      voiceNavigationController = VoiceNavigationController(
        speechInput: speechInput,
        ownsSpeechInput: false,
      );
      var didStartContinuousMode = false;

      await tester.pumpWidget(
        _app(
          controller,
          voiceNavigationController: voiceNavigationController,
          speakingSessionController: speakingSessionController,
          onMainSpeakingModeStarted: () async {
            didStartContinuousMode = true;
            speakingSessionController.enter();
            await controller.startRecording(
              noSpeechTimeout: const Duration(seconds: 6),
              speakNoSpeechPrompt: false,
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(await voiceNavigationController.activateFromMainButton(), isTrue);
      speechInput.emitPartial('Dịch sang tiếng Anh');
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(ConversationScreen).hitTestable(), findsOneWidget);
      expect(didStartContinuousMode, isTrue);
      expect(controller.isRecording, isTrue);
      expect(speechInput.cancelCount, 1);
      expect(speechInput.startCount, 2);

      controller.dispose();
      voiceNavigationController.dispose();
      speakingSessionController.dispose();
      await speechInput.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets(
    'Android shows conversation before translation MAIN starts from vocabulary',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final speechInput = _FakeStreamingSpeechInput();
      final voiceNavigationController = VoiceNavigationController(
        speechInput: speechInput,
        ownsSpeechInput: true,
      );
      final speakingSessionController = MainSpeakingSessionController();
      final controller = _controller();
      final mainStartEntered = Completer<void>();
      final releaseMainStart = Completer<void>();

      await tester.pumpWidget(
        _app(
          controller,
          voiceNavigationController: voiceNavigationController,
          speakingSessionController: speakingSessionController,
          onMainSpeakingModeStarted: () async {
            mainStartEntered.complete();
            await releaseMainStart.future;
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('vocabulary-edge-tab')));
      await tester.pumpAndSettle();
      expect(find.byType(VocabularyHomeScreen).hitTestable(), findsOneWidget);

      expect(await voiceNavigationController.activateFromMainButton(), isTrue);
      final dispatch = voiceNavigationController.dispatchRecognizedText(
        'Dịch sang tiếng Anh',
      );
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 500));

      expect(mainStartEntered.isCompleted, isTrue);
      final pageView = tester.widget<PageView>(
        find.byKey(const Key('home-learning-page-view')),
      );
      expect(pageView.controller?.page, closeTo(0, 0.001));
      expect(find.byType(ConversationScreen).hitTestable(), findsOneWidget);

      releaseMainStart.complete();
      await tester.pump();
      expect(await dispatch, isTrue);

      controller.dispose();
      voiceNavigationController.dispose();
      speakingSessionController.dispose();
      await speechInput.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'leaving listening waits for the continuous translation microphone handoff',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final speechInput = _FakeStreamingSpeechInput();
      final voiceNavigationController = VoiceNavigationController(
        speechInput: speechInput,
        ownsSpeechInput: true,
      );
      final speakingSessionController = MainSpeakingSessionController();
      final controller = _controller();
      final handoff = Completer<void>();
      var handoffCount = 0;
      var exitCommitted = false;
      var exitWasCommittedWhenHandoffStarted = false;

      await tester.pumpWidget(
        _app(
          controller,
          voiceNavigationController: voiceNavigationController,
          speakingSessionController: speakingSessionController,
          listeningContentFuture: AssetListeningContentRepository(
            bundle: rootBundle,
          ).load(),
          onActiveLearningExitCommitted: () => exitCommitted = true,
          onMainSpeakingModeStarted: () async {
            speakingSessionController.enter();
            exitWasCommittedWhenHandoffStarted = exitCommitted;
            handoffCount += 1;
            await handoff.future;
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('topic-listening-edge-tab')));
      await tester.pumpAndSettle();
      expect(find.byType(TopicListeningScreen), findsOneWidget);

      expect(
        await voiceNavigationController.activateFromMainButton(
          activeLearning: true,
        ),
        isTrue,
      );
      expect(
        await voiceNavigationController.dispatchRecognizedText(
          'Con muốn học cái khác',
        ),
        isTrue,
      );

      var navigationCompleted = false;
      final navigation = voiceNavigationController
          .dispatchRecognizedText('Dịch sang tiếng Anh')
          .then((value) {
            navigationCompleted = true;
            return value;
          });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      expect(handoffCount, 1);
      expect(exitWasCommittedWhenHandoffStarted, isTrue);
      expect(navigationCompleted, isFalse);
      expect(voiceNavigationController.isListening, isFalse);
      expect(find.byType(TopicListeningScreen).hitTestable(), findsNothing);
      expect(find.byType(ConversationScreen).hitTestable(), findsOneWidget);

      handoff.complete();
      expect(await navigation, isTrue);
      await tester.pump();
      expect(navigationCompleted, isTrue);

      controller.dispose();
      voiceNavigationController.dispose();
      speakingSessionController.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

Widget _app(
  ConversationController controller, {
  bool autoStartVoiceNavigation = false,
  int childAge = 6,
  VoiceNavigationController? voiceNavigationController,
  Future<ListeningContentCatalog>? listeningContentFuture,
  MainSpeakingSessionController? speakingSessionController,
  VoidCallback? onActiveLearningExitCommitted,
  Future<void> Function()? onMainSpeakingModeStarted,
  ValueChanged<bool>? onModalVisibilityChanged,
  ValueChanged<int>? onChildAgeChanged,
  Future<bool> Function(BuildContext)? parentAccessGate,
  bool useDefaultParentAccessGate = false,
  BackgroundLearningSessionControl? backgroundLearningSession,
  ParentMediaSettingsStore parentMediaSettingsStore =
      const _FakeParentMediaSettingsStore(true),
}) {
  final home = HomeLearningShell(
    controller: controller,
    voiceNavigationController: voiceNavigationController,
    speakingSessionController: speakingSessionController,
    listeningContentFuture: listeningContentFuture,
    listeningProgressStore: _HomeListeningProgressStore(),
    onActiveLearningExitCommitted: onActiveLearningExitCommitted,
    onMainSpeakingModeStarted: onMainSpeakingModeStarted,
    onScreenMainPressed: voiceNavigationController == null
        ? null
        : () async {
            await voiceNavigationController.activateFromMainButton();
          },
    onModalVisibilityChanged: onModalVisibilityChanged,
    onChildAgeChanged: onChildAgeChanged,
    parentAccessGate: useDefaultParentAccessGate
        ? null
        : parentAccessGate ?? (_) async => true,
    backgroundLearningSession: backgroundLearningSession,
    parentMediaSettingsStore: parentMediaSettingsStore,
    config: AppConfig(
      backendBaseUri: Uri.parse('https://example.com'),
      useDemoBackend: true,
      childAge: childAge,
      autoStartVoiceNavigation: autoStartVoiceNavigation,
    ),
  );
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    home: home,
  );
}

class _FakeParentMediaSettingsStore implements ParentMediaSettingsStore {
  const _FakeParentMediaSettingsStore(this.enabled);

  final bool enabled;

  @override
  Future<bool> readStopMediaWhenBackgrounded() async => enabled;

  @override
  Future<void> writeStopMediaWhenBackgrounded(bool enabled) async {}
}

class _HomeListeningProgressStore extends ListeningProgressStore {
  ListeningTopicSelectionCheckpoint? _selectionCheckpoint;

  @override
  Future<Map<String, int>> readAll() async => <String, int>{};

  @override
  Future<Set<String>> readCompletedV4LessonActivities() async => <String>{};

  @override
  Future<Set<String>> readStartedLessonCores() async => <String>{};

  @override
  Future<bool> hasPassedLevelMission(String levelId) async => false;

  @override
  Future<bool> isCourseCompleted(String courseId) async => false;

  @override
  Future<ListeningTopicSelectionCheckpoint?> readTopicSelectionCheckpoint(
    String courseId,
  ) async => _selectionCheckpoint;

  @override
  Future<void> saveTopicSelectionCheckpoint(
    String courseId, {
    required int levelNumber,
    required bool announceLevel,
  }) async {
    _selectionCheckpoint = ListeningTopicSelectionCheckpoint(
      levelNumber: levelNumber,
      announceLevel: announceLevel,
    );
  }

  @override
  Future<void> clearTopicSelectionCheckpoint(String courseId) async {
    _selectionCheckpoint = null;
  }

  @override
  Future<int> readLesson(String lessonId) async => 0;

  @override
  Future<int> readCurrentSentence(String lessonId) async => 0;

  @override
  Future<ListeningResumeStage> readResumeStage(String lessonId) async =>
      ListeningResumeStage.core;

  @override
  Future<bool> hasStartedLessonCore(String lessonId) async => false;

  @override
  Future<bool> hasCompletedV4LessonActivity(String lessonId) async => false;

  @override
  Future<bool> hasLessonPendingRelearn(String lessonId) async => false;

  @override
  Future<bool> hasOpenedLearningGuide() async => true;
}

class _FakeBackgroundLearningSession
    implements BackgroundLearningSessionControl {
  final StreamController<BackgroundLearningEvent> _events =
      StreamController<BackgroundLearningEvent>.broadcast();
  int startCount = 0;
  int stopCount = 0;

  @override
  Stream<BackgroundLearningEvent> get events => _events.stream;

  @override
  Future<bool> start() async {
    startCount += 1;
    return true;
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
  }

  void interrupt(String reason) {
    _events.add(
      BackgroundLearningEvent(
        type: BackgroundLearningEventType.interrupted,
        reason: reason,
      ),
    );
  }

  void resume([String reason = 'audio_session_interruption_ended']) {
    _events.add(
      BackgroundLearningEvent(
        type: BackgroundLearningEventType.resumable,
        reason: reason,
      ),
    );
  }

  Future<void> dispose() => _events.close();
}

class _FakeScreenAwareBackgroundLearningSession
    extends _FakeBackgroundLearningSession
    implements DeviceScreenStateBackgroundSessionControl {
  _FakeScreenAwareBackgroundLearningSession({required this.screenInteractive});

  final bool screenInteractive;
  int screenStateReadCount = 0;

  @override
  Future<bool?> isScreenInteractive() async {
    screenStateReadCount += 1;
    return screenInteractive;
  }
}

ConversationController _controller({
  StreamingSpeechInput? streamingSpeechInput,
  Future<void> Function()? beforeRecordingStart,
}) {
  return ConversationController(
    audioInput: _FakeAudioInput(),
    streamingSpeechInput: streamingSpeechInput,
    playbackService: const _FakePlaybackService(),
    repository: const DemoConversationRepository(),
    childAge: 6,
    initialAsrMode: streamingSpeechInput == null
        ? null
        : AsrMode.androidStreaming,
    beforeRecordingStart: beforeRecordingStart,
  );
}

class _FakeStreamingSpeechInput implements StreamingSpeechInput {
  final StreamController<double> _amplitudeController =
      StreamController<double>.broadcast();
  final StreamController<void> _completedController =
      StreamController<void>.broadcast();
  final StreamController<String> _partialTextController =
      StreamController<String>.broadcast();
  int startCount = 0;
  int cancelCount = 0;

  @override
  String get label => 'ASR Android trực tiếp';

  @override
  Stream<double> get amplitudeDbfs => _amplitudeController.stream;

  @override
  Stream<void> get completed => _completedController.stream;

  @override
  Stream<String> get partialText => _partialTextController.stream;

  @override
  Future<bool> checkAvailability() async => true;

  @override
  Future<void> start() async {
    startCount += 1;
  }

  @override
  Future<StreamingSpeechCapture> stop() async => const StreamingSpeechCapture(
    sourceText: 'Con muốn học từ vựng',
    duration: Duration(seconds: 1),
    inputLabel: 'ASR Android trực tiếp',
    confidence: 0.9,
    firstResultMs: 100,
    finalAfterStopMs: 20,
  );

  @override
  Future<void> cancel() async {
    cancelCount += 1;
  }

  void emitPartial(String text) {
    _partialTextController.add(text);
  }

  @override
  Future<void> dispose() async {
    await _amplitudeController.close();
    await _completedController.close();
    await _partialTextController.close();
  }
}

class _FakeAudioInput implements ChunkedAudioInput {
  @override
  String get label => 'Mic điện thoại';

  @override
  bool get isBluetooth => false;

  @override
  bool get isAvailable => true;

  @override
  Stream<double> get amplitudeDbfs => const Stream<double>.empty();

  @override
  Stream<Uint8List> get audioChunks => const Stream<Uint8List>.empty();

  @override
  Future<void> start() async {}

  @override
  Future<void> startChunked() async {}

  @override
  Future<AudioCapture> stop() async => const AudioCapture(
    filePath: 'unused.wav',
    mimeType: 'audio/wav',
    duration: Duration(seconds: 1),
    inputLabel: 'Mic điện thoại',
    isBluetoothInput: false,
    initialNoiseRms: null,
  );

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}
}

class _FakePlaybackService implements AudioPlaybackService {
  const _FakePlaybackService();

  @override
  Stream<bool> get playingStream => const Stream<bool>.empty();

  @override
  Future<void> prepare() async {}

  @override
  Future<void> preload(Uri uri) async {}

  @override
  Future<PlaybackStartMetrics> play(Uri uri) async {
    return const PlaybackStartMetrics(
      audioLoadDuration: Duration.zero,
      startedAfterRequest: Duration.zero,
      fromDeviceCache: false,
    );
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
