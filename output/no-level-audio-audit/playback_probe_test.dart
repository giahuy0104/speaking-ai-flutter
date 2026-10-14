// Audit artifact only: mock native playback; no synthesis or production changes.
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/v4_completion_flow.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/application/main_voice_assistant_flow.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('record real factory routing for changed navigation and completion', () async {
    const channel = MethodChannel('ailingo_voice_prompt');
    final calls = <MethodCall>[];
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final service = createVoicePromptService(owner: AudioTurnOwner.mainAssistant);
    addTearDown(service.dispose);
    final flow = MainVoiceAssistantFlow(childAge: 3);
    final rows = <Map<String, Object?>>[];
    final manifests = [
      for (final name in ['assistant_core_audio', 'listening_common_audio', 'homi_gap66_audio'])
        ...(jsonDecode(File('assets/data/$name.json').readAsStringSync())['prompts'] as List),
    ];
    Future<void> probe(String context, String text, String? key, {String? expectedMethod}) async {
      calls.clear();
      if (key == null) {
        await service.speakAndWait(text);
      } else {
        await (service as KeyedVoicePromptService).speakAndWaitWithAudioKey(key, text);
      }
      final playback = calls.where((c) => c.method == 'playAuthoredAudioAndWait' || c.method == 'speakAndWait').toList();
      expect(playback, hasLength(1), reason: context);
      final call = playback.single;
      final args = call.arguments as Map;
      final hash = call.method == 'playAuthoredAudioAndWait'
          ? sha256.convert(args['bytes'] as Uint8List).toString() : null;
      rows.add({
        'context': context, 'text': text, 'requestedKey': key,
        'method': call.method,
        'playedKeys': hash == null ? <String>[] : manifests.where((e) => e['sha256'] == hash).map((e) => e['key'] ?? e['id']).toList(),
      });
      if (expectedMethod != null) expect(call.method, expectedMethod, reason: context);
    }
    for (final text in [
      'Có 10 Chủ đề. Bạn chọn Chủ đề số mấy?',
      'Nhóm tuổi này có 10 Chủ đề. Bạn chọn lại nhé.',
      MainVoiceAssistantFlow.courseRelearnTopicPrompt,
      'Bạn chọn Chủ đề 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 nhé.',
    ]) {
      await probe('new ten-topic navigation', text, flow.audioKeyForPrompt(text), expectedMethod: 'speakAndWait');
    }
    for (var n = 1; n <= 10; n++) {
      for (final text in [
        'Chủ đề $n bạn đã học xong rồi. Bạn muốn chọn Chủ đề khác hay học lại Chủ đề $n?',
        'Bạn đã hoàn thành Chủ đề $n rồi!',
        v4CompletionPrompt(V4CompletionStage.topicEnd, topicNumber: n),
      ]) {
        await probe('topic $n replay/milestone/completion', text, flow.audioKeyForPrompt(text), expectedMethod: 'playAuthoredAudioAndWait');
      }
    }
    for (final text in [
      'Bạn đã hoàn thành khóa học rồi!',
      v4CompletionPrompt(V4CompletionStage.topicEndOneRemaining),
      v4CompletionPrompt(V4CompletionStage.lessonEnd, currentLesson: 1, nextLesson: 2),
      v4CompletionPrompt(V4CompletionStage.lessonEnd, currentLesson: 2, nextLesson: 3),
    ]) {
      await probe('completion', text, flow.audioKeyForPrompt(text), expectedMethod: 'playAuthoredAudioAndWait');
    }
    flow.beginOtherLearning();
    var turn = await flow.handle(MainVoiceAssistantFlow.otherLearningPrompt);
    await probe('other-learning echo', turn.promptText, turn.promptAudioKey);
    flow.beginAfterTranslationStop();
    turn = await flow.handle(MainVoiceAssistantFlow.afterTranslationStopPrompt);
    await probe('after-translation-stop echo', turn.promptText, turn.promptAudioKey);
    File('output/no-level-audio-audit/playback-results.json').writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
  });
}
