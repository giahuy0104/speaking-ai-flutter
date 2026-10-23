import '../../offline/bloc/offline_service_bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../app/app_theme.dart';
import '../../../l10n/display_language.dart';
import '../../../features/conversation/application/conversation_settings_port.dart';
import 'settings_section_label.dart';
import 'settings_offline_language_packs_card.dart';
import 'settings_diagnostic_section.dart';
import 'settings_status_tile.dart';

class SettingsRecognitionSection extends StatelessWidget {
  const SettingsRecognitionSection({
    required this.controller,
    required this.createOfflineBloc,
    this.vadSilenceMs,
    this.onVadChanged,
    super.key,
  });
  final OfflineServiceBloc Function() createOfflineBloc;
  final int? vadSilenceMs;
  final ValueChanged<int>? onVadChanged;
  int get _vadSilenceMs => vadSilenceMs ?? controller.vadSilenceMs;
  final ConversationSettingsPort controller;
  @override
  Widget build(BuildContext context) {
    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    final nativeDiagnostic = controller.nativeSpeechDiagnostic;
    final nativeDiagnosticTimeline = controller
        .nativeSpeechDiagnosticLog
        .reversed
        .take(40)
        .toList(growable: false)
        .reversed
        .map(
          (item) => <String>[
            if (item.elapsedMs != null) '+${item.elapsedMs}ms',
            item.stage,
            if (item.caller != null) '@${item.caller}',
            if (item.code != null) 'code=${item.code}',
            if (item.isError && item.message != null) item.message!,
          ].join(' '),
        )
        .join('\n');
    final nativeDiagnosticDetail = nativeDiagnostic == null
        ? null
        : <String>[
            if (nativeDiagnosticTimeline.isNotEmpty) nativeDiagnosticTimeline,
            if (nativeDiagnostic.turnId != null)
              'turn=${nativeDiagnostic.turnId}',
            if (nativeDiagnostic.audioSource != null)
              'source=${nativeDiagnostic.audioSource}',
            if (nativeDiagnostic.audioRoute != null)
              'route=${nativeDiagnostic.audioRoute}',
            if (nativeDiagnostic.code != null) 'code=${nativeDiagnostic.code}',
            if (nativeDiagnostic.message != null) nativeDiagnostic.message!,
          ].join(' • ');
    return SettingsDiagnosticSection(
      key: const Key('settings-recognition-section'),
      icon: Icons.record_voice_over_rounded,
      title: kIsWeb
          ? context.tr('Chế độ nhận diện', '识别模式')
          : context.tr('Nhận dạng giọng nói', '语音识别'),
      summary: context.tr(
        'Chế độ tiêu chuẩn • Tự dừng $_vadSilenceMs ms',
        '标准模式 • 静音 $_vadSilenceMs 毫秒后停止',
      ),
      children: <Widget>[
        if (isAndroid)
          SettingsStatusTile(
            key: const Key('android-standard-recognition'),
            icon: Icons.record_voice_over_rounded,
            title: context.tr('Chế độ tiêu chuẩn', '标准模式'),
            detail: context.tr(
              'Nhận dạng trực tiếp bằng dịch vụ Android. Cloudflare chỉ dịch văn bản và tạo giọng đọc khi cần, không nhận dạng audio.',
              '使用 Android 服务直接识别。Cloudflare 仅在需要时翻译文本和生成语音，不识别音频。',
            ),
            trailing: context.tr('Mặc định', '默认'),
            stateColor: AppColors.success,
          )
        else if (isIOS)
          SettingsStatusTile(
            key: const Key('ios-native-recognition'),
            icon: Icons.record_voice_over_rounded,
            title: context.tr('Apple Native Speech', 'Apple 原生语音识别'),
            detail: context.tr(
              'iOS dùng một luồng Apple Native Speech cho MAIN; không đổi mic hoặc chuyển sang Batch trong cùng lượt.${nativeDiagnosticDetail == null ? '' : '\n\n$nativeDiagnosticDetail'}',
              'iOS 的 MAIN 仅使用一条 Apple 原生语音识别流程；同一轮不会切换麦克风或转入 Batch。${nativeDiagnosticDetail == null ? '' : '\n\n$nativeDiagnosticDetail'}',
            ),
            trailing: nativeDiagnostic?.stage ?? context.tr('Ưu tiên', '优先'),
            stateColor: nativeDiagnostic?.isError == true
                ? AppColors.coral
                : AppColors.success,
          )
        else
          SettingsStatusTile(
            key: const Key('web-online-recognition'),
            icon: Icons.cloud_done_rounded,
            title: context.tr('Nhận giọng nói trực tuyến', '在线语音识别'),
            detail: context.tr(
              controller.usesHfpInput
                  ? 'Đang nhận âm thanh từ mic Bluetooth đã chọn; Cloudflare xử lý nhận dạng, dịch và phát âm.'
                  : 'Đang nhận âm thanh từ mic mặc định; Cloudflare xử lý nhận dạng, dịch và phát âm.',
              controller.usesHfpInput
                  ? '使用已选择的蓝牙麦克风；由 Cloudflare 完成识别、翻译和语音合成。'
                  : '使用默认麦克风；由 Cloudflare 完成识别、翻译和语音合成。',
            ),
            trailing: context.tr('Mặc định', '默认'),
            stateColor: AppColors.success,
          ),
        if (isAndroid || isIOS) ...<Widget>[
          const SizedBox(height: 10),
          SettingsOfflineLanguagePacksCard(createBloc: createOfflineBloc),
        ],
        const SizedBox(height: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SettingsSectionLabel(
              label: context.tr('Tự động dừng khi im lặng', '静音时自动停止'),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '$_vadSilenceMs ms',
                style: const TextStyle(
                  color: AppColors.indigo,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        Slider(
          key: const Key('settings-vad-silence-slider'),
          value: _vadSilenceMs.toDouble(),
          min: 400,
          max: 1600,
          divisions: 12,
          label: '$_vadSilenceMs ms',
          onChanged: controller.isBusy
              ? null
              : (value) =>
                    (onVadChanged ?? controller.setVadSilence)(value.round()),
        ),
        Text(
          context.tr(
            '700 ms là mặc định; có thể tăng nếu trẻ thường ngắt câu.',
            '默认 700 毫秒；如果孩子说话经常停顿，可以调高。',
          ),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
