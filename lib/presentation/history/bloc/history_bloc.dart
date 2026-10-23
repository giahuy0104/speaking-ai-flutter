import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../features/conversation/application/conversation_settings_port.dart';
import '../../../features/conversation/domain/conversation_models.dart';

part 'history_event.dart';
part 'history_state.dart';

class HistoryBloc extends Bloc<HistoryEvent, HistoryState> {
  HistoryBloc({required ConversationHistoryPort history})
    : _history = history,
      super(HistoryState()) {
    on<HistoryEvent>(_handle);
  }
  final ConversationHistoryPort _history;
  final _closedSignal = Completer<void>();
  Future<void> _dataTail = Future.value();
  bool _closing = false;
  bool _loadPending = false;
  bool _clearPending = false;

  Future<void> dispatch(HistoryEvent event) {
    if (_closing || isClosed) return Future.value();
    add(event);
    return event._completed.future;
  }

  // Serialize fetch/review/delete/clear so a late fetch cannot restore a deleted
  // item and a review cannot apply to a different row after list reordering.
  // Search/filter and playback remain responsive while data IO is pending.
  Future<void> _enqueue(Future<void> Function() action) {
    final operation = _dataTail.then((_) async {
      if (!_closing) await action();
    });
    _dataTail = operation.catchError((Object _) {});
    return operation;
  }

  Future<T> _wait<T>(Future<T> operation) => Future.any<T>([
    operation,
    _closedSignal.future.then<T>((_) => throw const _HistoryClosed()),
  ]);

  Future<void> _handle(HistoryEvent event, Emitter<HistoryState> emit) async {
    try {
      if (_closing) return;
      switch (event) {
        case HistoryQueryChanged():
          emit(state.copyWith(query: event.query));
        case HistoryFilterChanged():
          emit(state.copyWith(filter: event.filter));
        case HistoryLoadRequested():
          if (_loadPending || _clearPending) return;
          _loadPending = true;
          try {
            await _enqueue(() => _load(emit));
          } finally {
            _loadPending = false;
          }
        case HistoryPlayRequested():
          if (!_reserve(event.item, emit)) return;
          try {
            await _wait(
              event.userAudio
                  ? _history.playHistoryUserAudio(event.item)
                  : _history.playHistoryItem(event.item),
            );
          } finally {
            _release(event.item, emit);
          }
        case HistoryReviewRequested():
          if (!_reserve(event.item, emit)) return;
          try {
            await _enqueue(() => _review(event.item, event.approved, emit));
          } finally {
            _release(event.item, emit);
          }
        case HistoryDeleteRequested():
          if (!_reserve(event.item, emit)) return;
          try {
            await _enqueue(() => _delete(event.item, emit));
          } finally {
            _release(event.item, emit);
          }
        case HistoryClearRequested():
          if (_clearPending) return;
          _clearPending = true;
          try {
            await _enqueue(() => _clear(emit));
          } finally {
            _clearPending = false;
          }
      }
    } on _HistoryClosed {
      // Closing the sheet releases handlers without owning/cancelling the
      // shared controller, audio session, or an already accepted server write.
    } catch (error) {
      if (!_closing) {
        emit(
          state.copyWith(
            notice: HistoryNotice(
              HistoryNoticeKind.error,
              message: _friendlyError(error),
            ),
          ),
        );
      }
    } finally {
      if (!event._completed.isCompleted) event._completed.complete();
    }
  }

  bool _reserve(ConversationHistoryItem item, Emitter<HistoryState> emit) {
    if (_clearPending ||
        state.busyItems.contains(item.conversationId) ||
        !state.items.any(
          (value) => value.conversationId == item.conversationId,
        )) {
      return false;
    }
    emit(state.copyWith(busyItems: {...state.busyItems, item.conversationId}));
    return true;
  }

  void _release(ConversationHistoryItem item, Emitter<HistoryState> emit) {
    if (!_closing) {
      emit(
        state.copyWith(
          busyItems: {...state.busyItems}..remove(item.conversationId),
        ),
      );
    }
  }

  Future<void> _load(Emitter<HistoryState> emit) async {
    emit(state.copyWith(loading: true, clearError: true));
    try {
      final items = List<ConversationHistoryItem>.of(
        await _wait(_history.loadHistory()),
      );
      if (_closing) return;
      items.sort((left, right) => right.createdAt.compareTo(left.createdAt));
      emit(state.copyWith(items: items, loading: false, clearError: true));
    } on _HistoryClosed {
      rethrow;
    } catch (error) {
      if (!_closing) {
        emit(state.copyWith(loading: false, error: _friendlyError(error)));
      }
    }
  }

  void _replace(ConversationHistoryItem item, Emitter<HistoryState> emit) {
    emit(
      state.copyWith(
        items: [
          for (final current in state.items)
            if (current.conversationId == item.conversationId)
              item
            else
              current,
        ],
      ),
    );
  }

  Future<void> _review(
    ConversationHistoryItem item,
    bool approved,
    Emitter<HistoryState> emit,
  ) async {
    final index = state.items.indexWhere(
      (value) => value.conversationId == item.conversationId,
    );
    if (index < 0) return;
    final previous = state.items[index];
    _replace(previous.copyWithReview(approved), emit);
    try {
      final learning = await _wait(_history.reviewHistoryItem(item, approved));
      if (_closing) return;
      _replace(previous.copyWithReview(approved, learning: learning), emit);
      emit(
        state.copyWith(
          notice: HistoryNotice(
            HistoryNoticeKind.reviewed,
            message: learning.message,
            approved: approved,
          ),
        ),
      );
    } catch (_) {
      if (!_closing) _replace(previous, emit);
      rethrow;
    }
  }

  Future<void> _delete(
    ConversationHistoryItem item,
    Emitter<HistoryState> emit,
  ) async {
    if (!state.items.any(
      (value) => value.conversationId == item.conversationId,
    )) {
      return;
    }
    await _wait(_history.deleteHistoryItem(item));
    if (_closing) return;
    emit(
      state.copyWith(
        items: state.items
            .where((value) => value.conversationId != item.conversationId)
            .toList(),
        notice: const HistoryNotice(HistoryNoticeKind.deleted),
      ),
    );
  }

  Future<void> _clear(Emitter<HistoryState> emit) async {
    emit(state.copyWith(loading: true));
    try {
      await _wait(_history.clearHistory());
      if (_closing) return;
      emit(
        state.copyWith(
          items: [],
          loading: false,
          notice: const HistoryNotice(HistoryNoticeKind.cleared),
        ),
      );
    } finally {
      if (!_closing && state.loading) emit(state.copyWith(loading: false));
    }
  }

  String _friendlyError(Object error) => error
      .toString()
      .replaceFirst('Exception: ', '')
      .replaceFirst('Bad state: ', '');

  @override
  Future<void> close() {
    _closing = true;
    if (!_closedSignal.isCompleted) _closedSignal.complete();
    return super.close();
  }
}

class _HistoryClosed implements Exception {
  const _HistoryClosed();
}
