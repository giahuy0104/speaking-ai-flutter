import 'package:ai_speaking_flutter_app/app/di/history_dependencies.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/settings_bloc.dart';
import '../../../app/app_theme.dart';
import '../../../config/app_config.dart';
import '../../../core/device/device_connection_coordinator.dart';
import '../../../l10n/display_language.dart';
import '../../../features/conversation/application/conversation_settings_port.dart';
import '../../../core/audio/background_media_policy.dart';
import '../../history/screen/history_screen.dart';
import '../widgets/settings_section_label.dart';
import '../widgets/settings_background_media_card.dart';
import '../widgets/settings_device_section.dart';
import '../widgets/settings_preferences_section.dart';
import '../widgets/settings_information_section.dart';
import '../widgets/settings_recognition_section.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    required this.controller,
    this.settingsBloc,
    this.themeMode = ThemeMode.system,
    this.connectionCoordinator,
    this.onThemeModeChanged,
    this.onChildAgeChanged,
    this.onStartTutorial,
    this.config,
    this.privacyConsentGranted = false,
    this.voiceAccessEnabled = true,
    this.onRequestVoiceAccess,
    this.onManagePrivacyConsent,
    this.onRevokePrivacyConsent,
    this.stopMediaWhenBackgrounded,
    this.onStopMediaWhenBackgroundedChanged,
    super.key,
  });

  final ConversationSettingsPort controller;
  final SettingsBloc? settingsBloc;
  final DeviceConnectionCoordinator? connectionCoordinator;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final ValueChanged<int>? onChildAgeChanged;
  final VoidCallback? onStartTutorial;
  final AppConfig? config;
  final bool privacyConsentGranted;
  final bool voiceAccessEnabled;
  final VoidCallback? onRequestVoiceAccess;
  final VoidCallback? onManagePrivacyConsent;
  final Future<void> Function()? onRevokePrivacyConsent;
  final bool? stopMediaWhenBackgrounded;
  final ValueChanged<bool>? onStopMediaWhenBackgroundedChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  ConversationSettingsPort get controller => widget.controller;
  ThemeMode get _themeMode =>
      widget.settingsBloc?.state.themeMode ?? widget.themeMode;
  DisplayLanguage get _language =>
      widget.settingsBloc?.state.displayLanguage ?? controller.displayLanguage;
  int get _childAge =>
      widget.settingsBloc?.state.childAge ?? controller.childAge;
  ValueChanged<ThemeMode>? get _themeChanged => widget.settingsBloc == null
      ? widget.onThemeModeChanged
      : (value) => unawaited(
          widget.settingsBloc!.dispatch(SettingsThemeChanged(value)),
        );
  ValueChanged<int>? get _ageChanged =>
      widget.onChildAgeChanged ??
      (widget.settingsBloc == null
          ? null
          : (value) => unawaited(
              widget.settingsBloc!.dispatch(SettingsChildAgeChanged(value)),
            ));
  void _changeLanguage(DisplayLanguage value) {
    final bloc = widget.settingsBloc;
    if (bloc == null) {
      controller.setDisplayLanguage(value);
    } else {
      unawaited(bloc.dispatch(SettingsLanguageChanged(value)));
    }
  }

  int get _vadSilenceMs =>
      widget.settingsBloc?.state.vadSilenceMs ?? controller.vadSilenceMs;
  bool get _stopMediaWhenBackgrounded =>
      widget.settingsBloc?.state.stopMediaWhenBackgrounded ??
      widget.stopMediaWhenBackgrounded ??
      defaultStopMediaWhenBackgrounded();
  void _changeVad(int value) {
    if (controller.isBusy) return;
    final bloc = widget.settingsBloc;
    if (bloc == null) {
      controller.setVadSilence(value);
    } else {
      unawaited(bloc.dispatch(SettingsVadSilenceChanged(value)));
    }
  }

  ValueChanged<bool>? get _mediaChanged => widget.settingsBloc == null
      ? widget.onStopMediaWhenBackgroundedChanged
      : (enabled) => unawaited(
          widget.settingsBloc!.dispatch(
            SettingsStopMediaWhenBackgroundedChanged(enabled),
          ),
        );

  @override
  Widget build(BuildContext context) {
    final bloc = widget.settingsBloc;
    if (bloc == null) return _buildContent(context);
    return BlocConsumer<SettingsBloc, SettingsState>(
      bloc: bloc,
      listenWhen: (previous, next) => next.failures.entries.any(
        (entry) => previous.failures[entry.key] != entry.value,
      ),
      listener: (context, state) {
        if (state.failures.isEmpty) return;
        final failure = state.failures.values.last;
        final language = state.displayLanguage;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              language.choose(
                'Chưa thể đọc hoặc lưu cài đặt. Vui lòng thử lại.',
                '暂时无法读取或保存设置，请重试。',
              ),
            ),
            action: SnackBarAction(
              label: language.choose('Thử lại', '重试'),
              onPressed: () => unawaited(
                bloc.dispatch(SettingsRetryRequested(failure.field)),
              ),
            ),
          ),
        );
      },
      builder: (context, state) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        controller,
        ?widget.connectionCoordinator,
        ?widget.connectionCoordinator?.bluetoothPower,
      ]),
      builder: (context, _) {
        return DisplayLanguageScope(
          language: _language,
          child: Builder(
            builder: (context) => SafeArea(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: Theme.of(context).brightness == Brightness.dark
                        ? const <Color>[
                            AppColors.darkCanvas,
                            AppColors.darkSurface,
                          ]
                        : const <Color>[AppColors.mintWash, AppColors.mintSoft],
                  ),
                ),
                child: SingleChildScrollView(
                  key: const Key('settings-scroll-view'),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              context.tr('Thiết lập phụ huynh', '家长设置'),
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.transparent,
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                            tooltip: context.tr('Đóng', '关闭'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      SettingsDeviceSection(
                        controller: controller,
                        connectionCoordinator: widget.connectionCoordinator,
                      ),
                      const SizedBox(height: 26),
                      SettingsSectionLabel(
                        label: context.tr('Trải nghiệm học', '学习体验'),
                      ),
                      const SizedBox(height: 12),
                      SettingsPreferencesSection(
                        themeMode: _themeMode,
                        language: _language,
                        childAge: _childAge,
                        isBusy: controller.isBusy,
                        onThemeChanged: _themeChanged,
                        onLanguageChanged: _changeLanguage,
                        onAgeChanged: _ageChanged,
                      ),
                      if (!kIsWeb &&
                          defaultTargetPlatform == TargetPlatform.iOS) ...[
                        const SizedBox(height: 12),
                        SettingsBackgroundMediaCard(
                          value: _stopMediaWhenBackgrounded,
                          onChanged: _mediaChanged,
                        ),
                        const SizedBox(height: 12),
                        SettingsRecognitionSection(
                          controller: controller,
                          vadSilenceMs: _vadSilenceMs,
                          onVadChanged: _changeVad,
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () => showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            useSafeArea: true,
                            showDragHandle: true,
                            builder: (_) => HistoryScreen(
                              createBloc: HistoryDependencies(
                                history: controller,
                              ).createBloc,
                              readLanguage: () => controller.displayLanguage,
                            ),
                          ),
                          icon: const Icon(Icons.history_rounded),
                          label: Text(
                            context.tr('Xem lịch sử gần đây', '查看最近记录'),
                          ),
                        ),
                      ],
                      const SizedBox(height: 26),
                      SettingsSectionLabel(
                        label: context.tr('Thông tin & hỗ trợ', '信息与支持'),
                      ),
                      const SizedBox(height: 10),
                      SettingsInformationSection(
                        config: widget.config,
                        privacyConsentGranted: widget.privacyConsentGranted,
                        voiceAccessEnabled: widget.voiceAccessEnabled,
                        onRequestVoiceAccess: widget.onRequestVoiceAccess,
                        onManagePrivacyConsent: widget.onManagePrivacyConsent,
                        onRevokePrivacyConsent: widget.onRevokePrivacyConsent,
                        onStartTutorial: widget.onStartTutorial,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
