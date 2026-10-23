import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../config/app_config.dart';
import '../../../core/privacy/parental_gate.dart';
import '../../../l10n/display_language.dart';
import 'settings_raised_panel.dart';
import 'settings_divider.dart';
import 'settings_action_tile.dart';

class SettingsInformationSection extends StatelessWidget {
  const SettingsInformationSection({
    this.config,
    this.privacyConsentGranted = false,
    this.voiceAccessEnabled = true,
    this.onRequestVoiceAccess,
    this.onManagePrivacyConsent,
    this.onRevokePrivacyConsent,
    this.onStartTutorial,
    super.key,
  });
  final AppConfig? config;
  final bool privacyConsentGranted;
  final bool voiceAccessEnabled;
  final VoidCallback? onRequestVoiceAccess;
  final VoidCallback? onManagePrivacyConsent;
  final Future<void> Function()? onRevokePrivacyConsent;
  final VoidCallback? onStartTutorial;
  @override
  Widget build(BuildContext context) {
    final isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    return SettingsRaisedPanel(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          children: <Widget>[
            SettingsActionTile(
              key: const Key('settings-privacy-policy'),
              icon: Icons.privacy_tip_outlined,
              title: context.tr('Chính sách quyền riêng tư', '隐私政策'),
              detail: context.tr(
                'Xem dữ liệu được thu thập, nhà cung cấp AI, thời hạn lưu và cách yêu cầu xóa.',
                '查看所收集的数据、AI 服务商、保存期限和删除方式。',
              ),
              onTap: () => _openParentLink(
                context,
                config?.privacyPolicyUri,
                context.tr('Chính sách quyền riêng tư', '隐私政策'),
              ),
            ),
            const SettingsDivider(),
            SettingsActionTile(
              key: const Key('settings-terms'),
              icon: Icons.description_outlined,
              title: context.tr('Điều khoản sử dụng', '使用条款'),
              detail: context.tr(
                'Điều khoản dành cho phụ huynh và người giám hộ.',
                '面向家长和监护人的使用条款。',
              ),
              onTap: () => _openParentLink(
                context,
                config?.termsUri,
                context.tr('Điều khoản sử dụng', '使用条款'),
              ),
            ),
            const SettingsDivider(),
            SettingsActionTile(
              key: const Key('settings-support'),
              icon: Icons.support_agent_rounded,
              title: context.tr('Hỗ trợ', '支持'),
              detail: context.tr(
                'Liên hệ HOMI về quyền riêng tư, dữ liệu hoặc lỗi ứng dụng.',
                '就隐私、数据或应用问题联系 HOMI。',
              ),
              onTap: () => _openParentLink(
                context,
                config?.supportUri,
                context.tr('Hỗ trợ', '支持'),
              ),
            ),
            if (privacyConsentGranted &&
                !voiceAccessEnabled &&
                onRequestVoiceAccess != null) ...<Widget>[
              const SettingsDivider(),
              SettingsActionTile(
                key: const Key('settings-enable-voice'),
                showDetail: true,
                icon: Icons.mic_rounded,
                title: context.tr('Cho phép micro', '允许麦克风'),
                detail: context.tr(
                  'Mở hộp thoại quyền hệ thống. Audio chỉ được gửi sau khi có cả chấp thuận phụ huynh và quyền micro.',
                  '打开系统权限对话框。只有家长同意并授予麦克风权限后才会发送音频。',
                ),
                onTap: onRequestVoiceAccess!,
              ),
            ],
            if (!privacyConsentGranted &&
                onManagePrivacyConsent != null) ...<Widget>[
              const SettingsDivider(),
              SettingsActionTile(
                key: const Key('settings-manage-privacy-consent'),
                showDetail: true,
                icon: Icons.verified_user_outlined,
                title: context.tr('Thiết lập tính năng giọng nói', '设置语音功能'),
                detail: context.tr(
                  'Quay lại màn hình dành cho phụ huynh để đọc thông tin và chọn đồng ý.',
                  '返回家长设置页面，阅读说明并选择是否同意。',
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  onManagePrivacyConsent!();
                },
              ),
            ],
            if (isIOS &&
                privacyConsentGranted &&
                onRevokePrivacyConsent != null) ...<Widget>[
              const SettingsDivider(),
              SettingsActionTile(
                key: const Key('settings-revoke-privacy-consent'),
                icon: Icons.delete_forever_outlined,
                title: context.tr('Rút chấp thuận và xóa dữ liệu', '撤回同意并删除数据'),
                detail: context.tr(
                  'Yêu cầu backend xóa lịch sử trước, sau đó xóa nhóm tuổi cục bộ và đặt lại mã cài đặt iOS/Web.',
                  '先请求后端删除历史记录，再删除本地年龄组并重置 iOS/Web 安装标识。',
                ),
                onTap: () => _revokeConsent(context),
              ),
            ],
            if (isIOS && onStartTutorial != null) ...<Widget>[
              const SettingsDivider(),
              SettingsActionTile(
                key: const Key('settings-start-user-tutorial'),
                icon: Icons.school_rounded,
                title: context.tr('Hướng dẫn sử dụng', '使用指南'),
                detail: context.tr(
                  'Xem lại cách giao tiếp, học từ vựng và luyện nghe theo chủ đề',
                  '重新查看对话、词汇和主题听力的使用方法',
                ),
                onTap: () {
                  final startTutorial = onStartTutorial!;
                  Navigator.of(context).pop();
                  Future<void>.delayed(
                    const Duration(milliseconds: 260),
                    startTutorial,
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openParentLink(
    BuildContext context,
    Uri? uri,
    String label,
  ) async {
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label chưa được cấu hình cho bản build này.')),
      );
      return;
    }
    if (!await showParentalGate(context) || !context.mounted) {
      return;
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Không thể mở $label.')));
    }
  }

  Future<void> _revokeConsent(BuildContext context) async {
    final revoke = onRevokePrivacyConsent;
    if (revoke == null ||
        !await showParentalGate(context) ||
        !context.mounted) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rút chấp thuận và yêu cầu xóa dữ liệu?'),
        content: const Text(
          'HOMI sẽ gửi yêu cầu xóa history tới backend trước khi xóa chấp thuận, nhóm tuổi lưu cục bộ và mã cài đặt iOS/Web. Nếu máy chủ không xác nhận, thao tác sẽ dừng và hiển thị lỗi.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Tiếp tục xóa'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    try {
      await revoke();
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Chưa thể xác nhận xóa dữ liệu trên máy chủ. Chấp thuận vẫn được giữ: $error',
          ),
        ),
      );
    }
  }
}
