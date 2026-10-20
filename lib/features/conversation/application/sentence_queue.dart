import 'dart:async';

/// Conservative final-transcript segmentation. Uncertain periods stay intact.
List<String> splitFinalSentences(String text) {
  final parts = <String>[];
  var start = 0;
  final boundary = RegExp(r'[.!?。！？]+[”’"»)]*(?:\s+|$)');
  final abbreviations = RegExp(
    r'(?:\b(?:mr|mrs|ms|dr|prof|sr|jr|etc|vs|ts|ths|pgs|tp|q|p)|\b[A-Za-z]|\b(?:[A-Za-z]\.)+[A-Za-z])\.$',
    caseSensitive: false,
  );
  for (final match in boundary.allMatches(text)) {
    final punctuation = match.group(0)!;
    if (punctuation.startsWith('.')) {
      final prefix = text.substring(0, match.start + 1);
      if (punctuation.startsWith('..') || abbreviations.hasMatch(prefix)) {
        continue;
      }
      // A period without a clearly capitalized next sentence is ambiguous.
      final next = text.substring(match.end);
      if (next.isNotEmpty &&
          (next[0].toUpperCase() == next[0].toLowerCase() ||
              next[0] != next[0].toUpperCase())) {
        continue;
      }
    }
    final part = text.substring(start, match.end).trim();
    if (part.isNotEmpty) parts.add(part);
    start = match.end;
  }
  final tail = text.substring(start).trim();
  if (tail.isNotEmpty) parts.add(tail);
  return parts.expand(_splitVietnameseQuestions).toList(growable: false);
}

final _polarQuestionStart = RegExp(
  r'^(?:bạn|anh|chị|em|cô|chú)\s+(?:có|đã)\s+',
  caseSensitive: false,
);
final _quantityQuestionStart = RegExp(
  r'^(?:có\s+)?bao nhiêu\s+\S',
  caseSensitive: false,
);
final _questionEnd = RegExp(
  r'(?:^|\s)(?:không|chưa|chứ)[?!.。！？]*$',
  caseSensitive: false,
);
final _questionJunction = RegExp(
  r'(?:^|\s)(?:không|chưa|chứ)(\s+)',
  caseSensitive: false,
);
final _ambiguousQuestionContext = RegExp(r"""["'“”‘’«»:()\[\]{}…]|\.{2,}""");
final _indirectQuestionCue = RegExp(
  r'(?:^|\s)(?:có biết|muốn biết|không biết|hỏi xem|cho biết|câu nói|câu hỏi)(?:\s|$)',
  caseSensitive: false,
);

bool _isExplicitVietnameseQuestion(String text) =>
    (_polarQuestionStart.hasMatch(text) && _questionEnd.hasMatch(text)) ||
    _quantityQuestionStart.hasMatch(text);

/// Native Vietnamese ASR often omits punctuation. Only accept a junction
/// between two explicit question forms, never capitals or pauses alone.
/// Preserve original spelling, punctuation and word order; do not synthesize
/// question marks or interpret quoted/reported text as independent questions.
List<String> _splitVietnameseQuestions(String text) {
  if (_ambiguousQuestionContext.hasMatch(text) ||
      _indirectQuestionCue.hasMatch(text)) {
    return [text];
  }
  final parts = <String>[];
  var end = text.length;
  // Validate from the end so a final quantity question does not hide the
  // terminal "không/chưa/chứ" of the preceding yes/no question.
  for (final match in _questionJunction.allMatches(text).toList().reversed) {
    final boundary = match.end - match.group(1)!.length;
    final previous = text.substring(0, boundary).trim();
    final next = text.substring(match.end, end).trim();
    if (!_isExplicitVietnameseQuestion(previous) ||
        !_isExplicitVietnameseQuestion(next)) {
      continue;
    }
    parts.add(next);
    end = boundary;
  }
  parts.add(text.substring(0, end).trim());
  return parts.reversed.toList(growable: false);
}

class SentenceQueueFailure implements Exception {
  const SentenceQueueFailure(this.index, this.cause);
  final int index;
  final Object cause;
}

class _Prepared<T> {
  _Prepared.value(this.value) : error = null;
  _Prepared.error(this.error) : value = null;
  final T? value;
  final Object? error;
}

/// One active sentence and at most one lookahead. Playback must complete only
/// on a real end event; prepare must never touch the player's current source.
class SentenceQueue<T> {
  SentenceQueue({required this.sessionId});
  final String sessionId;
  final _cancelled = Completer<void>();
  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get cancelled => _cancelled.future;
  void cancel() {
    if (!isCancelled) _cancelled.complete();
  }

  Future<void> run({
    required int count,
    required Future<T> Function(int index) prepare,
    required Future<void> Function(T value, int index) play,
    required void Function(int index, bool preparing) progress,
  }) async {
    Future<_Prepared<T>> safePrepare(int index) async {
      try {
        return _Prepared.value(await prepare(index));
      } catch (error) {
        // Capture immediately, including failures after cancellation.
        return _Prepared.error(error);
      }
    }

    Future<R?> cancellable<R>(Future<R> operation) =>
        Future.any<R?>([operation, _cancelled.future.then((_) => null)]);

    if (count == 0 || isCancelled) return;
    var pending = safePrepare(0);
    for (var index = 0; index < count; index++) {
      if (isCancelled) return;
      progress(index, true);
      final prepared = await cancellable(pending);
      if (isCancelled || prepared == null) return;
      if (prepared.error != null) {
        throw SentenceQueueFailure(index, prepared.error!);
      }
      progress(index, false);
      final playback = play(prepared.value as T, index);
      // The player is starting now; only the immediately following sentence
      // may be prepared while it owns the output.
      if (index + 1 < count) pending = safePrepare(index + 1);
      try {
        await cancellable(playback);
      } catch (error) {
        if (!isCancelled) throw SentenceQueueFailure(index, error);
      }
    }
  }
}
