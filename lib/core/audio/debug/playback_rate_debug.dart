import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// Chẩn đoán "đoạn đầu nhanh, đoạn sau chậm" của giọng dịch tiếng Anh.
///
/// Bật bằng `--dart-define=HOMI_PLAYBACK_RATE_DEBUG=true`. Khi tắt (mặc định)
/// mọi hàm chỉ kiểm tra một hằng số `const` nên không tốn gì đáng kể và không
/// in gì ra log.
///
/// Mục đích là ghi lại đúng thứ tự thời gian của:
/// - quyết định đổi tốc độ ở tầng controller (`use_rate` có `from`/`to`),
/// - thời điểm tầng phát thực sự ghi tốc độ vào player,
/// - vị trí phát lúc tốc độ được ghi, để biết tốc độ có bị đổi *giữa lúc đang
///   phát* hay không,
/// - các lệnh phát/dừng chồng lên nhau giữa hai lượt.
///
/// Không ghi nội dung câu nói, không ghi URL đã ký. URI chỉ được rút gọn thành
/// scheme + 8 ký tự băm để ghép sự kiện cùng một file.
class PlaybackRateDebug {
  /// Chỉ bật khi build có truyền dart-define. Mặc định tắt.
  static const bool enabled = bool.fromEnvironment(
    'HOMI_PLAYBACK_RATE_DEBUG',
  );

  static const String _tag = 'HOMI_RATE';

  static int _sequence = 0;
  static final Stopwatch _clock = Stopwatch()..start();
  static Timer? _heartbeat;

  static bool get isRecording => enabled;

  /// Đặt nhãn cho tiến trình hiện tại (đọc log thấy ngay "ê giọng dịch" hay
  /// "10 giây yên tĩnh").
  static void phase(String label) {
    if (!enabled) return;
    _emit('phase', <String, Object?>{'label': label});
  }

  /// Ghi một vị trí trong mã nguồn cho bất kỳ tầng nào cần.
  static void mark(String event, [Map<String, Object?> fields = const {}]) {
    if (!enabled) return;
    _emit(event, fields);
  }

  /// Bật nhịp 2 giây báo cáo tốc độ và vị trí thực tế của player, để phát hiện
  /// tốc độ bị đổi giữa clip theo thời gian thực.
  static void watchPlayer(
    String owner, {
    required double? Function() currentRate,
    required Duration? Function() position,
    required bool Function() isPlaying,
  }) {
    if (!enabled || _heartbeat != null) return;
    _heartbeat = Timer.periodic(const Duration(seconds: 2), (_) {
      _emit('player_heartbeat', <String, Object?>{
        'owner': owner,
        'rate': currentRate(),
        'positionMs': position()?.inMilliseconds,
        'playing': isPlaying(),
      });
    });
  }

  static void _emit(String event, Map<String, Object?> fields) {
    final id = ++_sequence;
    debugPrintSynchronously(
      '$_tag t=${_clock.elapsedMilliseconds}ms #$id $event '
      '${_encode(fields)}',
    );
  }

  /// Nhãn ngắn cho một file audio: giữ scheme, chỉ lấy 8 ký tự băm. Không in
  /// URL đã ký để log dán ra ngoài vẫn an toàn.
  static String uriTag(Uri? uri) {
    if (uri == null) return 'none';
    final text = uri.toString();
    final digest = sha1.convert(utf8.encode(text)).toString();
    return '${uri.scheme}:${digest.substring(0, 8)}';
  }

  static String _encode(Map<String, Object?> fields) {
    if (fields.isEmpty) return '{}';
    final buffer = StringBuffer('{');
    var first = true;
    fields.forEach((key, value) {
      if (!first) buffer.write(', ');
      first = false;
      buffer.write('$key=$value');
    });
    buffer.write('}');
    return buffer.toString();
  }
}
