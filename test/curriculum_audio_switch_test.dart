import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('curriculum uses platform TTS without authored audio flags', () async {
    final catalog = await AssetListeningContentRepository().load();
    final sentence =
        catalog.groups.first.topics.first.lessons.first.sentences.first;
    expect(sentence.audioUri, isNull);
    expect(sentence.vietnameseAudioUri, isNull);

    const channel = MethodChannel('ailingo_voice_prompt');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final service = createVoicePromptService(
      owner: AudioTurnOwner.listeningLesson,
    );
    await service.speakAndWait('Quả táo: Apple hay Ball?');
    expect(calls.single.method, 'speakAndWait');
    await service.dispose();
  });
}
