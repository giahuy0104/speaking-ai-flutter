import 'package:flutter/foundation.dart';

@immutable
final class AudioPromptKey {
  factory AudioPromptKey(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty ||
        normalized.length > 240 ||
        !_valid.hasMatch(normalized)) {
      throw FormatException('Invalid audio prompt key: $value');
    }
    return AudioPromptKey._(normalized);
  }

  const AudioPromptKey._(this.value);

  static final RegExp _valid = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');

  final String value;

  @override
  bool operator ==(Object other) =>
      other is AudioPromptKey && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
