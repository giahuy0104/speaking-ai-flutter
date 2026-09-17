// Exercises the actual Flutter resolver; only the native speaker and CDN
// transport are substituted. Separate remote-audio-results.json verifies CDN.
import 'dart:convert';
import 'dart:io';
import 'package:ai_speaking_flutter_app/core/audio/main_assistant_audio_prompt_service.dart';
import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service.dart';
import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service_native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../test/support/local_cloudinary_audio_client.dart';

const _out = 'deliverables/audio-runtime-audit-2026-09-17';
const _channel = MethodChannel('ailingo_voice_prompt');
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      return null;
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, null));

  test('execute every current and conditional utterance on all three resolver routes', () async {
    final inventory = (jsonDecode(File(const String.fromEnvironment(
        'HOMI_AUDIT_INVENTORY', defaultValue: 'deliverables/homi-speech-inventory.json'))
        .readAsStringSync()) as List).cast<Map<String, dynamic>>();
    final rows = inventory.where((r) => (r['scopes'] as List).any(
      (s) => s == 'current' || s == 'conditional')).toList();
    final client = createLocalCloudinaryAudioClient();
    final service = createVoicePromptService(httpClient: client);
    final results = <Map<String, dynamic>>[];
    try {
      for (final row in rows) {
        for (final route in ['normal', 'selected', 'phone']) {
          calls.clear();
          final text = row['text'] as String;
          final locale = row['locale'] as String;
          if (route == 'selected') {
            await (service as SelectedMediaOutputVoicePromptService)
                .speakAndWaitOnSelectedMediaOutput(text, locale: locale);
          } else if (route == 'phone') {
            await (service as PhoneSpeakerVoicePromptService)
                .speakAndWaitOnPhoneSpeaker(text, locale: locale);
          } else {
            await service.speakAndWait(text, locale: locale);
          }
          final tts = calls.where((c)=>c.method=='speak'||c.method=='speakAndWait').isNotEmpty;
          results.add({'text':text, 'locale':locale, 'route':route,
            'scopes':row['scopes'], 'source':tts?'native_tts':'authored_mp3',
            'methods':calls.map((c)=>c.method).toList()});
        }
      }
    } finally { await service.dispose(); client.close(); }
    Directory(_out).createSync(recursive:true);
    final failures = results.where((r)=>r['source']=='native_tts').toList();
    File(const String.fromEnvironment('HOMI_AUDIT_RESOLVER_OUTPUT',
        defaultValue: '$_out/resolver-execution.json')).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({'utterances':rows.length,
        'executions':results.length,'fallbacks':failures,'results':results}));
    expect(failures,isEmpty);
  },timeout:const Timeout(Duration(minutes:10)));

  test('characterize first manifest timeout persisting after storage recovers', () async {
    final client=createLocalCloudinaryAudioClient();
    final service=MainAssistantAudioPromptService(
      delegate:const MethodChannelVoicePromptService(), httpClient:client,
      bundle:_SlowFirstManifestBundle(),
      additionalManifestAssets:const ['assets/data/curriculum_audio.json']);
    final prompt=(jsonDecode(File('assets/data/main_assistant_audio.json')
        .readAsStringSync())['prompts'] as List).first['text'] as String;
    await service.speakAndWait(prompt);
    await Future<void>.delayed(const Duration(milliseconds:200));
    await service.speakAndWait(prompt);
    final methods=calls.map((c)=>c.method).toList();
    File('$_out/slow-manifest-reproduction.json').writeAsStringSync(
      jsonEncode({'scenario':'First main manifest load takes 650ms; subsequent storage is fast',
        'runtimeTimeoutMs':500, 'methods':methods,
        'bothAttemptsUseTts':methods.where((m)=>m=='speakAndWait').length==2}));
    expect(methods,['speakAndWait','speakAndWait']);
    await service.dispose(); client.close();
  });
}

class _SlowFirstManifestBundle extends CachingAssetBundle {
  bool slow=true;
  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(await File(key).readAsBytes());
  @override
  Future<String> loadString(String key,{bool cache=true}) async {
    if(slow) {slow=false; await Future<void>.delayed(const Duration(milliseconds:650));}
    return File(key).readAsString();
  }
}
