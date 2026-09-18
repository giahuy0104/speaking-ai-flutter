// Temporary diagnostic entry point. Production main.dart is unchanged.
// Records native output selection without changing playback or learning logic.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:ai_speaking_flutter_app/main.dart' as app;

void _emit(Map<String, Object?> event) {
  // Intentionally available in the diagnostic release APK's local logcat.
  // ignore: avoid_print
  print('HOMI_AUDIO_AUDIT ${jsonEncode({
    'at': DateTime.now().toIso8601String(),
    ...event,
  })}');
}

Future<void> main() async {
  _AuditBinding();
  _emit({'event': 'diagnostic_started'});
  await app.main();
}

class _AuditBinding extends WidgetsFlutterBinding {
  @override
  BinaryMessenger createBinaryMessenger() =>
      _AuditMessenger(super.createBinaryMessenger());
}

class _AuditMessenger extends BinaryMessenger {
  _AuditMessenger(this.delegate);
  final BinaryMessenger delegate;
  int sequence = 0;

  @override
  Future<ByteData?>? send(String channel, ByteData? message) {
    Map<String, Object?>? event;
    try {
      if (channel == 'ailingo_voice_prompt' && message != null) {
        final call = const StandardMethodCodec().decodeMethodCall(message);
        final args = call.arguments is Map ? call.arguments as Map : const {};
        event = {'channel': channel, 'method': call.method};
        if (call.method == 'speak' || call.method == 'speakAndWait') {
          event.addAll({
            'source': 'native_tts',
            'text': args['text'],
            'locale': args['locale'],
            'speechRate': args['speechRate'],
          });
        } else if (call.method == 'playAuthoredAudioAndWait') {
          final bytes = args['bytes'] as Uint8List;
          event.addAll({
            'source': 'authored_mp3',
            'sha256': sha256.convert(bytes).toString(),
            'bytes': bytes.length,
          });
        }
      } else if (channel == 'flutter/assets' && message != null) {
        final asset = utf8.decode(message.buffer.asUint8List(
          message.offsetInBytes, message.lengthInBytes,
        ));
        if (asset.contains('audio') || asset.contains('listening_lessons')) {
          event = {'channel': channel, 'asset': asset};
        }
      } else if (channel.startsWith('com.ryanheise.just_audio') &&
          message != null) {
        final call = const StandardMethodCodec().decodeMethodCall(message);
        if (call.method == 'load') {
          final uris = <String>[];
          void collect(Object? value) {
            if (value is Map) {
              if (value['uri'] is String) {
                final uri = Uri.tryParse(value['uri'] as String);
                if (uri != null) uris.add(uri.replace(query: '').toString());
              }
              for (final nested in value.values) { collect(nested); }
            } else if (value is List) {
              for (final nested in value) { collect(nested); }
            }
          }
          collect(call.arguments);
          event = {'channel': channel, 'method': call.method,
            'source': 'media_uri', 'uris': uris};
        }
      }
    } catch (_) { /* Diagnostics must not interrupt platform messages. */ }
    if (event == null) return delegate.send(channel, message);
    final recorded = {...event, 'sequence': ++sequence};
    final watch = Stopwatch()..start();
    _emit({...recorded, 'event': 'request'});
    final response = delegate.send(channel, message);
    return response?.then((bytes) {
      String? error;
      if (bytes != null && channel != 'flutter/assets') {
        try { const StandardMethodCodec().decodeEnvelope(bytes); }
        catch (e) { error = e.toString(); }
      }
      _emit({...recorded, 'event': 'response', 'elapsedMs': watch.elapsedMilliseconds,
        'responseBytes': bytes?.lengthInBytes, 'error': ?error});
      return bytes;
    }, onError: (Object error, StackTrace stack) {
      _emit({...recorded, 'event': 'response_error',
        'elapsedMs': watch.elapsedMilliseconds, 'error': error.toString()});
      Error.throwWithStackTrace(error, stack);
    });
  }

  @override
  void setMessageHandler(String channel, MessageHandler? handler) =>
      delegate.setMessageHandler(channel, handler);

  @override
  Future<void> handlePlatformMessage(String channel, ByteData? data,
      PlatformMessageResponseCallback? callback) =>
      // ignore: deprecated_member_use
      delegate.handlePlatformMessage(channel, data, callback);
}
