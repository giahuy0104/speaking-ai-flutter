import 'package:ai_speaking_flutter_app/features/home/application/authored_vocabulary_suggestion_provider.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/domain/vocabulary_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads and searches the bundled production catalog', () async {
    final provider = AuthoredVocabularySuggestionProvider(
      loadCatalog: AssetListeningContentRepository().load,
    );

    final suggestions = await provider
        .call('cat', 3)
        .timeout(const Duration(seconds: 5));

    expect(suggestions, isNotEmpty);
    expect(
      suggestions.any((item) => item.englishText.toLowerCase().contains('cat')),
      isTrue,
    );
  });

  test(
    'suggests matching authored content for the selected child age',
    () async {
      final provider = AuthoredVocabularySuggestionProvider(
        loadCatalog: () async => const ListeningContentCatalog(
          groups: <ListeningContentAgeGroup>[
            ListeningContentAgeGroup(
              startAge: 3,
              endAge: 5,
              topics: <ListeningTopicContent>[
                ListeningTopicContent(
                  id: 'animals',
                  number: 1,
                  titleVi: 'Động vật',
                  titleEn: 'Animals',
                  lessons: <ListeningLessonContent>[
                    ListeningLessonContent(
                      id: 'cat',
                      number: 1,
                      titleVi: 'Con mèo',
                      titleEn: 'The cat',
                      intro: '',
                      outro: '',
                      estimatedMinutes: 3,
                      sentences: <ListeningSentenceContent>[
                        ListeningSentenceContent(
                          number: 1,
                          english: 'It is a cat.',
                          vietnamese: 'Đó là con mèo.',
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            ListeningContentAgeGroup(
              startAge: 11,
              endAge: 12,
              topics: <ListeningTopicContent>[
                ListeningTopicContent(
                  id: 'technology',
                  number: 1,
                  titleVi: 'Công nghệ',
                  titleEn: 'Technology',
                  lessons: <ListeningLessonContent>[],
                ),
              ],
            ),
          ],
        ),
      );

      final suggestions = await provider.call('con mèo', 5);

      expect(suggestions, isNotEmpty);
      expect(
        suggestions.map((item) => item.englishText),
        containsAll(<String>['The cat', 'It is a cat.']),
      );
      expect(
        suggestions.map((item) => item.englishText),
        isNot(contains('Technology')),
      );
    },
  );

  test(
    'checks duplicates across every age group and unpublished local state',
    () async {
      final provider = AuthoredVocabularySuggestionProvider(
        loadCatalog: () async => const ListeningContentCatalog(
          groups: <ListeningContentAgeGroup>[
            ListeningContentAgeGroup(
              startAge: 3,
              endAge: 5,
              topics: <ListeningTopicContent>[],
            ),
            ListeningContentAgeGroup(
              startAge: 11,
              endAge: 12,
              topics: <ListeningTopicContent>[
                ListeningTopicContent(
                  id: 'later-level',
                  number: 10,
                  titleVi: 'Tương lai',
                  titleEn: 'Future',
                  lessons: <ListeningLessonContent>[
                    ListeningLessonContent(
                      id: 'future-lesson',
                      number: 1,
                      titleVi: 'Bài học',
                      titleEn: 'Lesson',
                      intro: '',
                      outro: '',
                      estimatedMinutes: 2,
                      sentences: <ListeningSentenceContent>[
                        ListeningSentenceContent(
                          number: 1,
                          english: 'I will be a doctor.',
                          vietnamese: 'Con sẽ là bác sĩ.',
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );

      expect(
        await provider.containsInCurriculum(
          const VocabularyTranslation(
            englishText: 'I will be a doctor',
            vietnameseText: 'Con sẽ là bác sĩ',
          ),
        ),
        isTrue,
      );
      expect(
        await provider.containsInCurriculum(
          const VocabularyTranslation(
            englishText: 'I will be a pilot',
            vietnameseText: 'Con sẽ là phi công',
          ),
        ),
        isFalse,
      );
    },
  );

  test(
    'uses the nearest authored age group when age is outside the catalog',
    () async {
      final provider = AuthoredVocabularySuggestionProvider(
        loadCatalog: () async => const ListeningContentCatalog(
          groups: <ListeningContentAgeGroup>[
            ListeningContentAgeGroup(
              startAge: 6,
              endAge: 7,
              topics: <ListeningTopicContent>[
                ListeningTopicContent(
                  id: 'school',
                  number: 1,
                  titleVi: 'Trường học',
                  titleEn: 'School',
                  lessons: <ListeningLessonContent>[],
                ),
              ],
            ),
          ],
        ),
      );

      final suggestions = await provider.call('trường học', 3);

      expect(suggestions.single.englishText, 'School');
    },
  );
}
