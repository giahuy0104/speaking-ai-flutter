import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../app/homi_ui.dart';
import '../../../l10n/display_language.dart';
import '../../../features/listening/application/android_offline_speech_model_service.dart';
import '../../offline/bloc/offline_service_bloc.dart';

class SettingsOfflineLanguagePacksCard extends StatelessWidget {
  const SettingsOfflineLanguagePacksCard({required this.createBloc, super.key});
  final OfflineServiceBloc Function() createBloc;

  @override
  Widget build(BuildContext context) => BlocProvider<OfflineServiceBloc>(
    create: (_) => createBloc()..add(OfflineServiceRefreshRequested()),
    child: BlocConsumer<OfflineServiceBloc, OfflineServiceState>(
      listenWhen: (previous, current) =>
          previous.noticeRevision != current.noticeRevision,
      listener: (context, state) {
        if (state.saveFailed) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.tr(
                  'Chưa lưu được lựa chọn. Vui lòng thử lại.',
                  '暂时无法保存选择，请重试。',
                ),
              ),
            ),
          );
        } else {
          _showResultMessage(context, state.isAndroid, state.preparation);
        }
      },
      builder: (context, state) => _OfflinePackContent(
        state: state,
        onChanged: (enabled) => context.read<OfflineServiceBloc>().add(
          OfflineServiceAutomaticDownloadChanged(enabled),
        ),
      ),
    ),
  );
}

class _OfflinePackContent extends StatelessWidget {
  const _OfflinePackContent({required this.state, required this.onChanged});
  final OfflineServiceState state;
  final ValueChanged<bool> onChanged;

  String _detail(BuildContext context) {
    if (state.busy) {
      return context.tr('Đang kiểm tra các gói offline…', '正在检查离线模型…');
    }
    if (!state.isAndroid) {
      if (state.status?.state == AndroidOfflineSpeechModelState.installed) {
        return context.tr(
          'Dịch Việt–Anh và Anh–Việt đã sẵn sàng trên thiết bị. Giọng nói offline phụ thuộc model Apple Speech của thiết bị.',
          '设备上的越英双向翻译已准备好。离线语音取决于设备的 Apple Speech 模型。',
        );
      }
      if (state.preparingIosModels) {
        return context.tr(
          'HOMI đang chuẩn bị giọng nói và tải gói dịch offline qua Wi-Fi. Bạn có thể tiếp tục dùng ứng dụng.',
          'HOMI 正在准备语音并通过 Wi-Fi 下载离线翻译模型；您可以继续使用应用。',
        );
      }
      return state.consent == AndroidOfflineSpeechModelConsent.allowed
          ? context.tr(
              'Đã cho phép chuẩn bị giọng nói và tải gói dịch Việt–Anh/Anh–Việt qua Wi-Fi. Các gói dịch chưa sẵn sàng; cần iPhone thật để tải và dùng offline.',
              '已允许准备语音并通过 Wi-Fi 下载越英双向翻译模型。翻译模型尚未准备好；下载和离线使用需要实体 iPhone。',
            )
          : context.tr(
              'Bật để HOMI chuẩn bị Apple Speech và tải gói dịch Việt–Anh/Anh–Việt qua Wi-Fi cho iPhone.',
              '开启后 HOMI 会准备 Apple Speech，并通过 Wi-Fi 为 iPhone 下载越英双向翻译模型。',
            );
    }
    switch (state.status?.state) {
      case AndroidOfflineSpeechModelState.installed:
        return context.tr(
          'Các gói giọng nói và dịch Việt–Anh đã sẵn sàng. Khi mất mạng, bài học, thử thách và dịch liên tục có thể xử lý trên thiết bị.',
          '语音与越英翻译模型已准备好；离线时课程、挑战和连续翻译可在设备上处理。',
        );
      case AndroidOfflineSpeechModelState.pending:
        final progress = state.status?.progress ?? 0;
        final totalMegabytes =
            ((state.status?.downloadBytes ?? 0) / 1024 / 1024).round();
        final sizeText = totalMegabytes > 0
            ? ' (riêng giọng nói khoảng $totalMegabytes MB; gói dịch tải thêm)'
            : '';
        return context.tr(
          progress > 0
              ? 'HOMI đang tải các gói offline$sizeText trong nền: $progress%. Thường mất 2–10 phút tùy Wi-Fi; bạn có thể tiếp tục dùng ứng dụng.'
              : 'Đã xếp lịch tải các gói offline$sizeText. HOMI sẽ tự bắt đầu khi có Wi-Fi; thường mất 2–10 phút.',
          progress > 0
              ? 'HOMI 正在后台下载离线模型：$progress%。通常需要 2–10 分钟；您可以继续使用应用。'
              : '离线模型已排入队列；连接 Wi-Fi 后会自动开始，通常需要 2–10 分钟。',
        );
      case AndroidOfflineSpeechModelState.unavailable:
        return context.tr(
          'CPU của thiết bị này chưa tương thích với model offline; khi có mạng ứng dụng vẫn chấm qua máy chủ.',
          '此 Android 设备不支持由 HOMI 下载模型；联网时仍会通过服务器评分。',
        );
      case AndroidOfflineSpeechModelState.downloadable:
      case AndroidOfflineSpeechModelState.missing:
      case AndroidOfflineSpeechModelState.unknown:
      case null:
        if (state.preparation ==
            AndroidOfflineSpeechModelPreparationResult.waitingForWifi) {
          return context.tr(
            'Đã cho phép. HOMI sẽ tự tải en-US khi có Wi-Fi, không dùng dữ liệu di động.',
            '已允许。连接 Wi-Fi 后 HOMI 将自动下载 en-US，不使用移动数据。',
          );
        }
        return state.consent == AndroidOfflineSpeechModelConsent.allowed
            ? context.tr(
                'Đã cho phép tự tải các gói tiếng Anh, tiếng Việt và dịch Việt–Anh qua Wi-Fi. Không mở màn hình tải riêng.',
                '已允许通过 Wi-Fi 自动下载约 40 MB 的 en-US 模型，不会打开 Google 下载页面。',
              )
            : context.tr(
                'Phụ huynh bật mục này một lần; HOMI tự tải các gói cần thiết khi có Wi-Fi và không dùng dữ liệu di động.',
                '家长只需开启一次；HOMI 会在连接 Wi-Fi 时自动下载 en-US，不使用移动数据。',
              );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unsupported =
        state.status?.state == AndroidOfflineSpeechModelState.unavailable;
    return HomiSurface(
      key: const Key('settings-offline-language-packs'),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const HomiIconBadge(icon: Icons.download_for_offline_rounded),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  context.tr('Tự tải giọng nói và dịch offline', '自动下载离线语音和翻译'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _detail(context),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            key: const Key('settings-offline-language-packs-switch'),
            value: state.consent == AndroidOfflineSpeechModelConsent.allowed,
            onChanged: state.busy || unsupported ? null : onChanged,
          ),
        ],
      ),
    );
  }
}

void _showResultMessage(
  BuildContext context,
  bool isAndroid,
  AndroidOfflineSpeechModelPreparationResult? result,
) {
  if (!isAndroid &&
      result == AndroidOfflineSpeechModelPreparationResult.downloadRequested) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              'HOMI sẽ chuẩn bị giọng nói và tải gói dịch offline qua Wi-Fi.',
              'HOMI 将准备离线语音，并通过 Wi-Fi 下载离线翻译模型。',
            ),
          ),
        ),
      );
    return;
  }
  final message = switch (result) {
    AndroidOfflineSpeechModelPreparationResult.downloadRequested => context.tr(
      'HOMI sẽ tải các gói giọng nói và dịch trong nền qua Wi-Fi.',
      'HOMI 将通过 Wi-Fi 在后台下载语音和翻译模型。',
    ),
    AndroidOfflineSpeechModelPreparationResult.waitingForWifi => context.tr(
      'Đã bật tự tải. HOMI sẽ thực hiện khi có Wi-Fi.',
      '已开启自动下载。连接 Wi-Fi 后 HOMI 会自动执行。',
    ),
    AndroidOfflineSpeechModelPreparationResult.ready => context.tr(
      'Các gói offline đã sẵn sàng.',
      '离线模型已准备好。',
    ),
    AndroidOfflineSpeechModelPreparationResult.unavailable => context.tr(
      'Thiết bị này chưa hỗ trợ tải model trực tiếp.',
      '此设备暂不支持直接下载模型。',
    ),
    _ => null,
  };
  if (message != null) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
