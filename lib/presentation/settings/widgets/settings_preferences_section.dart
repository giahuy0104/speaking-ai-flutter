import 'dart:async';
import 'package:flutter/material.dart';
import '../../../app/app_theme.dart';
import '../../../l10n/display_language.dart';
import '../../../features/listening/domain/listening_catalog.dart';
import 'settings_raised_panel.dart';
import 'settings_divider.dart';
import 'settings_preference_row.dart';

class SettingsPreferencesSection extends StatefulWidget {
  const SettingsPreferencesSection({
    required this.themeMode,
    required this.language,
    required this.childAge,
    required this.isBusy,
    this.onThemeChanged,
    this.onLanguageChanged,
    this.onAgeChanged,
    super.key,
  });
  final ThemeMode themeMode;
  final DisplayLanguage language;
  final int childAge;
  final bool isBusy;
  final ValueChanged<ThemeMode>? onThemeChanged;
  final ValueChanged<DisplayLanguage>? onLanguageChanged;
  final ValueChanged<int>? onAgeChanged;
  @override
  State<SettingsPreferencesSection> createState() =>
      _SettingsPreferencesSectionState();
}

class _SettingsPreferencesSectionState
    extends State<SettingsPreferencesSection> {
  @override
  Widget build(BuildContext context) => SettingsRaisedPanel(
    child: Column(
      children: <Widget>[
        SettingsPreferenceRow(
          key: const Key('settings-child-age-group'),
          icon: Icons.child_care_rounded,
          title: context.tr('Nhóm tuổi', '年龄组'),
          value: _ageLabel(context),
          onTap: !widget.isBusy && widget.onAgeChanged != null
              ? () => _chooseAge(context)
              : null,
        ),
        const SettingsDivider(),
        SettingsPreferenceRow(
          key: const Key('settings-language-row'),
          icon: Icons.language_rounded,
          title: context.tr('Ngôn ngữ', '语言'),
          value: widget.language.nativeLabel,
          onTap: () => _chooseLanguage(context),
        ),
        const SettingsDivider(),
        SettingsPreferenceRow(
          key: const Key('appearance-settings-card'),
          icon: Icons.light_mode_outlined,
          title: context.tr('Giao diện', '外观'),
          value: _themeLabel(context, widget.themeMode),
          onTap: widget.onThemeChanged == null
              ? null
              : () => _chooseTheme(context),
        ),
      ],
    ),
  );
  bool _choiceSheetOpen = false;

  String _ageLabel(BuildContext context) {
    final catalog = listeningCatalogs.firstWhere(
      (entry) =>
          widget.childAge >= entry.startAge && widget.childAge <= entry.endAge,
      orElse: () => listeningCatalogs.first,
    );
    return context.tr(
      '${catalog.startAge}–${catalog.endAge} tuổi',
      '${catalog.startAge}–${catalog.endAge} 岁',
    );
  }

  String _themeLabel(BuildContext context, ThemeMode mode) => switch (mode) {
    ThemeMode.system => context.tr('Hệ thống', '跟随系统'),
    ThemeMode.light => context.tr('Sáng', '浅色'),
    ThemeMode.dark => context.tr('Tối', '深色'),
  };

  Future<T?> _choose<T>(
    BuildContext context, {
    required String title,
    required T selected,
    required List<({T value, String label, String key})> options,
    bool useChips = false,
  }) async {
    if (_choiceSheetOpen) return null;
    _choiceSheetOpen = true;
    try {
      return await showModalBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (sheetContext) => ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.75,
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 8, 12),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(sheetContext).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: context.tr('Đóng', '关闭'),
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: useChips
                        ? SizedBox(
                            width: double.infinity,
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 2,
                              children: <Widget>[
                                for (final option in options)
                                  ChoiceChip(
                                    key: ValueKey<String>(option.key),
                                    showCheckmark: true,
                                    elevation: 0,
                                    side: BorderSide(
                                      color: Theme.of(
                                        sheetContext,
                                      ).colorScheme.outlineVariant,
                                    ),
                                    label: Text(option.label),
                                    selected: option.value == selected,
                                    onSelected: (_) => Navigator.of(
                                      sheetContext,
                                    ).pop(option.value),
                                  ),
                              ],
                            ),
                          )
                        : Column(
                            children: <Widget>[
                              for (final option in options)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Material(
                                    borderRadius: BorderRadius.circular(12),
                                    color: option.value == selected
                                        ? AppColors.primaryNavy
                                        : Colors.transparent,
                                    child: ListTile(
                                      key: ValueKey<String>(option.key),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      selected: option.value == selected,
                                      selectedColor: Colors.white,
                                      title: Text(option.label),
                                      trailing: option.value == selected
                                          ? const Icon(Icons.check_rounded)
                                          : null,
                                      onTap: () => Navigator.of(
                                        sheetContext,
                                      ).pop(option.value),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } finally {
      _choiceSheetOpen = false;
    }
  }

  Future<void> _chooseAge(BuildContext context) async {
    final catalog = listeningCatalogs.firstWhere(
      (entry) =>
          widget.childAge >= entry.startAge && widget.childAge <= entry.endAge,
      orElse: () => listeningCatalogs.first,
    );
    final value = await _choose<int>(
      context,
      title: context.tr('Nhóm tuổi của trẻ', '孩子年龄组'),
      useChips: true,
      selected: catalog.startAge,
      options: [
        for (final entry in listeningCatalogs)
          (
            value: entry.startAge,
            label: context.tr(
              '${entry.startAge}–${entry.endAge} tuổi',
              '${entry.startAge}–${entry.endAge} 岁',
            ),
            key: 'settings-age-${entry.id}',
          ),
      ],
    );
    if (mounted && value != null && !widget.isBusy) {
      widget.onAgeChanged?.call(value);
    }
  }

  Future<void> _chooseLanguage(BuildContext context) async {
    final value = await _choose<DisplayLanguage>(
      context,
      title: context.tr('Ngôn ngữ hiển thị', '显示语言'),
      selected: widget.language,
      options: [
        for (final language in DisplayLanguage.values)
          (
            value: language,
            label: language.nativeLabel,
            key: 'settings-language-${language.code}',
          ),
      ],
    );
    if (mounted && value != null) widget.onLanguageChanged?.call(value);
  }

  Future<void> _chooseTheme(BuildContext context) async {
    final value = await _choose<ThemeMode>(
      context,
      title: context.tr('Giao diện', '外观'),
      selected: widget.themeMode,
      options: [
        for (final mode in ThemeMode.values)
          (
            value: mode,
            label: _themeLabel(context, mode),
            key: 'theme-mode-${mode.name}',
          ),
      ],
    );
    if (mounted && value != null) widget.onThemeChanged?.call(value);
  }
}
