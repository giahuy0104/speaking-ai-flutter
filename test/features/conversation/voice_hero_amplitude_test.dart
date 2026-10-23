import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/app/homi_ui.dart';
import 'package:ai_speaking_flutter_app/features/conversation/domain/conversation_models.dart';
import 'package:ai_speaking_flutter_app/features/conversation/presentation/widgets/voice_hero.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'VoiceHero follows the amplitude listenable without being rebuilt',
    (tester) async {
      final amplitude = ValueNotifier<double>(0.1);
      addTearDown(amplitude.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: VoiceHero(
                phase: ConversationPhase.recording,
                processingStage: ConversationProcessingStage.recognizing,
                amplitude: amplitude,
                onStop: () {},
              ),
            ),
          ),
        ),
      );

      double waveformLevel() =>
          tester.widget<HomiWaveform>(find.byType(HomiWaveform)).amplitude;
      double mascotScale() => tester
          .widget<AnimatedScale>(
            find.descendant(
              of: find.byType(VoiceHero),
              matching: find.byType(AnimatedScale),
            ),
          )
          .scale;

      expect(waveformLevel(), 0.1);

      // Record exactly which widgets rebuild for one amplitude change.
      final rebuilt = <Type>[];
      final previousHook = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, builtOnce) =>
          rebuilt.add(element.widget.runtimeType);
      addTearDown(() => debugOnRebuildDirtyWidget = previousHook);

      amplitude.value = 0.75;
      await tester.pump();
      debugOnRebuildDirtyWidget = previousHook;

      expect(waveformLevel(), 0.75);
      expect(mascotScale(), closeTo(0.96 + 0.75 * 0.08, 1e-9));
      expect(rebuilt, contains(ValueListenableBuilder<double>));
      expect(rebuilt, isNot(contains(VoiceHero)));
    },
  );
}
