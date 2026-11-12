import 'package:ai_speaking_flutter_app/app/mascot_assets.dart';
import 'package:ai_speaking_flutter_app/features/conversation/presentation/widgets/homi_hero_3d.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _hero(
  HomiHeroMood mood, {
  bool visible = true,
  Brightness brightness = Brightness.light,
}) => MaterialApp(
  theme: ThemeData(brightness: brightness),
  home: TickerMode(
    enabled: visible,
    child: Center(child: HomiHero3D(mood: mood)),
  ),
);

bool _shows(String asset) => find
    .byWidgetPredicate(
      (widget) => widget is Image && widget.image == AssetImage(asset),
    )
    .evaluate()
    .isNotEmpty;

/// Where HOMI is in its motion loop, 0..1.
double _phase(WidgetTester tester) => tester
    .widget<ValueListenableBuilder<double>>(
      find.descendant(
        of: find.byType(HomiHero3D),
        matching: find.byType(ValueListenableBuilder<double>),
      ),
    )
    .valueListenable
    .value;

/// True when HOMI's motion advances over the next few frames.
Future<bool> _isMoving(WidgetTester tester) async {
  final before = _phase(tester);
  await tester.pump(const Duration(milliseconds: 100));
  return _phase(tester) != before;
}

void main() {
  setUp(() => HomiHero3D.motionEnabled = true);
  tearDown(() => HomiHero3D.motionEnabled = false);

  testWidgets('idle HOMI rests after a while and a tap wakes it', (
    tester,
  ) async {
    await tester.pumpWidget(_hero(HomiHeroMood.idle));
    await tester.pump(const Duration(seconds: 1));
    expect(await _isMoving(tester), isTrue);
    expect(_shows(MascotAssets.waveAnimated), isTrue);

    // 20 s awake, then it stops at the next loop end (loops are 8.4 s).
    await tester.pump(const Duration(seconds: 30));
    expect(await _isMoving(tester), isFalse);
    expect(_phase(tester), 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
    // Resting HOMI holds a still pose instead of the animation.
    expect(_shows(MascotAssets.waveAnimated), isFalse);
    expect(_shows(MascotAssets.wave), isTrue);

    await tester.tap(find.byType(HomiHero3D));
    await tester.pump(const Duration(milliseconds: 100));
    expect(await _isMoving(tester), isTrue);
    expect(_shows(MascotAssets.waveAnimated), isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a theme change does not wake resting HOMI', (tester) async {
    await tester.pumpWidget(_hero(HomiHeroMood.idle));
    await tester.pump(const Duration(seconds: 31));
    expect(await _isMoving(tester), isFalse);

    await tester.pumpWidget(
      _hero(HomiHeroMood.idle, brightness: Brightness.dark),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(await _isMoving(tester), isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('speaking HOMI keeps moving past the idle rest time', (
    tester,
  ) async {
    await tester.pumpWidget(_hero(HomiHeroMood.speaking));
    await tester.pump(const Duration(seconds: 40));
    expect(await _isMoving(tester), isTrue);
    // Only the shown pose plays its animation.
    expect(_shows(MascotAssets.speakAnimated), isTrue);
    expect(_shows(MascotAssets.waveAnimated), isFalse);
    expect(_shows(MascotAssets.listenAnimated), isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a new mood wakes resting HOMI', (tester) async {
    await tester.pumpWidget(_hero(HomiHeroMood.idle));
    await tester.pump(const Duration(seconds: 31));
    expect(await _isMoving(tester), isFalse);

    await tester.pumpWidget(_hero(HomiHeroMood.speaking));
    await tester.pump(const Duration(milliseconds: 100));
    expect(await _isMoving(tester), isTrue);
    expect(_shows(MascotAssets.speakAnimated), isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('HOMI stops while its page is hidden', (tester) async {
    await tester.pumpWidget(_hero(HomiHeroMood.listening, visible: false));
    await tester.pump(const Duration(seconds: 1));
    expect(await _isMoving(tester), isFalse);
    expect(_shows(MascotAssets.listenAnimated), isFalse);

    await tester.pumpWidget(_hero(HomiHeroMood.listening));
    await tester.pump(const Duration(milliseconds: 100));
    expect(await _isMoving(tester), isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
