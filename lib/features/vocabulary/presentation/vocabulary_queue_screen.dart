import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../l10n/display_language.dart';
import '../application/vocabulary_queue_settings.dart';
import '../data/vocabulary_store.dart';
import '../domain/vocabulary_dictionary.dart';
import '../domain/vocabulary_entry.dart';
import 'vocabulary_add_flow.dart';

/// Full CRUD + reorder + words-per-day setting for the parent waiting queue.
/// Reachable from VocabularyHomeScreen's "Ba mẹ đã thêm" journey. Adding a
/// word uses the same translate/suggest flow as "Ba mẹ đã thêm" so both
/// surfaces offer an identical add experience.
class VocabularyQueueScreen extends StatefulWidget {
  const VocabularyQueueScreen({
    required this.store,
    required this.settingsStore,
    this.childAge = 5,
    this.translator,
    this.suggestionProvider,
    this.dictionaryProvider,
    this.curriculumDuplicateChecker,
    super.key,
  });

  final VocabularyStore store;
  final VocabularyQueueSettingsStore settingsStore;
  final int childAge;
  final VocabularyTranslator? translator;
  final VocabularySuggestionProvider? suggestionProvider;
  final VocabularyDictionaryProvider? dictionaryProvider;
  final VocabularyCurriculumDuplicateChecker? curriculumDuplicateChecker;

  @override
  State<VocabularyQueueScreen> createState() => _VocabularyQueueScreenState();
}

class _VocabularyQueueScreenState extends State<VocabularyQueueScreen> {
  List<VocabularyEntry> _waiting = const <VocabularyEntry>[];
  List<VocabularyEntry> _today = const <VocabularyEntry>[];
  int _wordsPerDay = defaultVocabularyWordsPerDay;
  bool _loading = true;
  bool _hasAssignedTodayBatch = false;
  StreamSubscription<void>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = widget.store.changes.listen((_) => unawaited(_load()));
    unawaited(_load());
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final entries = await widget.store.read();
    final wordsPerDay = await widget.settingsStore.readWordsPerDay();
    if (!mounted) return;
    final today = VocabularyStore.dayKey(DateTime.now());
    setState(() {
      _waiting = entries.where((entry) => entry.isWaitingParent).toList()
        ..sort(
          (a, b) => a.effectiveQueueOrder.compareTo(b.effectiveQueueOrder),
        );
      _today = entries.where((entry) => entry.isTodayParent).toList()
        ..sort(
          (a, b) => a.effectiveQueueOrder.compareTo(b.effectiveQueueOrder),
        );
      _wordsPerDay = wordsPerDay;
      _hasAssignedTodayBatch = entries.any(
        (entry) => entry.isParentAdded && entry.todayDayKey == today,
      );
      _loading = false;
    });
  }

  Future<void> _changeWordsPerDay(int delta) async {
    final next = clampVocabularyWordsPerDay(_wordsPerDay + delta);
    if (next == _wordsPerDay) return;
    await widget.settingsStore.writeWordsPerDay(next);
    if (!mounted) return;
    setState(() => _wordsPerDay = next);
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    final updated = List<VocabularyEntry>.of(_waiting);
    final moved = updated.removeAt(oldIndex);
    updated.insert(newIndex, moved);
    setState(() => _waiting = updated);
    await widget.store.reorderWaitingEntries(
      updated.map((entry) => entry.id).toList(growable: false),
    );
  }

  Future<void> _delete(VocabularyEntry entry) async {
    try {
      await widget.store.deleteParentEntry(entry.id, dailyLimit: _wordsPerDay);
    } on VocabularyValidationException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _edit(VocabularyEntry entry) async {
    final result = await showDialog<VocabularyTranslation>(
      context: context,
      builder: (_) => _EditQueueEntryDialog(entry: entry),
    );
    if (result == null) return;
    try {
      await widget.store.updateParentEntry(entryId: entry.id, value: result);
    } on VocabularyValidationException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _add() async {
    final controller = VocabularyAddFlowController(
      store: widget.store,
      childAge: widget.childAge,
      translator: widget.translator,
      suggestionProvider: widget.suggestionProvider,
      dictionaryProvider: widget.dictionaryProvider,
      curriculumDuplicateChecker: widget.curriculumDuplicateChecker,
    );
    try {
      await controller.promptAndAdd(context);
    } on VocabularyValidationException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              'Chưa xử lý được nội dung này. Ba mẹ thử lại nhé.',
              '暂时无法处理此内容，请重试。',
            ),
          ),
        ),
      );
    }
  }

  List<VocabularyEntry> get _upcoming =>
      _waiting.take(_wordsPerDay).toList(growable: false);

  int _daysUntilDue(int index) => (index / _wordsPerDay).ceil();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      key: const Key('vocabulary-queue-screen'),
      appBar: AppBar(
        title: Text(context.tr('Quản lý hàng chờ', '管理等待列表')),
        actions: <Widget>[
          IconButton(
            key: const Key('vocabulary-queue-add-button'),
            tooltip: context.tr('Thêm từ mới', '添加新词'),
            onPressed: () => unawaited(_add()),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              children: <Widget>[
                _buildWordsPerDayCard(context, isDark),
                const SizedBox(height: 16),
                if (_today.isNotEmpty) ...<Widget>[
                  _buildTodayWordsCard(context, isDark),
                  const SizedBox(height: 20),
                ],
                if (_upcoming.isNotEmpty) ...<Widget>[
                  _buildUpcomingPreviewCard(context, isDark),
                  const SizedBox(height: 20),
                ],
                Container(
                  key: const Key('vocabulary-queue-waiting-card'),
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkSurfaceRaised
                        : AppColors.mintSoft,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: isDark
                          ? AppColors.darkMint.withValues(alpha: 0.48)
                          : AppColors.success.withValues(alpha: 0.34),
                      width: 1.5,
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: isDark
                            ? Colors.black.withValues(alpha: 0.18)
                            : AppColors.deepNavy.withValues(alpha: 0.07),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              context.tr('Danh sách chờ', '等待列表'),
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          Text(
                            context.tr(
                              '${_waiting.length} từ · kéo để sắp xếp',
                              '${_waiting.length} 个 · 拖动排序',
                            ),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: isDark
                                      ? AppColors.darkMuted
                                      : AppColors.muted,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_waiting.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            context.tr(
                              'Chưa có từ nào trong hàng chờ.',
                              '等待列表为空。',
                            ),
                            style: TextStyle(
                              color: isDark
                                  ? AppColors.darkMuted
                                  : AppColors.muted,
                            ),
                          ),
                        )
                      else
                        ReorderableListView.builder(
                          key: const Key('vocabulary-queue-reorder-list'),
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          buildDefaultDragHandles: false,
                          itemCount: _waiting.length,
                          onReorderItem: (oldIndex, newIndex) =>
                              unawaited(_reorder(oldIndex, newIndex)),
                          itemBuilder: (itemContext, index) {
                            final entry = _waiting[index];
                            final isDue = index < _wordsPerDay;
                            return Padding(
                              key: ValueKey<String>('queue-item-${entry.id}'),
                              padding: const EdgeInsets.only(bottom: 9),
                              child: Opacity(
                                opacity: isDue ? 1 : 0.55,
                                child: Container(
                                  padding: const EdgeInsets.fromLTRB(
                                    10,
                                    10,
                                    6,
                                    10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? AppColors.darkSurfaceStrong
                                              .withValues(alpha: 0.82)
                                        : Colors.white.withValues(alpha: 0.84),
                                    borderRadius: BorderRadius.circular(17),
                                    border: Border.all(
                                      color: isDark
                                          ? AppColors.darkOutline
                                          : AppColors.mintBorder,
                                    ),
                                    boxShadow: <BoxShadow>[
                                      BoxShadow(
                                        color: isDark
                                            ? Colors.black.withValues(
                                                alpha: 0.12,
                                              )
                                            : AppColors.primaryNavy.withValues(
                                                alpha: 0.05,
                                              ),
                                        blurRadius: 10,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    children: <Widget>[
                                      ReorderableDragStartListener(
                                        index: index,
                                        child: const Padding(
                                          padding: EdgeInsets.only(right: 10),
                                          child: Icon(
                                            Icons.drag_indicator_rounded,
                                            size: 20,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: <Widget>[
                                            Text(
                                              entry.word,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleSmall
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                            ),
                                            Text(
                                              entry.meaning,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: isDark
                                                        ? AppColors.darkMuted
                                                        : AppColors.muted,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (isDue) ...<Widget>[
                                        IconButton.filledTonal(
                                          key: ValueKey<String>(
                                            'queue-edit-${entry.id}',
                                          ),
                                          onPressed: () =>
                                              unawaited(_edit(entry)),
                                          icon: const Icon(
                                            Icons.edit_rounded,
                                            size: 20,
                                          ),
                                          tooltip: context.tr('Sửa', '编辑'),
                                        ),
                                        IconButton.filledTonal(
                                          key: ValueKey<String>(
                                            'queue-delete-${entry.id}',
                                          ),
                                          onPressed: () =>
                                              unawaited(_delete(entry)),
                                          style: IconButton.styleFrom(
                                            foregroundColor: isDark
                                                ? AppColors.darkPink
                                                : AppColors.accentPink,
                                            backgroundColor: isDark
                                                ? AppColors.darkPink.withValues(
                                                    alpha: 0.14,
                                                  )
                                                : AppColors.accentPinkSoft,
                                          ),
                                          icon: const Icon(
                                            Icons.delete_outline_rounded,
                                            size: 20,
                                          ),
                                          tooltip: context.tr('Xóa', '删除'),
                                        ),
                                      ] else
                                        Text(
                                          context.tr(
                                            'chờ thêm ${_daysUntilDue(index)} ngày',
                                            '还需等待 ${_daysUntilDue(index)} 天',
                                          ),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: isDark
                                                    ? AppColors.darkMuted
                                                    : AppColors.muted,
                                              ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildWordsPerDayCard(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceRaised : AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? AppColors.darkOutline : AppColors.mintBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            context.tr('Số từ bé học mỗi ngày', '每天学习的词数'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: isDark ? AppColors.darkMuted : AppColors.muted,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              IconButton(
                key: const Key('vocabulary-queue-words-per-day-minus'),
                onPressed: () => unawaited(_changeWordsPerDay(-1)),
                icon: const Icon(Icons.remove_circle_outline_rounded),
              ),
              Expanded(
                child: Text(
                  '$_wordsPerDay',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                key: const Key('vocabulary-queue-words-per-day-plus'),
                onPressed: () => unawaited(_changeWordsPerDay(1)),
                icon: const Icon(Icons.add_circle_outline_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTodayWordsCard(BuildContext context, bool isDark) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('vocabulary-queue-today-words'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceRaised : AppColors.mintSoft,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark
              ? AppColors.darkMint.withValues(alpha: 0.48)
              : AppColors.success.withValues(alpha: 0.34),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.menu_book_rounded,
                size: 18,
                color: isDark ? AppColors.darkMint : AppColors.success,
              ),
              const SizedBox(width: 8),
              Text(
                context.tr(
                  'Từ vựng hôm nay · ${_today.length} từ',
                  '今天要学 · ${_today.length} 个',
                ),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final entry in _today)
            Padding(
              key: ValueKey<String>('queue-today-word-${entry.id}'),
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    entry.todayStatus == TodayVocabularyStatus.heard
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 18,
                    color: entry.todayStatus == TodayVocabularyStatus.heard
                        ? (isDark ? AppColors.darkMint : AppColors.success)
                        : (isDark ? AppColors.darkMuted : AppColors.muted),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          entry.word,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          entry.meaning,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: isDark
                                ? AppColors.darkMuted
                                : AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildUpcomingPreviewCard(BuildContext context, bool isDark) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('vocabulary-queue-tomorrow-preview'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurfaceRaised
            : AppColors.primaryNavy.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark
              ? AppColors.darkPrimary.withValues(alpha: 0.48)
              : AppColors.primaryNavy.withValues(alpha: 0.24),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.calendar_month_rounded,
                size: 18,
                color: isDark ? AppColors.darkPrimary : AppColors.primaryNavy,
              ),
              const SizedBox(width: 8),
              Text(
                _hasAssignedTodayBatch
                    ? context.tr('Từ học hôm sau', '明天要学')
                    : context.tr('Từ học hôm nay', '今天要学'),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: isDark ? AppColors.darkPrimary : AppColors.primaryNavy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final (i, entry) in _upcoming.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Padding(
                    padding: EdgeInsets.only(right: 10),
                    child: Text(
                      "${i + 1}.",
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          entry.word,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          entry.meaning,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: isDark
                                    ? AppColors.darkMuted
                                    : AppColors.muted,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _EditQueueEntryDialog extends StatefulWidget {
  const _EditQueueEntryDialog({required this.entry});

  final VocabularyEntry entry;

  @override
  State<_EditQueueEntryDialog> createState() => _EditQueueEntryDialogState();
}

class _EditQueueEntryDialogState extends State<_EditQueueEntryDialog> {
  late final TextEditingController _wordController;
  late final TextEditingController _meaningController;

  @override
  void initState() {
    super.initState();
    _wordController = TextEditingController(text: widget.entry.word);
    _meaningController = TextEditingController(text: widget.entry.meaning);
  }

  @override
  void dispose() {
    _wordController.dispose();
    _meaningController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr('Sửa từ', '编辑词')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _wordController,
            decoration: InputDecoration(
              labelText: context.tr('Từ tiếng Anh', '英文单词'),
            ),
          ),
          TextField(
            controller: _meaningController,
            decoration: InputDecoration(
              labelText: context.tr('Nghĩa tiếng Việt', '越南语意思'),
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('Hủy', '取消')),
        ),
        FilledButton(
          onPressed: () {
            final word = _wordController.text.trim();
            final meaning = _meaningController.text.trim();
            if (word.isEmpty || meaning.isEmpty) return;
            Navigator.of(context).pop(
              VocabularyTranslation(englishText: word, vietnameseText: meaning),
            );
          },
          child: Text(context.tr('Lưu', '保存')),
        ),
      ],
    );
  }
}
