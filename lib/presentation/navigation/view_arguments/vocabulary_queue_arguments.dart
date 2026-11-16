import '../../../features/vocabulary/application/vocabulary_queue_settings.dart';
import '../../../features/vocabulary/data/vocabulary_store.dart';
import '../../../features/vocabulary/domain/vocabulary_dictionary.dart';
import '../../../features/vocabulary/domain/vocabulary_entry.dart';

/// Input data for VocabularyQueueScreen (manage hàng chờ). Carries the same
/// translate/suggest dependencies as VocabularyHomeScreen so "Thêm từ mới"
/// offers an identical add experience on both screens.
class VocabularyQueueArguments {
  const VocabularyQueueArguments({
    required this.store,
    required this.settingsStore,
    this.childAge = 5,
    this.translator,
    this.suggestionProvider,
    this.dictionaryProvider,
    this.curriculumDuplicateChecker,
  });

  final VocabularyStore store;
  final VocabularyQueueSettingsStore settingsStore;
  final int childAge;
  final VocabularyTranslator? translator;
  final VocabularySuggestionProvider? suggestionProvider;
  final VocabularyDictionaryProvider? dictionaryProvider;
  final VocabularyCurriculumDuplicateChecker? curriculumDuplicateChecker;
}
