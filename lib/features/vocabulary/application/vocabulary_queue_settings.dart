import 'package:shared_preferences/shared_preferences.dart';

/// How many parent-added words move from the waiting queue into "today"
/// each day. Configurable by the parent in the manage-queue screen.
abstract interface class VocabularyQueueSettingsStore {
  Future<int> readWordsPerDay();

  Future<void> writeWordsPerDay(int wordsPerDay);
}

const int defaultVocabularyWordsPerDay = 5;
const int minVocabularyWordsPerDay = 1;
const int maxVocabularyWordsPerDay = 20;

int clampVocabularyWordsPerDay(int value) =>
    value.clamp(minVocabularyWordsPerDay, maxVocabularyWordsPerDay);

class SharedPreferencesVocabularyQueueSettingsStore
    implements VocabularyQueueSettingsStore {
  const SharedPreferencesVocabularyQueueSettingsStore();

  static const String _wordsPerDayKey =
      'homi.vocabulary.parent-words-per-day.v1';

  @override
  Future<int> readWordsPerDay() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final stored = preferences.getInt(_wordsPerDayKey);
      if (stored == null) return defaultVocabularyWordsPerDay;
      return clampVocabularyWordsPerDay(stored);
    } catch (_) {
      return defaultVocabularyWordsPerDay;
    }
  }

  @override
  Future<void> writeWordsPerDay(int wordsPerDay) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(
      _wordsPerDayKey,
      clampVocabularyWordsPerDay(wordsPerDay),
    );
  }
}
