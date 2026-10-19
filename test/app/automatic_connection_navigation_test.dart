import 'package:ai_speaking_flutter_app/app/ai_speaking_app.dart';
import 'package:ai_speaking_flutter_app/app/device_connection_feedback_overlay.dart';
import 'package:ai_speaking_flutter_app/features/conversation/presentation/conversation_screen.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/topic_listening_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'native BLE recovery never blocks topic navigation after setup',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Completed limited-mode setup avoids voice permission prompts. Native
      // recovery events still flow through the real BLE bridge, controller and
      // app-level status handlers. Flutter's test binding blocks network I/O.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'innotrik.child-age.v1': 6,
        'homi.parent-setup.version': 1,
        'homi.parental-privacy-consent.limited-mode': true,
      });
      final messenger = tester.binding.defaultBinaryMessenger;
      const channels = <MethodChannel>[
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
      ];
      for (final channel in channels) {
        messenger.setMockMethodCallHandler(channel, (call) async {
          return switch (call.method) {
            'initialize' => <String, Object?>{'phase': 'idle'},
            'findDevices' || 'scan' => <Object?>[],
            'requestPermissions' || 'hasPermission' => false,
            _ => null,
          };
        });
      }
      addTearDown(() {
        for (final channel in channels) {
          messenger.setMockMethodCallHandler(channel, null);
        }
      });

      await tester.pumpWidget(const AiSpeakingApp());
      await tester.pumpAndSettle();
      expect(find.byType(ConversationScreen).hitTestable(), findsOneWidget);
      final controller = tester
          .widget<ConversationScreen>(find.byType(ConversationScreen))
          .controller;
      // Flutter's Navigator keeps its own route barrier. Recovery must not
      // introduce an additional, app-owned barrier above the page.
      final initialBarriers = find.byType(ModalBarrier).evaluate().length;

      // Events can originate from a native recovery timer after the Dart
      // auto-connect future finished. Cover more than one recovery round.
      for (final phase in <String>[
        'scanning',
        'connecting',
        'reconnecting',
        'error',
        'scanning',
      ]) {
        await messenger.handlePlatformMessage(
          'ailingo_aiv0_ble_control/events',
          const StandardMethodCodec().encodeSuccessEnvelope(<String, Object?>{
            'type': 'status',
            'phase': phase,
          }),
          (_) {},
        );
        await tester.pump();
        await tester.pump();
        expect(controller.aiv0BleStatus.phase.name, phase);
        expect(find.byType(DeviceConnectionFeedbackOverlay), findsNothing);
        expect(find.byType(ModalBarrier), findsNWidgets(initialBarriers));

        final topics = find.byKey(const Key('topic-listening-edge-tab'));
        expect(topics.hitTestable(), findsOneWidget);
        await tester.tap(topics);
        await tester.pumpAndSettle();
        expect(find.byType(TopicListeningScreen).hitTestable(), findsOneWidget);
        final topicBarriers = find.byType(ModalBarrier).evaluate().length;
        // A reconnect can arrive while the user is already in Topics too.
        await messenger.handlePlatformMessage(
          'ailingo_aiv0_ble_control/events',
          const StandardMethodCodec().encodeSuccessEnvelope(<String, Object?>{
            'type': 'status',
            'phase': 'reconnecting',
          }),
          (_) {},
        );
        await tester.pump();
        await tester.pump();
        expect(controller.aiv0BleStatus.phase.name, 'reconnecting');
        expect(find.byType(DeviceConnectionFeedbackOverlay), findsNothing);
        expect(find.byType(ModalBarrier), findsNWidgets(topicBarriers));
        expect(find.byTooltip('Quay lại').hitTestable(), findsOneWidget);
        await tester.tap(find.byTooltip('Quay lại'));
        await tester.pumpAndSettle();
        expect(find.byType(ConversationScreen).hitTestable(), findsOneWidget);
      }

      await tester.pumpWidget(const SizedBox.shrink());
      // Drain the optional backend-catalog preload deadline after disposal;
      // network requests are blocked by the widget test binding.
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
    },
    variant: TargetPlatformVariant(<TargetPlatform>{TargetPlatform.android}),
  );
}
