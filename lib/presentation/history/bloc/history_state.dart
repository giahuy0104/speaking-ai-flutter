part of 'history_bloc.dart';

enum HistoryFilter { all, approved, rejected, pending }

enum HistoryNoticeKind { error, reviewed, deleted, cleared }

class HistoryNotice {
  const HistoryNotice(this.kind, {this.message = '', this.approved = false});
  final HistoryNoticeKind kind;
  final String message;
  final bool approved;
}

class HistoryState {
  HistoryState({
    List<ConversationHistoryItem> items = const [],
    Set<String> busyItems = const {},
    this.query = '',
    this.filter = HistoryFilter.all,
    this.loading = true,
    this.error,
    this.notice,
    this.noticeRevision = 0,
  }) : items = List.unmodifiable(items),
       busyItems = Set.unmodifiable(busyItems);

  final List<ConversationHistoryItem> items;
  final Set<String> busyItems;
  final String query;
  final HistoryFilter filter;
  final bool loading;
  final String? error;
  final HistoryNotice? notice;
  final int noticeRevision;

  List<ConversationHistoryItem> get visibleItems {
    final search = query.trim().toLowerCase();
    return items
        .where((item) {
          final matches = switch (filter) {
            HistoryFilter.all => true,
            HistoryFilter.approved =>
              item.reviewStatus == HistoryReviewStatus.approved,
            HistoryFilter.rejected =>
              item.reviewStatus == HistoryReviewStatus.rejected,
            HistoryFilter.pending =>
              item.reviewStatus == HistoryReviewStatus.pending,
          };
          return matches &&
              (search.isEmpty ||
                  item.vietnameseText.toLowerCase().contains(search) ||
                  item.displayedTranslation.toLowerCase().contains(search));
        })
        .toList(growable: false);
  }

  List<ConversationHistoryItem> get recentUserAudioItems =>
      items.where((item) => item.hasUserAudio).take(3).toList(growable: false);

  HistoryState copyWith({
    List<ConversationHistoryItem>? items,
    Set<String>? busyItems,
    String? query,
    HistoryFilter? filter,
    bool? loading,
    String? error,
    bool clearError = false,
    HistoryNotice? notice,
  }) => HistoryState(
    items: items ?? this.items,
    busyItems: busyItems ?? this.busyItems,
    query: query ?? this.query,
    filter: filter ?? this.filter,
    loading: loading ?? this.loading,
    error: clearError ? null : error ?? this.error,
    notice: notice ?? this.notice,
    noticeRevision: notice == null ? noticeRevision : noticeRevision + 1,
  );
}
