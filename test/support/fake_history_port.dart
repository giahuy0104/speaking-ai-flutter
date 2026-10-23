import 'dart:async';
import 'package:ai_speaking_flutter_app/features/conversation/application/conversation_settings_port.dart';
import 'package:ai_speaking_flutter_app/features/conversation/domain/conversation_models.dart';
import 'package:ai_speaking_flutter_app/l10n/display_language.dart';

ConversationHistoryItem historyItem(
  String id, {
  int minute = 0,
  bool? approved,
  bool userAudio = false,
}) => ConversationHistoryItem(
  conversationId: id,
  vietnameseText: 'Câu $id',
  englishText: 'Sentence $id',
  createdAt: DateTime(2026, 10, 23, 9, minute),
  qualityApproved: approved,
  audioUri: Uri.parse('https://example.test/$id.mp3'),
  hasUserAudio: userAudio,
);

const historyLearning = ConversationLearningOutcome(
  status: 'promoted',
  promoted: true,
  useCount: 3,
  threshold: 3,
  message: '',
);

class FakeHistoryPort implements ConversationHistoryPort {
  @override
  DisplayLanguage displayLanguage = DisplayLanguage.vietnamese;
  List<ConversationHistoryItem> items = [
    historyItem('a'),
    historyItem('b', minute: 1),
  ];
  final calls = <String>[];
  Completer<List<ConversationHistoryItem>>? loadGate;
  Completer<ConversationLearningOutcome>? reviewGate;
  Completer<void>? deleteGate;
  Completer<void>? clearGate;
  Completer<void>? playGate;
  Object? loadError;
  Object? actionError;

  @override
  Future<List<ConversationHistoryItem>> loadHistory() async {
    calls.add('load');
    if (loadError != null) throw loadError!;
    return loadGate == null ? List.of(items) : await loadGate!.future;
  }

  @override
  Future<void> playHistoryItem(ConversationHistoryItem item) async {
    calls.add('play:${item.conversationId}');
    if (actionError != null) throw actionError!;
    await playGate?.future;
  }

  @override
  Future<void> playHistoryUserAudio(ConversationHistoryItem item) async {
    calls.add('user:${item.conversationId}');
    if (actionError != null) throw actionError!;
    await playGate?.future;
  }

  @override
  Future<ConversationLearningOutcome> reviewHistoryItem(
    ConversationHistoryItem item,
    bool approved,
  ) async {
    calls.add('review:${item.conversationId}:$approved');
    if (actionError != null) throw actionError!;
    final learning = reviewGate == null
        ? historyLearning
        : await reviewGate!.future;
    items = [
      for (final current in items)
        if (current.conversationId == item.conversationId)
          current.copyWithReview(approved, learning: learning)
        else
          current,
    ];
    return learning;
  }

  @override
  Future<void> deleteHistoryItem(ConversationHistoryItem item) async {
    calls.add('delete:${item.conversationId}');
    if (actionError != null) throw actionError!;
    await deleteGate?.future;
    items.removeWhere(
      (current) => current.conversationId == item.conversationId,
    );
  }

  @override
  Future<void> clearHistory() async {
    calls.add('clear');
    if (actionError != null) throw actionError!;
    await clearGate?.future;
    items = [];
  }
}
