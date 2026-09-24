import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_audio_keys.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('curriculum resolves fixed prompts to authored audio', () async {
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
    expect(calls.single.method, 'playAuthoredAudioAndWait');

    final keyed = service as KeyedVoicePromptService;
    for (final text in <String>[
      'Bạn cần hoàn thành Level 1 trước nhé.',
      'Bạn cần học xong Bài 2 trước nhé.',
      'Bạn đã hoàn thành Chủ đề 7 rồi!',
      'Bạn muốn chọn Chủ đề khác hay học lại Chủ đề 7?',
      'Bạn muốn bắt đầu Level 3 hay dừng lại?',
      'Tiếp theo là một câu thử thách nhé.',
      'Bạn muốn bắt đầu Bài 1 hay dừng lại?',
      'Có 2 Bài học. Bạn chọn từ số 1 đến số 2.',
      'Bạn muốn học Bài 1 hay học lại Bài 2?',
      'Bạn muốn học Bài 1 hay học lại Bài 3?',
      'Bạn muốn học Bài 2 hay học lại Bài 3?',
    ]) {
      final audioKey = ListeningAudioKeys.topicContextPrompt(text);
      expect(audioKey, isNotNull, reason: text);
      calls.clear();
      await keyed.speakAndWaitWithAudioKey(audioKey!, text);
      expect(calls.single.method, 'playAuthoredAudioAndWait', reason: text);
    }
    await service.dispose();
  });
}
