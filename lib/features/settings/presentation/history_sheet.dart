import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../app/homi_ui.dart';
import '../../../app/mascot_assets.dart';
import '../../../l10n/display_language.dart';
import '../../conversation/application/conversation_settings_port.dart';
import '../../conversation/domain/conversation_models.dart';

class HistorySheet extends StatefulWidget {
  const HistorySheet({required this.controller, super.key});

  final ConversationHistoryPort controller;

  @override
  State<HistorySheet> createState() => _HistorySheetState();
}

class _HistorySheetState extends State<HistorySheet> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _busyItems = <String>{};

  List<ConversationHistoryItem> _items = const <ConversationHistoryItem>[];
  bool _loading = true;
  String? _error;

  String _t(String vietnamese, String simplifiedChinese) =>
      widget.controller.displayLanguage.choose(vietnamese, simplifiedChinese);

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final items = List<ConversationHistoryItem>.of(
        await widget.controller.loadHistory(),
      );
      if (!mounted) {
        return;
      }
      items.sort((left, right) => right.createdAt.compareTo(left.createdAt));
      setState(() {
        _items = items;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = _friendlyError(error);
      });
    }
  }

  List<ConversationHistoryItem> get _visibleItems {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return _items;
    }
    return _items
        .where(
          (item) =>
              item.vietnameseText.toLowerCase().contains(query) ||
              item.displayedTranslation.toLowerCase().contains(query),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final sheetHeight = math.min(
      MediaQuery.sizeOf(context).height * 0.84,
      760.0,
    );
    final visibleItems = _visibleItems;
    final recentUserAudioItems = _items
        .where((item) => item.hasUserAudio)
        .take(3)
        .toList(growable: false);

    return DisplayLanguageScope(
      language: widget.controller.displayLanguage,
      child: Builder(
        builder: (context) => SafeArea(
          child: SizedBox(
            height: sheetHeight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _HistoryHeader(
                    count: _items.length,
                    onRefresh: () => _loadHistory(),
                    onClear: _items.isEmpty ? null : _confirmClearHistory,
                    onClose: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: context.tr(
                        'Tìm câu tiếng Việt hoặc bản dịch',
                        '搜索越南语句子或译文',
                      ),
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.close_rounded),
                              tooltip: context.tr(
                                'Xóa nội dung tìm kiếm',
                                '清除搜索内容',
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (!_loading && recentUserAudioItems.isNotEmpty) ...<Widget>[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        context.tr('3 bản ghi âm gần nhất', '最近 3 条录音'),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: recentUserAudioItems
                            .map(
                              (item) => Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: OutlinedButton.icon(
                                  key: ValueKey<String>(
                                    'user-audio-${item.conversationId}',
                                  ),
                                  onPressed:
                                      _busyItems.contains(item.conversationId)
                                      ? null
                                      : () => _playUserAudioItem(item),
                                  icon: const Icon(
                                    Icons.graphic_eq_rounded,
                                    size: 18,
                                  ),
                                  label: Text(
                                    '${_formatTime(item.createdAt)} · ${item.vietnameseText}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            )
                            .toList(growable: false),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  Expanded(
                    child: _HistoryBody(
                      loading: _loading,
                      error: _error,
                      hasAnyItems: _items.isNotEmpty,
                      items: visibleItems,
                      busyItems: _busyItems,
                      onRetry: () => _loadHistory(),
                      onPlay: _playItem,
                      onDelete: _confirmDeleteItem,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _playItem(ConversationHistoryItem item) async {
    if (_busyItems.contains(item.conversationId)) {
      return;
    }
    setState(() => _busyItems.add(item.conversationId));
    try {
      await widget.controller.playHistoryItem(item);
    } catch (error) {
      _showMessage(_friendlyError(error), isError: true);
    } finally {
      if (mounted) {
        setState(() => _busyItems.remove(item.conversationId));
      }
    }
  }

  Future<void> _playUserAudioItem(ConversationHistoryItem item) async {
    if (_busyItems.contains(item.conversationId)) {
      return;
    }
    setState(() => _busyItems.add(item.conversationId));
    try {
      await widget.controller.playHistoryUserAudio(item);
    } catch (error) {
      _showMessage(_friendlyError(error), isError: true);
    } finally {
      if (mounted) {
        setState(() => _busyItems.remove(item.conversationId));
      }
    }
  }

  Future<void> _confirmDeleteItem(ConversationHistoryItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_t('Xóa lượt nói này?', '删除这条记录？')),
        content: Text(
          _t(
            'HOMI sẽ yêu cầu máy chủ xóa “${item.vietnameseText}” cùng transcript và audio liên quan. Thao tác chỉ hoàn tất khi máy chủ xác nhận.',
            '“${item.vietnameseText}”将从历史记录中删除。',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(_t('Giữ lại', '保留')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(_t('Xóa', '删除')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _busyItems.add(item.conversationId));
    try {
      await widget.controller.deleteHistoryItem(item);
      if (!mounted) {
        return;
      }
      setState(() {
        _items = _items
            .where(
              (candidate) => candidate.conversationId != item.conversationId,
            )
            .toList(growable: false);
      });
      _showMessage(
        _t('Máy chủ đã xác nhận yêu cầu xóa lượt nói.', '服务器已确认删除这条记录。'),
      );
    } catch (error) {
      _showMessage(_friendlyError(error), isError: true);
    } finally {
      if (mounted) {
        setState(() => _busyItems.remove(item.conversationId));
      }
    }
  }

  Future<void> _confirmClearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_t('Xóa toàn bộ lịch sử?', '清除全部历史记录？')),
        content: Text(
          _t(
            'HOMI sẽ yêu cầu máy chủ xóa toàn bộ history, transcript và audio liên quan. Thao tác chỉ hoàn tất khi máy chủ xác nhận và không thể hoàn tác.',
            '此操作将删除所有已保存的对话记录，且无法撤销。',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(_t('Hủy', '取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(_t('Xóa tất cả', '全部删除')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _loading = true);
    try {
      await widget.controller.clearHistory();
      if (!mounted) {
        return;
      }
      setState(() {
        _items = const <ConversationHistoryItem>[];
        _loading = false;
      });
      _showMessage(
        _t(
          'Máy chủ đã xác nhận yêu cầu xóa toàn bộ dữ liệu lịch sử.',
          '服务器已确认删除全部历史数据。',
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _loading = false);
      }
      _showMessage(_friendlyError(error), isError: true);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            widget.controller.displayLanguage.translateKnown(message),
          ),
          backgroundColor: isError
              ? Theme.of(context).colorScheme.error
              : Theme.of(context).colorScheme.inverseSurface,
        ),
      );
  }

  String _friendlyError(Object error) {
    return error
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceFirst('Bad state: ', '');
  }
}

class _HistoryHeader extends StatelessWidget {
  const _HistoryHeader({
    required this.count,
    required this.onRefresh,
    required this.onClear,
    required this.onClose,
  });

  final int count;
  final VoidCallback onRefresh;
  final VoidCallback? onClear;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                context.tr('Lịch sử gần đây', '最近记录'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                context.tr('$count lượt đã lưu', '已保存 $count 条'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh_rounded),
          tooltip: context.tr('Làm mới lịch sử', '刷新历史记录'),
        ),
        const SizedBox(width: 4),
        IconButton(
          onPressed: onClear,
          icon: const Icon(Icons.delete_sweep_outlined),
          tooltip: context.tr('Xóa toàn bộ lịch sử', '清除全部历史记录'),
        ),
        const SizedBox(width: 4),
        IconButton(
          onPressed: onClose,
          icon: const Icon(Icons.close_rounded),
          tooltip: context.tr('Đóng', '关闭'),
        ),
      ],
    );
  }
}

class _HistoryBody extends StatelessWidget {
  const _HistoryBody({
    required this.loading,
    required this.error,
    required this.hasAnyItems,
    required this.items,
    required this.busyItems,
    required this.onRetry,
    required this.onPlay,
    required this.onDelete,
  });

  final bool loading;
  final String? error;
  final bool hasAnyItems;
  final List<ConversationHistoryItem> items;
  final Set<String> busyItems;
  final VoidCallback onRetry;
  final ValueChanged<ConversationHistoryItem> onPlay;
  final ValueChanged<ConversationHistoryItem> onDelete;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: HomiWaveform(
          active: true,
          width: 136,
          height: 38,
          semanticLabel: 'Đang tải lịch sử',
        ),
      );
    }
    if (error != null) {
      return _HistoryMessage(
        icon: Icons.cloud_off_rounded,
        text: context.trKnown(error!),
        actionLabel: context.tr('Thử lại', '重试'),
        onAction: onRetry,
      );
    }
    if (items.isEmpty) {
      return _HistoryMessage(
        icon: hasAnyItems ? Icons.search_off_rounded : Icons.history_rounded,
        assetPath: hasAnyItems ? null : MascotAssets.wave,
        text: hasAnyItems
            ? context.tr('Không tìm thấy lượt nói phù hợp.', '没有找到符合条件的记录。')
            : context.tr('Chưa có lượt nói nào.', '还没有对话记录。'),
        subtitle: hasAnyItems
            ? null
            : context.tr(
                'Lịch sử sẽ xuất hiện sau lần luyện đầu tiên.',
                '完成第一次练习后，记录会显示在这里。',
              ),
      );
    }

    final children = <Widget>[];
    String? currentDay;
    for (final item in items) {
      final dayKey = _dateKey(item.createdAt);
      if (dayKey != currentDay) {
        currentDay = dayKey;
        children.add(
          Padding(
            padding: EdgeInsets.only(top: children.isEmpty ? 4 : 12, bottom: 8),
            child: Text(
              context.trKnown(_dayLabel(item.createdAt)),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 14,
              ),
            ),
          ),
        );
      }
      children.add(
        _HistoryRow(
          item: item,
          busy: busyItems.contains(item.conversationId),
          onPlay: () => onPlay(item),
          onDelete: () => onDelete(item),
        ),
      );
    }
    return ListView(children: children);
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.item,
    required this.busy,
    required this.onPlay,
    required this.onDelete,
  });

  final ConversationHistoryItem item;
  final bool busy;
  final VoidCallback onPlay;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      container: true,
      label:
          '${item.vietnameseText}. ${item.outputLanguage.label}: ${item.displayedTranslation}. '
          '${_formatTime(item.createdAt)}.',
      child: HomiSurface(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Text(
                    item.vietnameseText,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatTime(item.createdAt),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              item.displayedTranslation,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                _MetadataChip(label: context.trKnown(item.context.label)),
                _MetadataChip(label: context.trKnown(_sourceLabel(item))),
                _MetadataChip(label: context.trKnown(_asrLabel(item.asrMode))),
                if (item.latency.timeToFirstAudioMs > 0)
                  _MetadataChip(label: '${item.latency.timeToFirstAudioMs} ms'),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  if (item.audioUri != null ||
                      item.displayedTranslation.trim().isNotEmpty)
                    IconButton(
                      onPressed: busy ? null : onPlay,
                      icon: const Icon(Icons.play_arrow_rounded),
                      tooltip: context.tr('Phát lại bản dịch', '重新播放译文'),
                    ),
                  IconButton(
                    onPressed: busy ? null : onDelete,
                    icon: const Icon(Icons.delete_outline_rounded),
                    tooltip: context.tr('Xóa lượt nói', '删除记录'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetadataChip extends StatelessWidget {
  const _MetadataChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark
            ? theme.colorScheme.surfaceContainerHighest
            : AppColors.lavenderSoft,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _HistoryMessage extends StatelessWidget {
  const _HistoryMessage({
    required this.icon,
    required this.text,
    this.assetPath,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final String? assetPath;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (assetPath != null)
              Image.asset(assetPath!, height: 116, fit: BoxFit.contain)
            else
              Icon(icon, color: theme.colorScheme.onSurfaceVariant, size: 38),
            const SizedBox(height: 10),
            Text(
              text,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (subtitle != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...<Widget>[
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

String _sourceLabel(ConversationHistoryItem item) {
  if (item.processingMode == 'rule' || item.textSource.contains('rule')) {
    return 'Rule';
  }
  if (item.processingMode == 'ai' || item.textSource == 'openai') {
    return 'AI';
  }
  if (item.processingMode == 'cache' || item.textSource.contains('cache')) {
    return 'Cache';
  }
  return item.processingMode == 'unknown'
      ? 'Không rõ nguồn'
      : item.processingMode;
}

String _asrLabel(String asrMode) {
  return switch (asrMode) {
    'android_streaming' => 'Chế độ tiêu chuẩn',
    'hfp_streaming' => 'HFP ASR',
    'openai_realtime' => 'Chế độ AI',
    'ble_offline_intent' => 'BLE offline',
    'batch_chunks' => 'Batch ASR',
    'device_streaming' => 'BLE ASR',
    _ => asrMode == 'unknown' ? 'ASR cũ' : asrMode,
  };
}

String _dateKey(DateTime value) {
  return '${value.year}-${value.month}-${value.day}';
}

String _dayLabel(DateTime value) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final date = DateTime(value.year, value.month, value.day);
  final difference = today.difference(date).inDays;
  if (difference == 0) {
    return 'Hôm nay';
  }
  if (difference == 1) {
    return 'Hôm qua';
  }
  return '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/${value.year}';
}

String _formatTime(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
