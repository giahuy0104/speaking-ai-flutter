import 'dart:async';
import 'package:ai_speaking_flutter_app/app/di/history_dependencies.dart';
import 'package:ai_speaking_flutter_app/presentation/history/bloc/history_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../support/fake_history_port.dart';

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeHistoryPort port;
  late HistoryBloc bloc;
  setUp(() {
    port = FakeHistoryPort();
    bloc = HistoryDependencies(history: port).createBloc();
  });
  tearDown(() async {
    await bloc.close();
  });

  test(
    'loads newest first, searches translation and combines filters; recent audio ignores filter',
    () async {
      port.items = [
        historyItem('a', approved: true, userAudio: true),
        historyItem('b', minute: 4, approved: false, userAudio: true),
        historyItem('c', minute: 2, userAudio: true),
        historyItem('d', minute: 3, userAudio: true),
      ];
      await bloc.dispatch(HistoryLoadRequested());
      expect(bloc.state.items.map((i) => i.conversationId), [
        'b',
        'd',
        'c',
        'a',
      ]);
      expect(bloc.state.recentUserAudioItems.map((i) => i.conversationId), [
        'b',
        'd',
        'c',
      ]);
      await bloc.dispatch(HistoryQueryChanged('  SENTENCE B  '));
      expect(bloc.state.visibleItems.single.conversationId, 'b');
      await bloc.dispatch(HistoryFilterChanged(HistoryFilter.approved));
      expect(bloc.state.visibleItems, isEmpty);
      await bloc.dispatch(HistoryQueryChanged('câu'));
      expect(bloc.state.visibleItems.single.conversationId, 'a');
      await bloc.dispatch(HistoryFilterChanged(HistoryFilter.pending));
      expect(bloc.state.visibleItems.map((i) => i.conversationId), ['d', 'c']);
      expect(bloc.state.recentUserAudioItems, hasLength(3));
      expect(() => bloc.state.items.clear(), throwsUnsupportedError);
      expect(() => bloc.state.busyItems.add('x'), throwsUnsupportedError);
    },
  );

  test(
    'load failure is inline and retry clears it; duplicate refresh coalesces',
    () async {
      port.loadError = StateError('offline');
      await bloc.dispatch(HistoryLoadRequested());
      expect(bloc.state.error, 'offline');
      expect(bloc.state.notice, isNull);
      expect(bloc.state.loading, isFalse);
      port.loadError = null;
      port.loadGate = Completer();
      final pending = bloc.dispatch(HistoryLoadRequested());
      await flush();
      await bloc.dispatch(HistoryLoadRequested());
      expect(port.calls, ['load', 'load']);
      expect(bloc.state.loading, isTrue);
      port.loadGate!.complete(port.items);
      await pending;
      expect(bloc.state.error, isNull);
      expect(bloc.state.items, hasLength(2));
    },
  );

  for (final approved in [true, false]) {
    test(
      'review $approved is optimistic and blocks repeated actions on same item',
      () async {
        await bloc.dispatch(HistoryLoadRequested());
        final item = bloc.state.items.first;
        port.reviewGate = Completer();
        final pending = bloc.dispatch(HistoryReviewRequested(item, approved));
        await flush();
        expect(bloc.state.items.first.qualityApproved, approved);
        expect(bloc.state.busyItems, contains(item.conversationId));
        await bloc.dispatch(HistoryReviewRequested(item, !approved));
        await bloc.dispatch(HistoryPlayRequested(item));
        await bloc.dispatch(HistoryDeleteRequested(item));
        expect(port.calls, ['load', 'review:b:$approved']);
        port.reviewGate!.complete(historyLearning);
        await pending;
        expect(bloc.state.items.first.learningStatus, 'promoted');
        expect(bloc.state.notice!.kind, HistoryNoticeKind.reviewed);
        expect(bloc.state.notice!.approved, approved);
        expect(bloc.state.busyItems, isEmpty);
      },
    );
  }

  test(
    'failed review rolls back and repeated identical errors get fresh notices',
    () async {
      await bloc.dispatch(HistoryLoadRequested());
      final item = bloc.state.items.first;
      port.reviewGate = Completer();
      final pending = bloc.dispatch(HistoryReviewRequested(item, true));
      await flush();
      expect(bloc.state.items.first.qualityApproved, isTrue);
      port.reviewGate!.completeError(Exception('network'));
      await pending;
      expect(bloc.state.items.first, same(item));
      expect(bloc.state.notice!.message, 'network');
      expect(bloc.state.busyItems, isEmpty);
      final revision = bloc.state.noticeRevision;
      port.actionError = Exception('network');
      await bloc.dispatch(HistoryPlayRequested(item));
      expect(bloc.state.noticeRevision, revision + 1);
    },
  );

  test(
    'delete waits for server confirmation; failure keeps item and allows retry',
    () async {
      await bloc.dispatch(HistoryLoadRequested());
      final item = bloc.state.items.first;
      port.actionError = StateError('cannot delete');
      await bloc.dispatch(HistoryDeleteRequested(item));
      expect(bloc.state.items, contains(item));
      expect(bloc.state.busyItems, isEmpty);
      port.actionError = null;
      port.deleteGate = Completer();
      final pending = bloc.dispatch(HistoryDeleteRequested(item));
      await flush();
      expect(bloc.state.items, contains(item));
      port.deleteGate!.complete();
      await pending;
      expect(bloc.state.items, isNot(contains(item)));
      expect(bloc.state.notice!.kind, HistoryNoticeKind.deleted);
      await bloc.dispatch(HistoryDeleteRequested(item));
      expect(port.calls.where((c) => c == 'delete:b'), hasLength(2));
    },
  );

  test(
    'clear waits for confirmation from server; failure retains list, success clears',
    () async {
      await bloc.dispatch(HistoryLoadRequested());
      port.actionError = Exception('clear failed');
      await bloc.dispatch(HistoryClearRequested());
      expect(bloc.state.items, hasLength(2));
      expect(bloc.state.loading, isFalse);
      expect(bloc.state.notice!.message, 'clear failed');
      port.actionError = null;
      port.clearGate = Completer();
      final pending = bloc.dispatch(HistoryClearRequested());
      await flush();
      expect(bloc.state.loading, isTrue);
      expect(bloc.state.items, hasLength(2));
      await bloc.dispatch(HistoryClearRequested());
      await bloc.dispatch(HistoryPlayRequested(bloc.state.items.first));
      await bloc.dispatch(HistoryLoadRequested());
      expect(port.calls, ['load', 'clear', 'clear']);
      port.clearGate!.complete();
      await pending;
      expect(bloc.state.items, isEmpty);
      expect(bloc.state.loading, isFalse);
      expect(bloc.state.notice!.kind, HistoryNoticeKind.cleared);
    },
  );

  test(
    'refresh and clear queued after review cannot restore removed rows',
    () async {
      await bloc.dispatch(HistoryLoadRequested());
      port.reviewGate = Completer();
      final review = bloc.dispatch(
        HistoryReviewRequested(bloc.state.items.first, true),
      );
      await flush();
      final refresh = bloc.dispatch(HistoryLoadRequested());
      final clear = bloc.dispatch(HistoryClearRequested());
      await flush();
      await bloc.dispatch(HistoryQueryChanged('sentence'));
      expect(bloc.state.query, 'sentence');
      expect(port.calls, ['load', 'review:b:true']);
      port.reviewGate!.complete(historyLearning);
      await Future.wait([review, refresh, clear]);
      expect(port.calls, ['load', 'review:b:true', 'load', 'clear']);
      expect(bloc.state.items, isEmpty);
    },
  );

  test('late refresh reordered list applies a queued review by ID', () async {
    await bloc.dispatch(HistoryLoadRequested());
    final item = bloc.state.items.first;
    port.loadGate = Completer();
    final load = bloc.dispatch(HistoryLoadRequested());
    await flush();
    final review = bloc.dispatch(HistoryReviewRequested(item, true));
    await flush();
    port.loadGate!.complete([historyItem('b'), historyItem('a', minute: 5)]);
    await Future.wait([load, review]);
    expect(bloc.state.items.first.conversationId, 'a');
    expect(bloc.state.items.first.qualityApproved, isNull);
    expect(bloc.state.items.last.conversationId, 'b');
    expect(bloc.state.items.last.qualityApproved, isTrue);
  });

  test(
    'two playback paths use same busy guard and recover after errors',
    () async {
      await bloc.dispatch(HistoryLoadRequested());
      final item = bloc.state.items.first;
      port.playGate = Completer();
      final play = bloc.dispatch(HistoryPlayRequested(item));
      await flush();
      await bloc.dispatch(HistoryPlayRequested(item, userAudio: true));
      await bloc.dispatch(HistoryQueryChanged('b'));
      expect(bloc.state.query, 'b');
      expect(port.calls, ['load', 'play:b']);
      port.playGate!.complete();
      await play;
      await bloc.dispatch(HistoryPlayRequested(item, userAudio: true));
      expect(port.calls.last, 'user:b');
      port.actionError = Exception('play failed');
      await bloc.dispatch(HistoryPlayRequested(item));
      expect(bloc.state.busyItems, isEmpty);
      expect(bloc.state.notice!.message, 'play failed');
    },
  );

  test(
    'closing releases pending load without late state or running queued commands',
    () async {
      port.loadGate = Completer();
      final pending = bloc.dispatch(HistoryLoadRequested());
      await flush();
      final clear = bloc.dispatch(HistoryClearRequested());
      await flush();
      await bloc.close().timeout(const Duration(seconds: 1));
      await Future.wait([pending, clear]);
      final state = bloc.state;
      port.loadGate!.complete(port.items);
      await flush();
      await bloc.dispatch(HistoryLoadRequested());
      expect(bloc.state, same(state));
      expect(port.calls, ['load']);
    },
  );

  for (final operation in ['review', 'delete', 'clear', 'play']) {
    test(
      'close during $operation drops UI updates but allows accepted IO to finish',
      () async {
        await bloc.dispatch(HistoryLoadRequested());
        final item = bloc.state.items.first;
        final gate = Completer<void>();
        port.deleteGate = port.clearGate = port.playGate = gate;
        port.reviewGate = Completer();
        final event = switch (operation) {
          'review' => HistoryReviewRequested(item, true),
          'delete' => HistoryDeleteRequested(item),
          'clear' => HistoryClearRequested(),
          _ => HistoryPlayRequested(item),
        };
        final pending = bloc.dispatch(event);
        await flush();
        await bloc.close().timeout(const Duration(seconds: 1));
        await pending;
        final state = bloc.state;
        port.reviewGate!.complete(historyLearning);
        gate.complete();
        await flush();
        expect(bloc.state, same(state));
        expect(bloc.state.notice, isNull);
        if (operation == 'delete') expect(port.items, hasLength(1));
        if (operation == 'clear') expect(port.items, isEmpty);
      },
    );
  }

  test(
    'DI creates isolated sheet scopes and never disposes the shared port',
    () async {
      await bloc.dispatch(HistoryLoadRequested());
      await bloc.dispatch(HistoryQueryChanged('a'));
      final other = HistoryDependencies(history: port).createBloc();
      await other.dispatch(HistoryLoadRequested());
      expect(other.state.query, isEmpty);
      await bloc.close();
      await other.dispatch(HistoryDeleteRequested(other.state.items.first));
      expect(other.state.items, hasLength(1));
      await other.close();
    },
  );
}
