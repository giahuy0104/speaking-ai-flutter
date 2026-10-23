part of '../screen/history_screen.dart';

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
    required this.onReview,
    required this.onDelete,
  });

  final bool loading;
  final String? error;
  final bool hasAnyItems;
  final List<ConversationHistoryItem> items;
  final Set<String> busyItems;
  final VoidCallback onRetry;
  final ValueChanged<ConversationHistoryItem> onPlay;
  final void Function(ConversationHistoryItem item, bool approved) onReview;
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
          onApprove: () => onReview(item, true),
          onReject: () => onReview(item, false),
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
    required this.onApprove,
    required this.onReject,
    required this.onDelete,
  });

  final ConversationHistoryItem item;
  final bool busy;
  final VoidCallback onPlay;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final status = _statusPresentation(item.reviewStatus);
    final localizedStatus = context.trKnown(status.label);

    return Semantics(
      container: true,
      label:
          '$localizedStatus. ${item.vietnameseText}. ${item.outputLanguage.label}: ${item.displayedTranslation}. '
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
                HomiIconBadge(
                  icon: status.icon,
                  foregroundColor: status.color,
                  backgroundColor: isDark
                      ? Color.alphaBlend(
                          status.color.withValues(alpha: 0.14),
                          theme.colorScheme.surfaceContainerHighest,
                        )
                      : status.background,
                  size: 40,
                  iconSize: 22,
                ),
                const SizedBox(width: 10),
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
            Padding(
              padding: const EdgeInsets.only(left: 50),
              child: Text(
                item.displayedTranslation,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(left: 50),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: <Widget>[
                  _MetadataChip(label: context.trKnown(item.context.label)),
                  _MetadataChip(label: context.trKnown(_sourceLabel(item))),
                  _LearningChip(item: item),
                  _MetadataChip(
                    label: context.trKnown(_asrLabel(item.asrMode)),
                  ),
                  if (item.latency.timeToFirstAudioMs > 0)
                    _MetadataChip(
                      label: '${item.latency.timeToFirstAudioMs} ms',
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Align(
                  alignment: Alignment.centerLeft,
                  child: HomiStatusPill(
                    label: localizedStatus,
                    color: status.color,
                    icon: status.icon,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    if (item.audioUri != null)
                      IconButton(
                        onPressed: busy ? null : onPlay,
                        icon: const Icon(Icons.play_arrow_rounded),
                        tooltip: context.tr(
                          'Phát lại câu tiếng Anh',
                          '重新播放英语句子',
                        ),
                      ),
                    IconButton(
                      onPressed: busy ? null : onApprove,
                      icon: const Icon(Icons.sentiment_satisfied_alt_rounded),
                      tooltip: context.tr('Đánh dấu Đúng ý', '标记为符合原意'),
                      style: IconButton.styleFrom(
                        backgroundColor: isDark
                            ? theme.colorScheme.surfaceContainerHighest
                            : item.reviewStatus == HistoryReviewStatus.approved
                            ? AppColors.successSoft
                            : AppColors.lavender,
                        foregroundColor:
                            item.reviewStatus == HistoryReviewStatus.approved
                            ? AppColors.success
                            : theme.colorScheme.primary,
                      ),
                    ),
                    IconButton(
                      onPressed: busy ? null : onReject,
                      icon: const Icon(Icons.sentiment_dissatisfied_rounded),
                      tooltip: context.tr('Đánh dấu Sai ý', '标记为不符合原意'),
                      style: IconButton.styleFrom(
                        backgroundColor: isDark
                            ? theme.colorScheme.surfaceContainerHighest
                            : item.reviewStatus == HistoryReviewStatus.rejected
                            ? AppColors.coralSoft
                            : AppColors.lavender,
                        foregroundColor:
                            item.reviewStatus == HistoryReviewStatus.rejected
                            ? Theme.of(context).colorScheme.error
                            : theme.colorScheme.primary,
                      ),
                    ),
                    IconButton(
                      onPressed: busy ? null : onDelete,
                      icon: const Icon(Icons.delete_outline_rounded),
                      tooltip: context.tr('Xóa lượt nói', '删除记录'),
                    ),
                  ],
                ),
              ],
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

class _LearningChip extends StatelessWidget {
  const _LearningChip({required this.item});

  final ConversationHistoryItem item;

  @override
  Widget build(BuildContext context) {
    final presentation = _learningPresentation(item);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark
            ? Color.alphaBlend(
                presentation.color.withValues(alpha: 0.12),
                theme.colorScheme.surfaceContainerHighest,
              )
            : presentation.background,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(presentation.icon, size: 13, color: presentation.color),
          const SizedBox(width: 4),
          Text(
            context.trKnown(presentation.label),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: presentation.color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
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

class _StatusPresentation {
  const _StatusPresentation({
    required this.icon,
    required this.label,
    required this.color,
    required this.background,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color background;
}

_StatusPresentation _learningPresentation(ConversationHistoryItem item) {
  return switch (item.learningStatus) {
    'promoted' || 'already_rule' => const _StatusPresentation(
      icon: Icons.bolt_rounded,
      label: 'Đã tối ưu',
      color: AppColors.success,
      background: AppColors.successSoft,
    ),
    'cached' || 'observing' => _StatusPresentation(
      icon: Icons.psychology_alt_rounded,
      label: item.learningUseCount == null
          ? 'Đang học'
          : 'Đang học ${item.learningUseCount}/3',
      color: AppColors.indigo,
      background: AppColors.lavender,
    ),
    'rejected' => const _StatusPresentation(
      icon: Icons.do_not_disturb_alt_rounded,
      label: 'Không học',
      color: Color(0xFFD92D20),
      background: AppColors.coralSoft,
    ),
    'conflict' => const _StatusPresentation(
      icon: Icons.warning_amber_rounded,
      label: 'Cần kiểm tra',
      color: Color(0xFFB54708),
      background: Color(0xFFFFF4E5),
    ),
    _ => const _StatusPresentation(
      icon: Icons.info_outline_rounded,
      label: 'Chưa tối ưu',
      color: AppColors.muted,
      background: AppColors.lavenderSoft,
    ),
  };
}

_StatusPresentation _statusPresentation(HistoryReviewStatus status) {
  return switch (status) {
    HistoryReviewStatus.approved => const _StatusPresentation(
      icon: Icons.check_rounded,
      label: 'Đúng ý',
      color: AppColors.success,
      background: AppColors.successSoft,
    ),
    HistoryReviewStatus.rejected => const _StatusPresentation(
      icon: Icons.close_rounded,
      label: 'Sai ý',
      color: Color(0xFFD92D20),
      background: AppColors.coralSoft,
    ),
    HistoryReviewStatus.pending => const _StatusPresentation(
      icon: Icons.schedule_rounded,
      label: 'Chưa đánh giá',
      color: AppColors.indigo,
      background: AppColors.lavender,
    ),
  };
}

String _filterLabel(HistoryFilter filter) {
  return switch (filter) {
    HistoryFilter.all => 'Tất cả',
    HistoryFilter.approved => 'Đúng ý',
    HistoryFilter.rejected => 'Sai ý',
    HistoryFilter.pending => 'Chưa đánh giá',
  };
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
