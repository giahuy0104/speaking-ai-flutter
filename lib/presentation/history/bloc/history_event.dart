part of 'history_bloc.dart';

sealed class HistoryEvent {
  final _completed = Completer<void>();
}

final class HistoryLoadRequested extends HistoryEvent {}

final class HistoryQueryChanged extends HistoryEvent {
  HistoryQueryChanged(this.query);
  final String query;
}

final class HistoryFilterChanged extends HistoryEvent {
  HistoryFilterChanged(this.filter);
  final HistoryFilter filter;
}

final class HistoryPlayRequested extends HistoryEvent {
  HistoryPlayRequested(this.item, {this.userAudio = false});
  final ConversationHistoryItem item;
  final bool userAudio;
}

final class HistoryReviewRequested extends HistoryEvent {
  HistoryReviewRequested(this.item, this.approved);
  final ConversationHistoryItem item;
  final bool approved;
}

/// Dispatched only after confirmation in the view.
final class HistoryDeleteRequested extends HistoryEvent {
  HistoryDeleteRequested(this.item);
  final ConversationHistoryItem item;
}

/// Dispatched only after confirmation in the view.
final class HistoryClearRequested extends HistoryEvent {}
