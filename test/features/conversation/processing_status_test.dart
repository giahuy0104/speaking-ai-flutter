import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/app/homi_ui.dart';
import 'package:ai_speaking_flutter_app/features/conversation/domain/conversation_models.dart';
import 'package:ai_speaking_flutter_app/features/conversation/presentation/widgets/speak_action_bar.dart';
import 'package:ai_speaking_flutter_app/features/conversation/presentation/widgets/voice_hero.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final cases =
      <
        ({
          ConversationProcessingStage stage,
          String heroLabel,
          String actionLabel,
        })
      >[
        (
          stage: ConversationProcessingStage.recognizing,
          heroLabel: 'Đang nhận giọng nói…',
          actionLabel: 'Đang nhận giọng nói…',
        ),
        (
          stage: ConversationProcessingStage.translating,
          heroLabel: 'Đang dịch…',
          actionLabel: 'Đang dịch…',
        ),
        (
          stage: ConversationProcessingStage.preparingAudio,
          heroLabel: 'Đang chuẩn bị âm thanh…',
          actionLabel: 'Đang chuẩn bị âm thanh…',
        ),
      ];

  for (final testCase in cases) {
    testWidgets('shows the ${testCase.stage.name} processing status', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: Column(
              children: <Widget>[
                Expanded(
                  child: VoiceHero(
                    needsDeviceConnection: true,
                    phase: ConversationPhase.processing,
                    processingStage: testCase.stage,
                    amplitude: 0,
                    onStop: () {},
                  ),
                ),
                SpeakActionBar(
                  needsDeviceConnection: true,
                  phase: ConversationPhase.processing,
                  processingStage: testCase.stage,
                  onPressed: null,
                ),
              ],
            ),
          ),
        ),
      );

      final hero = find.byType(VoiceHero);
      final status = find.descendant(
        of: hero,
        matching: find.byKey(const Key('conversation-wave-status')),
      );
      expect(tester.widget<Text>(status).data, testCase.heroLabel);
      expect(
        find.descendant(of: hero, matching: find.byType(Text)),
        findsOneWidget,
      );
      expect(find.text(testCase.actionLabel), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        find.byKey(const Key('conversation-animated-waveform')),
        findsOneWidget,
      );
      expect(
        tester.getSize(find.byKey(const Key('conversation-animated-waveform'))),
        const Size(228, 44),
      );
    });
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('${platform.name} keeps one status below a steady waveform', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final states =
          <({ConversationPhase phase, bool preparing, String status})>[
            (
              phase: ConversationPhase.idle,
              preparing: false,
              status: 'Bấm nút micro bên dưới để bắt đầu',
            ),
            (
              phase: ConversationPhase.idle,
              preparing: true,
              status: 'Đang chuẩn bị micro…',
            ),
            (
              phase: ConversationPhase.recording,
              preparing: false,
              status: 'Mình đang nghe…',
            ),
            (
              phase: ConversationPhase.ready,
              preparing: false,
              status: 'Bấm “Nói câu mới” để tiếp tục',
            ),
            (
              phase: ConversationPhase.error,
              preparing: false,
              status: 'Bấm “Thử lại” khi bạn sẵn sàng',
            ),
          ];
      double? waveTop;
      for (final state in states) {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            home: Scaffold(
              body: VoiceHero(
                phase: state.phase,
                processingStage: ConversationProcessingStage.recognizing,
                amplitude: 0,
                isPreparingMicrophone: state.preparing,
                onStop: () {},
              ),
            ),
          ),
        );
        final status = find.byKey(const Key('conversation-wave-status'));
        expect(tester.widget<Text>(status).data, state.status);
        expect(
          find.descendant(
            of: find.byType(VoiceHero),
            matching: find.byType(Text),
          ),
          findsOneWidget,
        );
        final waveform = find.byType(HomiWaveform);
        final currentTop = tester.getTopLeft(waveform).dy;
        waveTop ??= currentTop;
        expect(currentTop, waveTop);
        expect(tester.getTopLeft(status).dy, greaterThan(currentTop));
      }
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('active waveform travels smoothly at frame cadence', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: VoiceHero(
          phase: ConversationPhase.processing,
          processingStage: ConversationProcessingStage.recognizing,
          amplitude: 0,
          onStop: () {},
        ),
      ),
    );

    final waveform = find.byKey(const Key('conversation-animated-waveform'));
    Finder waveBar(int index) => find.descendant(
      of: waveform,
      matching: find.byKey(ValueKey<String>('homi-wave-bar-$index')),
    );
    var previous = <double>[
      tester.getSize(waveBar(4)).height,
      tester.getSize(waveBar(10)).height,
      tester.getSize(waveBar(16)).height,
    ];
    var changed = false;
    var largestFrameStep = 0.0;

    final mintBar = tester.widget<Container>(waveBar(0));
    final pinkBar = tester.widget<Container>(waveBar(4));
    final navyBar = tester.widget<Container>(waveBar(10));
    expect((mintBar.decoration! as BoxDecoration).color, AppColors.mint);
    expect((pinkBar.decoration! as BoxDecoration).color, AppColors.accentPink);
    expect((navyBar.decoration! as BoxDecoration).color, AppColors.primaryNavy);

    for (var frame = 0; frame < 24; frame += 1) {
      await tester.pump(const Duration(milliseconds: 16));
      final current = <double>[
        tester.getSize(waveBar(4)).height,
        tester.getSize(waveBar(10)).height,
        tester.getSize(waveBar(16)).height,
      ];
      for (var index = 0; index < current.length; index += 1) {
        final step = (current[index] - previous[index]).abs();
        if (step > 0.01) changed = true;
        if (step > largestFrameStep) largestFrameStep = step;
      }
      previous = current;
    }

    expect(changed, isTrue);
    expect(largestFrameStep, lessThan(3.5));
  });
}
