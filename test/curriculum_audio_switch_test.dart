import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/local_cloudinary_audio_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const enabled = bool.fromEnvironment(
    'HOMI_CURRICULUM_AUTHORED_AUDIO',
    defaultValue: true,
  );

  test('curriculum switch controls catalog URIs and prompt lookup', () async {
    final catalog = await AssetListeningContentRepository().load();
    final sentence =
        catalog.groups.first.topics.first.lessons.first.sentences.first;
    if (enabled) {
      expect(
        sentence.audioUri.toString(),
        startsWith('https://res.cloudinary.com/'),
      );
    } else {
      expect(sentence.audioUri, isNull);
      expect(sentence.vietnameseAudioUri, isNull);
    }

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
      httpClient: createLocalCloudinaryAudioClient(),
    );
    await service.speakAndWait('Quả táo: Apple hay Ball?');
    expect(
      calls.single.method,
      enabled ? 'playAuthoredAudioAndWait' : 'speakAndWait',
    );
    await service.dispose();
  });
}
