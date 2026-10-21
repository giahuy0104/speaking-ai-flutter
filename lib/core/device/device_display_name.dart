import '../../l10n/display_language.dart';

/// Names from the OS remain raw so changing the app language also updates the
/// fallback. A device ID identifies a connection; it is not a friendly name.
String localizedDeviceName(
  String? rawName,
  DisplayLanguage language, {
  String? deviceId,
}) {
  final name = rawName?.trim() ?? '';
  final id = deviceId?.trim() ?? '';
  if (name.isEmpty ||
      (id.isNotEmpty && name.toLowerCase() == id.toLowerCase())) {
    return language.choose('Thiết bị không xác định', '未知设备');
  }
  return name;
}
