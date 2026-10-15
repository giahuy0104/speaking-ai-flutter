import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../l10n/display_language.dart';
import '../../application/translation_voice_catalog.dart';
import '../../domain/conversation_models.dart';
import '../conversation_controller.dart';

class TranslationVoicePicker extends StatefulWidget {
  const TranslationVoicePicker({
    required this.language,
    required this.controller,
    super.key,
  });

  final TranslationOutputLanguage language;
  final ConversationController controller;

  @override
  State<TranslationVoicePicker> createState() => _TranslationVoicePickerState();
}

class _TranslationVoicePickerState extends State<TranslationVoicePicker> {
  static const _catalog = AndroidTranslationVoiceCatalog();
  static const _refreshValue = '__refresh__';

  TranslationVoiceInventory? _inventory;
  bool _loading = false;
  bool _previewing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant TranslationVoicePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.language != widget.language) {
      _inventory = null;
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final locale = widget.language.speechLocale;
    setState(() => _loading = true);
    try {
      TranslationVoiceInventory? inventory;
      for (var attempt = 0; attempt < 5; attempt++) {
        try {
          inventory = await _catalog.list(locale);
          break;
        } on PlatformException catch (error) {
          if (error.code != 'TTS_UNAVAILABLE' || attempt == 4) rethrow;
          await Future<void>.delayed(const Duration(milliseconds: 400));
        }
      }
      if (!mounted || widget.language.speechLocale != locale) return;
      setState(() => _inventory = inventory);
    } catch (_) {
      if (!mounted || widget.language.speechLocale != locale) return;
      setState(() => _inventory = null);
    } finally {
      if (mounted && widget.language.speechLocale == locale) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _select(String value) async {
    if (value == _refreshValue) {
      await _load();
      return;
    }
    try {
      await _catalog.select(widget.language.speechLocale, value);
      await _load();
      await _preview();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr(
                'Chưa chọn được giọng này. Hãy thử giọng khác.',
                '暂时无法选择此声音，请尝试其他声音。',
              ),
            ),
          ),
        );
      }
    }
  }

  Future<void> _preview() async {
    if (_previewing || widget.controller.isBusy) return;
    setState(() => _previewing = true);
    try {
      await widget.controller.previewTranslationVoice();
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final voices = _inventory?.voices ?? const <TranslationVoice>[];
    final selected = _inventory?.selectedVoice;
    final selectedIndex = voices.indexWhere((voice) => voice.name == selected);
    final label = _loading && _inventory == null
        ? context.tr('Đang tải giọng', '正在加载声音')
        : selectedIndex < 0
        ? context.tr('Giọng đề xuất', '推荐声音')
        : context.tr('Giọng ${selectedIndex + 1}', '声音 ${selectedIndex + 1}');
    final enabled = !widget.controller.isBusy && !_previewing;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        PopupMenuButton<String>(
          key: const Key('translation-voice-button'),
          enabled: enabled,
          tooltip: context.tr('Chọn giọng đọc bản dịch', '选择译文朗读声音'),
          onSelected: (value) => unawaited(_select(value)),
          itemBuilder: (menuContext) => <PopupMenuEntry<String>>[
            PopupMenuItem<String>(
              value: '',
              child: Text(menuContext.tr('Giọng đề xuất', '推荐声音')),
            ),
            for (var index = 0; index < voices.length; index++)
              PopupMenuItem<String>(
                value: voices[index].name,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      menuContext.tr('Giọng ${index + 1}', '声音 ${index + 1}'),
                    ),
                    Text(
                      [
                        voices[index].quality >= 400
                            ? menuContext.tr('Chất lượng cao', '高音质')
                            : menuContext.tr('Chất lượng thường', '普通音质'),
                        voices[index].requiresNetwork
                            ? menuContext.tr('Cần mạng', '需要网络')
                            : menuContext.tr('Trên máy', '设备语音'),
                      ].join(' · '),
                      style: Theme.of(menuContext).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            if (voices.isEmpty)
              PopupMenuItem<String>(
                enabled: false,
                child: Text(
                  menuContext.tr(
                    'Chưa có giọng khác trên thiết bị',
                    '设备上暂无其他声音',
                  ),
                ),
              ),
            PopupMenuItem<String>(
              value: _refreshValue,
              child: Text(menuContext.tr('Làm mới danh sách', '刷新列表')),
            ),
          ],
          child: Chip(
            avatar: const Icon(Icons.record_voice_over_rounded, size: 18),
            label: Text(label),
          ),
        ),
        IconButton(
          key: const Key('translation-voice-preview'),
          onPressed: enabled ? () => unawaited(_preview()) : null,
          tooltip: context.tr('Nghe thử giọng', '试听声音'),
          icon: const Icon(Icons.volume_up_rounded),
        ),
      ],
    );
  }
}
