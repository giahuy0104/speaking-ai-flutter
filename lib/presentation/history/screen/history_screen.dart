import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../app/app_theme.dart';
import '../../../app/homi_ui.dart';
import '../../../app/mascot_assets.dart';
import '../../../l10n/display_language.dart';
import '../../../features/conversation/domain/conversation_models.dart';
import '../bloc/history_bloc.dart';

part '../widgets/history_widgets.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({
    required this.createBloc,
    required this.readLanguage,
    super.key,
  });
  final HistoryBloc Function() createBloc;
  final DisplayLanguage Function() readLanguage;

  @override
  Widget build(BuildContext context) => BlocProvider<HistoryBloc>(
    create: (_) => createBloc()..add(HistoryLoadRequested()),
    child: _HistoryContent(readLanguage: readLanguage),
  );
}

class _HistoryContent extends StatefulWidget {
  const _HistoryContent({required this.readLanguage});
  final DisplayLanguage Function() readLanguage;
  @override
  State<_HistoryContent> createState() => _HistoryContentState();
}

class _HistoryContentState extends State<_HistoryContent> {
  final TextEditingController _searchController = TextEditingController();
  HistoryBloc get _bloc => context.read<HistoryBloc>();
  String _t(String vietnamese, String simplifiedChinese) =>
      widget.readLanguage().choose(vietnamese, simplifiedChinese);

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocConsumer<HistoryBloc, HistoryState>(
    listenWhen: (previous, current) =>
        previous.noticeRevision != current.noticeRevision,
    listener: (context, state) => _showNotice(state.notice!),
    builder: _buildContent,
  );

  Widget _buildContent(BuildContext context, HistoryState state) {
    final sheetHeight = math.min(
      MediaQuery.sizeOf(context).height * 0.84,
      760.0,
    );
    final visibleItems = state.visibleItems;
    final recentUserAudioItems = state.recentUserAudioItems;

    return DisplayLanguageScope(
      language: widget.readLanguage(),
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
                    count: state.items.length,
                    onRefresh: () => _bloc.add(HistoryLoadRequested()),
                    onClear: state.items.isEmpty ? null : _confirmClearHistory,
                    onClose: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchController,
                    onChanged: (value) => _bloc.add(HistoryQueryChanged(value)),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: context.tr(
                        'Tìm câu tiếng Việt hoặc tiếng Anh',
                        '搜索越南语或英语句子',
                      ),
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _searchController.clear();
                                _bloc.add(HistoryQueryChanged(''));
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
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: HistoryFilter.values
                          .map(
                            (filter) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(
                                  context.trKnown(_filterLabel(filter)),
                                ),
                                selected: state.filter == filter,
                                onSelected: (_) =>
                                    _bloc.add(HistoryFilterChanged(filter)),
                              ),
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (!state.loading &&
                      recentUserAudioItems.isNotEmpty) ...<Widget>[
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
                                      state.busyItems.contains(
                                        item.conversationId,
                                      )
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
                      loading: state.loading,
                      error: state.error,
                      hasAnyItems: state.items.isNotEmpty,
                      items: visibleItems,
                      busyItems: state.busyItems,
                      onRetry: () => _bloc.add(HistoryLoadRequested()),
                      onPlay: _playItem,
                      onReview: _reviewItem,
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

  void _playItem(ConversationHistoryItem item) =>
      _bloc.add(HistoryPlayRequested(item));
  void _playUserAudioItem(ConversationHistoryItem item) =>
      _bloc.add(HistoryPlayRequested(item, userAudio: true));
  void _reviewItem(ConversationHistoryItem item, bool approved) =>
      _bloc.add(HistoryReviewRequested(item, approved));

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

    _bloc.add(HistoryDeleteRequested(item));
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

    _bloc.add(HistoryClearRequested());
  }

  void _showNotice(HistoryNotice notice) {
    final message = switch (notice.kind) {
      HistoryNoticeKind.error => notice.message,
      HistoryNoticeKind.reviewed =>
        notice.message.isNotEmpty
            ? notice.message
            : notice.approved
            ? _t('Đã đánh dấu Đúng ý.', '已标记为符合原意。')
            : _t('Đã đánh dấu Sai ý.', '已标记为不符合原意。'),
      HistoryNoticeKind.deleted => _t(
        'Máy chủ đã xác nhận yêu cầu xóa lượt nói.',
        '服务器已确认删除这条记录。',
      ),
      HistoryNoticeKind.cleared => _t(
        'Máy chủ đã xác nhận yêu cầu xóa toàn bộ dữ liệu lịch sử.',
        '服务器已确认删除全部历史数据。',
      ),
    };
    _showMessage(message, isError: notice.kind == HistoryNoticeKind.error);
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(widget.readLanguage().translateKnown(message)),
          backgroundColor: isError
              ? Theme.of(context).colorScheme.error
              : Theme.of(context).colorScheme.inverseSurface,
        ),
      );
  }
}
