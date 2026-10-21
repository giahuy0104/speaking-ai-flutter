import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_speaking_flutter_app/features/conversation/application/sentence_queue.dart';

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  test(
    'real vivo transcript separates explicit questions without punctuation',
    () {
      const first =
          'bạn có thể xây dựng kế hoạch tăng trưởng doanh thu và tối ưu '
          'hóa sản phẩm kinh doanh hàng thương mại điện tử được không';
      const second = 'Bạn có thể đăng doanh thu trong vòng 3 tháng được không';
      expect(splitFinalSentences('$first $second'), [first, second]);
    },
  );

  test('vivo build 76 transcript accepts final and intermediate chu', () {
    const first = 'bạn có khả năng đọc số liệu và có hóa quảng cáo được không';
    const second = 'Bạn có thể tăng doanh thu vào 3 tháng tới được chứ';
    expect(splitFinalSentences('$first $second'), [first, second]);
    expect(splitFinalSentences('$second $first'), [second, first]);
    expect(splitFinalSentences('$first $second bạn đã làm chưa'), [
      first,
      second,
      'bạn đã làm chưa',
    ]);
  });

  test('three lowercase ASR questions preserve every word and decimal', () {
    const sentences = [
      'bạn có thể vận hành sàn thương mại điện tử không',
      'bạn đã từng vận hành sàn thương mại điện tử hay chưa',
      'có bao nhiêu năm kinh nghiệm làm việc rồi',
    ];
    expect(splitFinalSentences(sentences.join(' ')), sentences);
    expect(splitFinalSentences('bạn có giá 3.14 không bạn đã bán chưa'), [
      'bạn có giá 3.14 không',
      'bạn đã bán chưa',
    ]);
  });

  test(
    'does not split a single question, reported text or uncertain clause',
    () {
      for (final text in [
        'Bạn có thể vận hành sàn thương mại điện tử được không',
        'Bạn có thể tăng doanh thu vào 3 tháng tới được chứ',
        'Bạn có thể làm chứ tôi chưa chắc',
        'Bạn có biết anh có làm được chứ bạn có muốn đi không',
        'Bạn có nói “được chứ bạn có làm không” không',
        'Bạn có biết không bạn có thể hỏi giáo viên',
        'Tôi không Bạn có thể giúp tôi được không',
        'Tôi hỏi bạn có đi không bạn có muốn đi không',
        'Bạn có biết anh có đi không em có đi không',
        'Bạn có biết không có ai ở nhà không',
        'Bạn có đi không Bao nhiêu',
        'Bạn có biết câu “được không Bạn có thể” nghĩa là gì không?',
        "Bạn có nói 'không bạn có về chưa' không",
        'Bạn có nói [không bạn có về chưa] không',
        'Bạn có biết câu: bạn có đi không bạn có muốn đi không',
        'Bạn có đi không... Bạn có muốn đi không',
        'Bạn có thể giúp tôi và bạn có thể giúp anh ấy không',
      ]) {
        expect(splitFinalSentences(text), [text], reason: text);
      }
    },
  );

  test(
    'final transcript segmentation preserves the three example sentences',
    () {
      const sentences = [
        'Bạn có thể vận hành sàn thương mại điện tử không?',
        'Bạn đã từng vận hành sàn thương mại điện tử hay chưa?',
        'Có bao nhiêu năm kinh nghiệm làm việc rồi?',
      ];
      expect(splitFinalSentences(sentences.join(' ')), sentences);
    },
  );

  test(
    'uncertain boundaries, decimal, abbreviations and ellipsis stay intact',
    () {
      for (final text in [
        'tôi muốn học tiếng anh hôm nay rồi đi làm',
        'Giá là 3.14 triệu.',
        'Dr. Smith ở TP. HCM.',
        'Tôi... chưa biết',
        'Tôi… chưa biết',
        'Gặp J. Smith và U.S. Army.',
      ]) {
        expect(splitFinalSentences(text), [text], reason: text);
      }
      expect(splitFinalSentences('Giá 3.14. Bạn mua không?'), [
        'Giá 3.14.',
        'Bạn mua không?',
      ]);
    },
  );

  test(
    'one lookahead overlaps playback, never advances without completion',
    () async {
      final queue = SentenceQueue<int>(sessionId: 'test');
      final prepared = <int>[];
      final played = <int>[];
      final ends = List.generate(3, (_) => Completer<void>());
      final run = queue.run(
        count: 3,
        prepare: (index) async {
          prepared.add(index);
          return index;
        },
        play: (value, index) {
          played.add(value);
          return ends[index].future;
        },
        progress: (_, _) {},
      );
      await flush();
      expect(prepared, [0, 1]);
      expect(played, [0]);
      ends[0].complete();
      await flush();
      expect(prepared, [0, 1, 2]);
      expect(played, [0, 1]);
      ends[1].complete();
      await flush();
      expect(played, [0, 1, 2]);
      ends[2].complete();
      await run;
    },
  );

  test('slow next sentence shows preparation and waits', () async {
    final queue = SentenceQueue<int>(sessionId: 'slow');
    final next = Completer<int>();
    final end = Completer<void>();
    final progress = <(int, bool)>[];
    final played = <int>[];
    final run = queue.run(
      count: 2,
      prepare: (index) => index == 0 ? Future.value(0) : next.future,
      play: (value, index) async {
        played.add(value);
        if (index == 0) await end.future;
      },
      progress: (index, preparing) => progress.add((index, preparing)),
    );
    await flush();
    end.complete();
    await flush();
    expect(progress.last, (1, true));
    expect(played, [0]);
    next.complete(1);
    await run;
    expect(played, [0, 1]);
  });

  test('lookahead error surfaces only after current audio completes', () async {
    final queue = SentenceQueue<int>(sessionId: 'error');
    final end = Completer<void>();
    var failed = false;
    final run = queue
        .run(
          count: 3,
          prepare: (index) async {
            if (index == 1) throw StateError('translation');
            return index;
          },
          play: (_, _) => end.future,
          progress: (_, _) {},
        )
        .catchError((Object error) {
          expect(error, isA<SentenceQueueFailure>());
          expect((error as SentenceQueueFailure).index, 1);
          failed = true;
        });
    await flush();
    expect(failed, isFalse);
    end.complete();
    await run;
    expect(failed, isTrue);
  });

  test(
    'cancel consumes late preparation errors and does not publish',
    () async {
      final queue = SentenceQueue<int>(sessionId: 'old');
      final late = Completer<int>();
      final progress = <int>[];
      final run = queue.run(
        count: 2,
        prepare: (_) => late.future,
        play: (_, _) async => fail('stale audio'),
        progress: (index, _) => progress.add(index),
      );
      queue.cancel();
      await run;
      late.completeError(StateError('late network error'));
      await flush();
      expect(progress, [0]);
    },
  );

  test(
    'cancel while playing consumes pending playback and prefetch errors',
    () async {
      final queue = SentenceQueue<int>(sessionId: 'stop');
      final end = Completer<void>();
      final next = Completer<int>();
      final run = queue.run(
        count: 2,
        prepare: (index) => index == 0 ? Future.value(0) : next.future,
        play: (_, _) => end.future,
        progress: (_, _) {},
      );
      await flush();
      queue.cancel();
      await run;
      end.completeError(StateError('stopped'));
      next.completeError(StateError('aborted'));
      await flush();
    },
  );
}
