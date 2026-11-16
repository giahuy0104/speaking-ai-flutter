import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/app_theme.dart';
import '../../../l10n/display_language.dart';
import '../application/local_vocabulary_suggestion_provider.dart';
import '../data/vocabulary_store.dart';
import '../domain/vocabulary_dictionary.dart';
import '../domain/vocabulary_entry.dart';

/// Shared "add a parent word" flow: free-text entry -> translate/dictionary
/// lookup -> pick among up to 3 suggestions -> persist. Used by both
/// VocabularyHomeScreen's "Ba mẹ đã thêm" journey and VocabularyQueueScreen,
/// so the two surfaces never drift into different add experiences.
class VocabularyAddFlowController {
  VocabularyAddFlowController({
    required this.store,
    this.childAge = 5,
    this.translator,
    this.suggestionProvider,
    this.dictionaryProvider,
    this.curriculumDuplicateChecker,
  });

  final VocabularyStore store;
  final int childAge;
  final VocabularyTranslator? translator;
  final VocabularySuggestionProvider? suggestionProvider;
  final VocabularyDictionaryProvider? dictionaryProvider;
  final VocabularyCurriculumDuplicateChecker? curriculumDuplicateChecker;

  /// Shows the add dialog, then the suggestion-confirmation dialog, then
  /// persists the chosen selections. Returns the updated entry list, or
  /// null if the parent cancelled at any step. Validation/translation
  /// failures throw VocabularyValidationException or a generic Object -
  /// callers show that message via a snackbar.
  Future<List<VocabularyEntry>?> promptAndAdd(
    BuildContext context, {
    void Function(List<VocabularyTranslation>)? onPrefetchAudio,
    VoidCallback? onInputConfirmed,
  }) async {
    final input = await showDialog<String>(
      context: context,
      builder: (_) => const AddVocabularyDialog(),
    );
    final normalized = input?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    onInputConfirmed?.call();

    final resolution = await _translate(normalized);
    if (!context.mounted) return null;
    final selections = await _prepareChoices(
      context,
      input: normalized,
      translated: resolution.primary,
      initialSuggestions: resolution.alternatives,
      partOfSpeech: resolution.partOfSpeech,
      maxSelections: 3,
    );
    if (selections == null || selections.isEmpty) return null;

    final duplicateChecker = curriculumDuplicateChecker;
    if (duplicateChecker != null) {
      for (final selection in selections) {
        if (await duplicateChecker(selection)) {
          throw const VocabularyTopicDuplicateException();
        }
      }
    }
    final entries = await store.addParentEntries(
      selections,
      childAge: childAge,
    );
    onPrefetchAudio?.call(selections);
    return entries;
  }

  Future<List<VocabularyTranslation>?> _prepareChoices(
    BuildContext context, {
    required String input,
    required VocabularyTranslation translated,
    List<VocabularyTranslation> initialSuggestions =
        const <VocabularyTranslation>[],
    String? partOfSpeech,
    required int maxSelections,
  }) async {
    VocabularyValidationException? originalError;
    var originalAccepted = true;
    try {
      await store.validateParentCandidate(translated, childAge: childAge);
      final duplicateChecker = curriculumDuplicateChecker;
      if (duplicateChecker != null && await duplicateChecker(translated)) {
        throw const VocabularyTopicDuplicateException();
      }
    } on VocabularyDuplicateException {
      rethrow;
    } on VocabularyTopicDuplicateException {
      rethrow;
    } on VocabularyValidationException catch (error) {
      originalAccepted = false;
      originalError = error;
    }

    final candidates = <VocabularyTranslation>[
      if (originalAccepted) translated,
      ...initialSuggestions,
      ...approvedVocabularySuggestionsFor(translated),
    ];
    const targetOptionCount = 3;
    var options = await _filterSuggestions(
      candidates,
      limit: targetOptionCount,
    );
    final provider = suggestionProvider;
    if (provider != null && options.length < targetOptionCount) {
      try {
        final authoredSuggestions = await provider(input, childAge);
        options = await _filterSuggestions(<VocabularyTranslation>[
          ...options,
          ...authoredSuggestions,
        ], limit: targetOptionCount);
      } catch (error) {
        debugPrint('VOCABULARY_SUGGESTION_FALLBACK_FAILED error=$error');
      }
    }
    if (options.length < targetOptionCount) {
      const localProvider = LocalVocabularySuggestionProvider();
      final localSuggestions = <VocabularyTranslation>[
        ...localProvider.suggest(base: translated, partOfSpeech: partOfSpeech),
        if (partOfSpeech?.trim().isNotEmpty ?? false)
          ...localProvider.suggest(base: translated),
      ];
      options = await _filterSuggestions(<VocabularyTranslation>[
        ...options,
        ...localSuggestions,
      ], limit: targetOptionCount);
    }
    if (options.length < targetOptionCount) {
      if (originalError != null) throw originalError;
      throw const VocabularyValidationException(
        'Chưa tạo đủ 3 phương án phù hợp. Ba mẹ thử nội dung khác nhé.',
      );
    }
    if (!context.mounted) return null;
    return showDialog<List<VocabularyTranslation>>(
      context: context,
      builder: (_) => VocabularySuggestionDialog(
        options: options,
        maxSelections: maxSelections,
      ),
    );
  }

  Future<List<VocabularyTranslation>> _filterSuggestions(
    Iterable<VocabularyTranslation> candidates, {
    required int limit,
  }) async {
    final candidateList = candidates.toList(growable: false);
    final locallyValid = await store.filterParentSuggestions(
      candidateList,
      limit: candidateList.length,
      childAge: childAge,
    );
    final duplicateChecker = curriculumDuplicateChecker;
    if (duplicateChecker == null) {
      return locallyValid.take(limit).toList(growable: false);
    }
    final result = <VocabularyTranslation>[];
    for (final candidate in locallyValid) {
      if (!await duplicateChecker(candidate)) {
        result.add(candidate);
        if (result.length >= limit) break;
      }
    }
    return result;
  }

  Future<VocabularyTranslationResolution> _translate(String input) async {
    const pairs = <String, VocabularyTranslation>{
      'apple': VocabularyTranslation(
        englishText: 'Apple',
        vietnameseText: 'Quả táo',
      ),
      'quả táo': VocabularyTranslation(
        englishText: 'Apple',
        vietnameseText: 'Quả táo',
      ),
      'family': VocabularyTranslation(
        englishText: 'Family',
        vietnameseText: 'Gia đình',
      ),
      'gia đình': VocabularyTranslation(
        englishText: 'Family',
        vietnameseText: 'Gia đình',
      ),
      'school': VocabularyTranslation(
        englishText: 'School',
        vietnameseText: 'Trường học',
      ),
      'trường học': VocabularyTranslation(
        englishText: 'School',
        vietnameseText: 'Trường học',
      ),
      'happy': VocabularyTranslation(
        englishText: 'Happy',
        vietnameseText: 'Vui vẻ',
      ),
      'vui vẻ': VocabularyTranslation(
        englishText: 'Happy',
        vietnameseText: 'Vui vẻ',
      ),
      'hello': VocabularyTranslation(
        englishText: 'Hello',
        vietnameseText: 'Xin chào',
      ),
      'xin chào': VocabularyTranslation(
        englishText: 'Hello',
        vietnameseText: 'Xin chào',
      ),
      'thank you': VocabularyTranslation(
        englishText: 'Thank you',
        vietnameseText: 'Cảm ơn',
      ),
      'cảm ơn': VocabularyTranslation(
        englishText: 'Thank you',
        vietnameseText: 'Cảm ơn',
      ),
    };
    final normalized = input.toLowerCase();
    final known = pairs[normalized];
    if (known != null) {
      return VocabularyTranslationResolution(primary: known);
    }

    if (!_containsVietnameseCharacters(input)) {
      final dictionary = dictionaryProvider;
      if (dictionary != null) {
        try {
          final result = await dictionary.lookupEnglish(input);
          if (result != null && result.definitions.isNotEmpty) {
            final seenMeanings = <String>{};
            final meanings = result.definitions
                .map(
                  (definition) => VocabularyTranslation(
                    englishText: _capitalize(result.english),
                    vietnameseText: _capitalize(definition.vietnamese),
                  ),
                )
                .where(
                  (translation) => seenMeanings.add(
                    normalizedVocabularyText(translation.vietnameseText),
                  ),
                )
                .take(2)
                .toList(growable: false);
            if (meanings.isNotEmpty) {
              return VocabularyTranslationResolution(
                primary: meanings.first,
                alternatives: meanings.skip(1).toList(growable: false),
                partOfSpeech: result.definitions.first.partOfSpeech,
              );
            }
          }
        } catch (error) {
          debugPrint('VOCABULARY_DICTIONARY_LOOKUP_FAILED error=$error');
        }
      }
    }

    final translatorFn = translator;
    if (translatorFn == null) {
      throw StateError('Không có dịch vụ dịch từ vựng.');
    }
    final translated = await translatorFn(input);
    final englishText = _capitalize(translated.englishText.trim());
    final vietnameseText = _capitalize(
      translated.vietnameseText.trim().isEmpty
          ? input
          : translated.vietnameseText.trim(),
    );
    if (englishText.isEmpty || _containsVietnameseCharacters(englishText)) {
      throw StateError('Bản dịch tiếng Anh không hợp lệ.');
    }
    return VocabularyTranslationResolution(
      primary: VocabularyTranslation(
        englishText: englishText,
        vietnameseText: vietnameseText,
      ),
    );
  }
}

class VocabularyTranslationResolution {
  const VocabularyTranslationResolution({
    required this.primary,
    this.alternatives = const <VocabularyTranslation>[],
    this.partOfSpeech,
  });

  final VocabularyTranslation primary;
  final List<VocabularyTranslation> alternatives;
  final String? partOfSpeech;
}

String _capitalize(String value) =>
    value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';

bool _containsVietnameseCharacters(String value) => RegExp(
  r'[ăâđêôơưáàảãạấầẩẫậắằẳẵặéèẻẽẹếềểễệíìỉĩịóòỏõọốồổỗộớờởỡợúùủũụứừửữựýỳỷỹỵ]',
  caseSensitive: false,
).hasMatch(value);

String normalizedVocabularyText(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll('’', "'")
    .replaceAll(RegExp(r"[\s.,!?;:…_-]+"), ' ')
    .trim();

/// Hand-authored follow-up suggestions for a handful of starter words, used
/// to pad the suggestion dialog to 3 options when other sources fall short.
List<VocabularyTranslation> approvedVocabularySuggestionsFor(
  VocabularyTranslation translated,
) {
  const catalog = <String, List<VocabularyTranslation>>{
    'apple': <VocabularyTranslation>[
      VocabularyTranslation(
        englishText: 'Red apple',
        vietnameseText: 'Quả táo đỏ',
      ),
      VocabularyTranslation(
        englishText: 'Green apple',
        vietnameseText: 'Quả táo xanh',
      ),
      VocabularyTranslation(
        englishText: 'I like apples',
        vietnameseText: 'Con thích táo',
      ),
    ],
    'family': <VocabularyTranslation>[
      VocabularyTranslation(
        englishText: 'My family',
        vietnameseText: 'Gia đình của con',
      ),
      VocabularyTranslation(
        englishText: 'This is my mother',
        vietnameseText: 'Đây là mẹ của con',
      ),
      VocabularyTranslation(
        englishText: 'This is my father',
        vietnameseText: 'Đây là bố của con',
      ),
    ],
    'school': <VocabularyTranslation>[
      VocabularyTranslation(
        englishText: 'My school',
        vietnameseText: 'Trường của con',
      ),
      VocabularyTranslation(
        englishText: 'I go to school',
        vietnameseText: 'Con đi học',
      ),
      VocabularyTranslation(
        englishText: 'This is my classroom',
        vietnameseText: 'Đây là lớp học của con',
      ),
    ],
    'happy': <VocabularyTranslation>[
      VocabularyTranslation(
        englishText: 'I am happy',
        vietnameseText: 'Con vui',
      ),
      VocabularyTranslation(
        englishText: 'A happy day',
        vietnameseText: 'Một ngày vui',
      ),
      VocabularyTranslation(
        englishText: 'You make me happy',
        vietnameseText: 'Bạn làm con vui',
      ),
    ],
    'hello': <VocabularyTranslation>[
      VocabularyTranslation(
        englishText: 'Hello, Mom',
        vietnameseText: 'Con chào mẹ',
      ),
      VocabularyTranslation(
        englishText: 'Hello, Dad',
        vietnameseText: 'Con chào bố',
      ),
      VocabularyTranslation(
        englishText: 'Hello, my friend',
        vietnameseText: 'Chào bạn của mình',
      ),
    ],
    'thank you': <VocabularyTranslation>[
      VocabularyTranslation(
        englishText: 'Thank you, Mom',
        vietnameseText: 'Con cảm ơn mẹ',
      ),
      VocabularyTranslation(
        englishText: 'Thank you, Dad',
        vietnameseText: 'Con cảm ơn bố',
      ),
      VocabularyTranslation(
        englishText: 'Thank you for helping me',
        vietnameseText: 'Cảm ơn bạn đã giúp con',
      ),
    ],
  };
  return catalog[normalizedVocabularyText(translated.englishText)] ??
      const <VocabularyTranslation>[];
}

class AddVocabularyDialog extends StatefulWidget {
  const AddVocabularyDialog({super.key});

  @override
  State<AddVocabularyDialog> createState() => _AddVocabularyDialogState();
}

class _AddVocabularyDialogState extends State<AddVocabularyDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _controller.addListener(_refresh);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_refresh)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _controller.text.trim().isNotEmpty;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenWidth = MediaQuery.sizeOf(context).width;
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: screenWidth * 0.05,
        vertical: 24,
      ),
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: SizedBox(
        width: screenWidth * 0.9,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: Text(
                  context.tr('Thêm nội dung học', '添加学习内容'),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontSize: 23,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('add-vocabulary-field'),
                controller: _controller,
                autofocus: true,
                minLines: 3,
                maxLines: 5,
                textInputAction: TextInputAction.done,
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontSize: 16,
                ),
                decoration: InputDecoration(
                  hintText: context.tr(
                    'Nhập từ, cụm từ hoặc câu ngắn',
                    '输入单词、短语或短句',
                  ),
                  filled: true,
                  fillColor: isDark
                      ? theme.colorScheme.surfaceContainer
                      : AppColors.lavenderSoft,
                  hintStyle: const TextStyle(fontSize: 15),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide(
                      color: isDark
                          ? theme.colorScheme.outline
                          : AppColors.indigo,
                      width: 1.5,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide(
                      color: isDark
                          ? theme.colorScheme.secondary
                          : AppColors.indigo,
                      width: 2,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 18,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.tr(
                  'Có thể nhập bằng tiếng Anh hoặc tiếng Việt.',
                  '可以输入英文或越南文。',
                ),
                maxLines: 2,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(context.tr('Hủy', '取消')),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    key: const Key('confirm-add-vocabulary'),
                    onPressed: enabled
                        ? () => Navigator.of(context).pop(_controller.text)
                        : null,
                    icon: const Icon(Icons.add_rounded),
                    label: Text(context.tr('Thêm', '添加')),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(104, 46),
                      backgroundColor: isDark
                          ? theme.colorScheme.primary
                          : AppColors.indigo,
                      foregroundColor: isDark
                          ? theme.colorScheme.onPrimary
                          : Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _refresh() => setState(() {});
}

class VocabularySuggestionDialog extends StatefulWidget {
  const VocabularySuggestionDialog({
    required this.options,
    required this.maxSelections,
    super.key,
  });

  final List<VocabularyTranslation> options;
  final int maxSelections;

  @override
  State<VocabularySuggestionDialog> createState() =>
      _VocabularySuggestionDialogState();
}

class _VocabularySuggestionDialogState
    extends State<VocabularySuggestionDialog> {
  final Set<int> _selectedIndexes = <int>{0};
  late final List<TextEditingController> _englishControllers;
  late final List<TextEditingController> _vietnameseControllers;
  late final List<FocusNode> _englishFocusNodes;
  late final List<FocusNode> _vietnameseFocusNodes;
  int? _editingIndex;

  @override
  void initState() {
    super.initState();
    _englishControllers = <TextEditingController>[
      for (final option in widget.options)
        TextEditingController(text: option.englishText),
    ];
    _vietnameseControllers = <TextEditingController>[
      for (final option in widget.options)
        TextEditingController(text: option.vietnameseText),
    ];
    _englishFocusNodes = <FocusNode>[
      for (var index = 0; index < widget.options.length; index++) FocusNode(),
    ];
    _vietnameseFocusNodes = <FocusNode>[
      for (var index = 0; index < widget.options.length; index++) FocusNode(),
    ];
    for (final controller in <TextEditingController>[
      ..._englishControllers,
      ..._vietnameseControllers,
    ]) {
      controller.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    for (final controller in <TextEditingController>[
      ..._englishControllers,
      ..._vietnameseControllers,
    ]) {
      controller
        ..removeListener(_refresh)
        ..dispose();
    }
    for (final focusNode in <FocusNode>[
      ..._englishFocusNodes,
      ..._vietnameseFocusNodes,
    ]) {
      focusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final mediaQuery = MediaQuery.of(context);
    final maxSelections = widget.maxSelections.clamp(1, 3);
    final availableHeight =
        mediaQuery.size.height - mediaQuery.viewInsets.vertical - 48;
    final maxDialogHeight = availableHeight.clamp(320.0, 720.0).toDouble();

    return Dialog(
      key: const Key('vocabulary-suggestion-dialog'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 520, maxHeight: maxDialogHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: colorScheme.secondaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.playlist_add_check_circle_rounded,
                      color: colorScheme.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          context.tr('Chọn nội dung phù hợp', '选择合适的内容'),
                          style: theme.textTheme.titleLarge,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const Key('close-vocabulary-suggestions'),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: context.tr('Đóng', '关闭'),
                  ),
                ],
              ),
            ),
            Divider(color: colorScheme.outlineVariant),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    for (var index = 0; index < widget.options.length; index++)
                      if (_editingIndex == null || _editingIndex == index)
                        _buildSuggestionCard(context, index),
                    if (_editingIndex == null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          key: const Key('vocabulary-minhqnd-attribution'),
                          onPressed: () => unawaited(
                            launchUrl(
                              Uri.parse('https://dict.minhqnd.com/'),
                              mode: LaunchMode.externalApplication,
                            ),
                          ),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 10,
                            ),
                            alignment: Alignment.centerLeft,
                          ),
                          icon: const Icon(
                            Icons.info_outline_rounded,
                            size: 18,
                          ),
                          label: Text(
                            context.tr(
                              'Nguồn từ điển và phát âm: @minhqnd '
                                  '(CC BY-SA 4.0)',
                              '词典及发音来源：@minhqnd (CC BY-SA 4.0)',
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Divider(color: colorScheme.outlineVariant),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Row(
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        context.tr(
                          '${_selectedIndexes.length}/$maxSelections đã chọn',
                          '已选 ${_selectedIndexes.length}/$maxSelections',
                        ),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.onSecondaryContainer,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(context.tr('Hủy', '取消')),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      key: const Key('confirm-vocabulary-suggestions'),
                      onPressed: !_canSubmit || _editingIndex != null
                          ? null
                          : () => Navigator.of(context)
                                .pop(<VocabularyTranslation>[
                                  for (final index
                                      in _selectedIndexes.toList()..sort())
                                    VocabularyTranslation(
                                      englishText: _englishControllers[index]
                                          .text
                                          .trim(),
                                      vietnameseText:
                                          _vietnameseControllers[index].text
                                              .trim(),
                                    ),
                                ]),
                      icon: const Icon(Icons.add_task_rounded, size: 20),
                      label: Text(context.tr('Thêm', '添加')),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionCard(BuildContext context, int index) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selected = _selectedIndexes.contains(index);
    final isEditing = _editingIndex == index;
    return Container(
      key: ValueKey<String>('vocabulary-suggestion-$index'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? colorScheme.primary : colorScheme.outlineVariant,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Checkbox(
                key: ValueKey<String>('select-vocabulary-suggestion-$index'),
                value: selected,
                onChanged: isEditing
                    ? null
                    : (value) => _toggleSelection(index, value),
              ),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: isEditing
                      ? null
                      : () => _toggleSelection(index, !selected),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      context.tr('Gợi ý ${index + 1}', '建议 ${index + 1}'),
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (!isEditing)
                IconButton.filledTonal(
                  key: ValueKey<String>('edit-vocabulary-suggestion-$index'),
                  onPressed: () => _editSuggestion(index),
                  icon: const Icon(Icons.edit_rounded, size: 21),
                  tooltip: context.tr(
                    'Chỉnh sửa gợi ý ${index + 1}',
                    '编辑建议 ${index + 1}',
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          TextField(
            key: ValueKey<String>('vocabulary-suggestion-english-$index'),
            controller: _englishControllers[index],
            focusNode: _englishFocusNodes[index],
            readOnly: !isEditing,
            showCursor: isEditing,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            maxLines: 2,
            onSubmitted: isEditing
                ? (_) => _vietnameseFocusNodes[index].requestFocus()
                : null,
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            decoration: InputDecoration(
              labelText: context.tr('Tiếng Anh', '英语'),
              prefixIcon: const Icon(Icons.translate_rounded, size: 21),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            key: ValueKey<String>('vocabulary-suggestion-vietnamese-$index'),
            controller: _vietnameseControllers[index],
            focusNode: _vietnameseFocusNodes[index],
            readOnly: !isEditing,
            showCursor: isEditing,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            maxLines: 2,
            onSubmitted: isEditing ? (_) => _saveSuggestion(index) : null,
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            decoration: InputDecoration(
              labelText: context.tr('Tiếng Việt', '越南语'),
              prefixIcon: const Icon(
                Icons.chat_bubble_outline_rounded,
                size: 21,
              ),
            ),
          ),
          if (isEditing) ...<Widget>[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: ValueKey<String>('save-vocabulary-suggestion-$index'),
                onPressed: _canSave(index)
                    ? () => _saveSuggestion(index)
                    : null,
                icon: const Icon(Icons.check_rounded, size: 21),
                label: Text(context.tr('Lưu chỉnh sửa', '保存修改')),
              ),
            ),
          ],
        ],
      ),
    );
  }

  bool get _canSubmit =>
      _selectedIndexes.isNotEmpty &&
      _selectedIndexes.every(
        (index) =>
            _englishControllers[index].text.trim().isNotEmpty &&
            _vietnameseControllers[index].text.trim().isNotEmpty,
      );

  void _toggleSelection(int index, bool? selected) {
    if (selected == true &&
        !_selectedIndexes.contains(index) &&
        _selectedIndexes.length >= widget.maxSelections.clamp(1, 3)) {
      return;
    }
    setState(() {
      if (selected == true) {
        _selectedIndexes.add(index);
      } else {
        _selectedIndexes.remove(index);
      }
    });
  }

  void _editSuggestion(int index) {
    setState(() => _editingIndex = index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _englishFocusNodes[index].requestFocus();
    });
  }

  bool _canSave(int index) =>
      _englishControllers[index].text.trim().isNotEmpty &&
      _vietnameseControllers[index].text.trim().isNotEmpty;

  void _saveSuggestion(int index) {
    if (!_canSave(index)) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      final maxSelections = widget.maxSelections.clamp(1, 3);
      if (!_selectedIndexes.contains(index) &&
          _selectedIndexes.length >= maxSelections) {
        _selectedIndexes.remove(_selectedIndexes.first);
      }
      _selectedIndexes.add(index);
      _editingIndex = null;
    });
  }

  void _refresh() => setState(() {});
}
