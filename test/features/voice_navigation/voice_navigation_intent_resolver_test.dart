import 'package:ai_speaking_flutter_app/features/voice_navigation/application/voice_navigation_intent_resolver.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/domain/master_navigation_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const resolver = VoiceNavigationIntentResolver();

  group('VoiceNavigationIntentResolver', () {
    test(
      'recognizes complete numbered topic commands without an action verb',
      () {
        for (final entry in <String, int>{
          'Chủ đề số 1': 1,
          'Chủ đề số 2': 2,
          'Chủ đề số 3': 3,
          'chủ đề số một': 1,
          'chu de so hai': 2,
          'Chủ đề ba nhé': 3,
          'Con muốn học chủ đề số ba': 3,
          'Mở chủ đề mười một': 11,
          'Topic number one': 1,
          'Topic two': 2,
          'Open topic number three please': 3,
        }.entries) {
          final intent = resolver.resolve(entry.key);
          expect(
            intent?.destination,
            VoiceNavigationDestination.topics,
            reason: entry.key,
          );
          expect(intent?.topicNumber, entry.value, reason: entry.key);
          expect(intent?.openLesson, isFalse, reason: entry.key);
        }
      },
    );

    test('numbered topic recognition waits for a complete final utterance', () {
      for (final phrase in <String>[
        'Chủ đề số',
        'Bạn chọn chủ đề số mấy',
        'Chủ đề số hai rất hay',
        'Hôm nay cô kể chuyện về chủ đề số ba',
      ]) {
        expect(
          VoiceNavigationIntentResolver.directTopicNumber(phrase),
          isNull,
          reason: phrase,
        );
      }
      expect(resolver.resolve('Chủ đề số'), isNull);
      expect(resolver.resolve('Chủ đề số hai rất hay'), isNull);
      expect(
        resolver.resolve('Chủ đề số hai', allowShortDirectCommand: false),
        isNull,
      );
    });

    test(
      'continuous numbered topic navigation still requires a command cue',
      () {
        for (final command in <String>[
          'Mở chủ đề số hai',
          'Con muốn học chủ đề số hai',
        ]) {
          final intent = resolver.resolve(
            command,
            allowShortDirectCommand: false,
          );
          expect(intent?.destination, VoiceNavigationDestination.topics);
          expect(intent?.topicNumber, 2);
        }
        expect(
          resolver.resolve(
            'Hôm nay cô kể chuyện về chủ đề số hai',
            allowShortDirectCommand: false,
          ),
          isNull,
        );
      },
    );

    test('recognizes approved INT-022 HOMI wake phrases and ASR variants', () {
      for (final phrase in MasterNavigationContract.phrases['WAKE_WORD']!) {
        expect(resolver.containsWakeWord(phrase), isTrue, reason: phrase);
      }
      expect(resolver.containsWakeWord('Hey HOMI'), isTrue);
      expect(resolver.containsWakeWord('Hay HOMIE'), isTrue);
      expect(resolver.containsWakeWord('Hey HAMI'), isTrue);
      expect(resolver.containsWakeWord('Ê HOMPI'), isTrue);
      expect(resolver.containsWakeWord('Hôm-mi ơi'), isTrue);
      expect(resolver.containsWakeWord('HOMI nghe mình nói không?'), isTrue);
      expect(resolver.containsWakeWord('HOMI'), isFalse);
      expect(resolver.containsWakeWord('Pico'), isFalse);
      expect(resolver.containsWakeWord('Bạn ơi'), isFalse);
      expect(resolver.containsWakeWord('Mình thích HOMI'), isFalse);
      expect(resolver.containsWakeWord('Hãy đi coi bài tập'), isFalse);
    });

    test('recognizes vocabulary commands with and without accents', () {
      for (final command in <String>[
        'Con muốn học từ vựng',
        'Con muốn học từ mới',
        'Con muốn học từ',
        'Con muốn luyện từ',
        'mo kho tu vung cho con',
      ]) {
        expect(
          resolver.resolve(command)?.destination,
          VoiceNavigationDestination.vocabulary,
          reason: command,
        );
      }
    });

    test('recognizes all supported topic-learning synonyms', () {
      for (final command in <String>[
        'Học bài',
        'Học theo chủ đề',
        'Học khóa học',
        'Bắt đầu bài học',
      ]) {
        expect(
          resolver.resolve(command)?.destination,
          VoiceNavigationDestination.topics,
          reason: command,
        );
      }
    });

    test('recognizes the supported top-level destinations', () {
      expect(
        resolver.resolve('Con muốn học theo chủ đề')?.destination,
        VoiceNavigationDestination.topics,
      );
      expect(
        resolver.resolve('Cho con luyện giao tiếp')?.destination,
        VoiceNavigationDestination.conversation,
      );
      expect(
        resolver.resolve('Mở lịch sử gần đây')?.destination,
        VoiceNavigationDestination.history,
      );
      expect(
        resolver.resolve('Hãy mở cài đặt')?.destination,
        VoiceNavigationDestination.settings,
      );
    });

    test('recognizes a direct topic lesson command', () {
      final byName = resolver.resolve(
        'Con muốn học bài 2 trong chủ đề Gia đình và ngôi nhà',
      );
      expect(byName?.destination, VoiceNavigationDestination.topics);
      expect(byName?.openLesson, isTrue);
      expect(byName?.lessonNumber, 2);
      expect(byName?.topicNumber, isNull);

      final byNumber = resolver.resolve('Mở bài đầu tiên trong chủ đề số 3');
      expect(byNumber?.destination, VoiceNavigationDestination.topics);
      expect(byNumber?.openLesson, isTrue);
      expect(byNumber?.lessonNumber, 1);
      expect(byNumber?.topicNumber, 3);

      final contextual = resolver.resolve('Bài 2');
      expect(contextual?.openLesson, isTrue);
      expect(contextual?.lessonNumber, 2);
    });

    test('accepts a short destination name as a direct command', () {
      expect(
        resolver.resolve('Từ vựng')?.destination,
        VoiceNavigationDestination.vocabulary,
      );
      expect(
        resolver.resolve('主题')?.destination,
        VoiceNavigationDestination.topics,
      );
    });

    test('routes an approved workbook phrase in a longer utterance', () {
      expect(
        resolver
            .resolve('Bài học hôm nay có phần từ vựng rất khó')
            ?.destination,
        VoiceNavigationDestination.vocabulary,
      );
    });

    test(
      'does not redirect a normal sentence without an approved command phrase',
      () {
        expect(
          resolver.resolve('Bài học hôm nay có phần bài tập rất khó'),
          isNull,
        );
        expect(
          resolver.resolve('Cô giáo kể một câu chuyện về lịch sử Việt Nam'),
          isNull,
        );
        expect(resolver.resolve('Con muốn uống nước'), isNull);
      },
    );

    test('prefers the most specific phrase in an ambiguous command', () {
      expect(
        resolver.resolve('Con muốn học từ vựng theo chủ đề')?.destination,
        VoiceNavigationDestination.vocabulary,
      );
    });
  });
}
