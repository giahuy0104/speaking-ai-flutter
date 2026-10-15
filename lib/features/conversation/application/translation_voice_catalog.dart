import 'package:flutter/services.dart';

class TranslationVoice {
  const TranslationVoice({
    required this.name,
    required this.locale,
    required this.quality,
    required this.latency,
    required this.requiresNetwork,
  });

  final String name;
  final String locale;
  final int quality;
  final int latency;
  final bool requiresNetwork;

  factory TranslationVoice.fromMap(Map<Object?, Object?> value) =>
      TranslationVoice(
        name: value['name'] as String? ?? '',
        locale: value['locale'] as String? ?? '',
        quality: value['quality'] as int? ?? 0,
        latency: value['latency'] as int? ?? 0,
        requiresNetwork: value['network'] as bool? ?? false,
      );
}

class TranslationVoiceInventory {
  const TranslationVoiceInventory({
    required this.voices,
    required this.selectedVoice,
  });

  final List<TranslationVoice> voices;
  final String? selectedVoice;
}

class AndroidTranslationVoiceCatalog {
  const AndroidTranslationVoiceCatalog({
    MethodChannel channel = const MethodChannel('ailingo_voice_prompt'),
  }) : _channel = channel;

  final MethodChannel _channel;

  Future<TranslationVoiceInventory> list(String locale) async {
    final response = await _channel.invokeMapMethod<Object?, Object?>(
      'listTranslationVoices',
      <String, Object?>{'locale': locale},
    );
    final rawVoices = response?['voices'] as List<Object?>? ?? const [];
    return TranslationVoiceInventory(
      voices: rawVoices
          .whereType<Map<Object?, Object?>>()
          .map(TranslationVoice.fromMap)
          .where((voice) => voice.name.isNotEmpty)
          .toList(growable: false),
      selectedVoice: response?['selectedVoice'] as String?,
    );
  }

  Future<void> select(String locale, String? name) =>
      _channel.invokeMethod<void>('selectTranslationVoice', <String, Object?>{
        'locale': locale,
        'name': name ?? '',
      });
}
