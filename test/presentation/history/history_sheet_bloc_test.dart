import 'dart:async';
import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/app/di/history_dependencies.dart';
import 'package:ai_speaking_flutter_app/l10n/display_language.dart';
import 'package:ai_speaking_flutter_app/presentation/history/bloc/history_bloc.dart';
import 'package:ai_speaking_flutter_app/presentation/history/screen/history_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../support/fake_history_port.dart';

Future<HistoryBloc> pumpHistory(
  WidgetTester tester,
  FakeHistoryPort port,
) async {
  tester.view.physicalSize = const Size(460, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  late HistoryBloc bloc;
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: HistoryScreen(
          createBloc: () =>
              bloc = HistoryDependencies(history: port).createBloc(),
          readLanguage: () => port.displayLanguage,
        ),
      ),
    ),
  );
  await tester.pump();
  return bloc;
}

void main() {
  testWidgets('load error retries from UI, search and filter use Bloc', (
    tester,
  ) async {
    final port = FakeHistoryPort()..loadError = Exception('Mất mạng');
    final bloc = await pumpHistory(tester, port);
    await tester.pumpAndSettle();
    expect(find.text('Mất mạng'), findsOneWidget);
    port.loadError = null;
    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();
    expect(find.text('2 lượt đã lưu'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'sentence b');
    await tester.pump();
    expect(bloc.state.query, 'sentence b');
    expect(find.text('Câu b'), findsOneWidget);
    expect(find.text('Câu a'), findsNothing);
    await tester.tap(find.byTooltip('Xóa nội dung tìm kiếm'));
    await tester.pump();
    expect(bloc.state.query, isEmpty);
    expect(find.text('Câu a'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Đúng ý'));
    await tester.pumpAndSettle();
    expect(bloc.state.filter, HistoryFilter.approved);
    expect(find.text('Không tìm thấy lượt nói phù hợp.'), findsOneWidget);
  });

  testWidgets(
    'review UI is optimistic, disabled while busy and rolls back with one snackbar',
    (tester) async {
      final port = FakeHistoryPort()..items = [historyItem('a')];
      final bloc = await pumpHistory(tester, port);
      await tester.pumpAndSettle();
      port.reviewGate = Completer();
      await tester.tap(find.byTooltip('Đánh dấu Đúng ý'));
      await tester.pump();
      expect(bloc.state.items.single.qualityApproved, isTrue);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is IconButton && widget.tooltip == 'Đánh dấu Đúng ý',
              ),
            )
            .onPressed,
        isNull,
      );
      port.reviewGate!.completeError(Exception('Không lưu được'));
      await tester.pumpAndSettle();
      expect(bloc.state.items.single.qualityApproved, isNull);
      expect(find.text('Không lưu được'), findsOneWidget);
      ScaffoldMessenger.of(
        tester.element(find.byType(TextField)),
      ).hideCurrentSnackBar();
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'a');
      await tester.pumpAndSettle();
      expect(find.text('Không lưu được'), findsNothing);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is IconButton && widget.tooltip == 'Đánh dấu Đúng ý',
              ),
            )
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets(
    'delete dialog cancel does nothing; confirmed deletion waits for server',
    (tester) async {
      final port = FakeHistoryPort()..items = [historyItem('a')];
      final bloc = await pumpHistory(tester, port);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Xóa lượt nói'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Giữ lại'));
      await tester.pumpAndSettle();
      expect(port.calls, ['load']);
      port.deleteGate = Completer();
      await tester.tap(find.byTooltip('Xóa lượt nói'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Xóa'));
      await tester.pumpAndSettle();
      expect(bloc.state.items, hasLength(1));
      expect(bloc.state.busyItems, {'a'});
      port.deleteGate!.complete();
      await tester.pumpAndSettle();
      expect(bloc.state.items, isEmpty);
      expect(
        find.text('Máy chủ đã xác nhận yêu cầu xóa lượt nói.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'clear dialog cancellation and server rejection preserve data, retry succeeds',
    (tester) async {
      final port = FakeHistoryPort()..items = [historyItem('a')];
      final bloc = await pumpHistory(tester, port);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Xóa toàn bộ lịch sử'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
      expect(port.calls, ['load']);
      port.actionError = Exception('Máy chủ chưa xác nhận');
      await tester.tap(find.byTooltip('Xóa toàn bộ lịch sử'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xóa tất cả'));
      await tester.pumpAndSettle();
      expect(bloc.state.items, hasLength(1));
      expect(find.text('Máy chủ chưa xác nhận'), findsOneWidget);
      port.actionError = null;
      await tester.tap(find.byTooltip('Xóa toàn bộ lịch sử'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xóa tất cả'));
      await tester.pumpAndSettle();
      expect(bloc.state.items, isEmpty);
      expect(
        find.text('Máy chủ đã xác nhận yêu cầu xóa toàn bộ dữ liệu lịch sử.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('both playback buttons delegate to existing port', (
    tester,
  ) async {
    final port = FakeHistoryPort()..items = [historyItem('a', userAudio: true)];
    await pumpHistory(tester, port);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Phát lại câu tiếng Anh'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('user-audio-a')));
    await tester.pumpAndSettle();
    expect(port.calls, ['load', 'play:a', 'user:a']);
  });

  testWidgets('Chinese success notice remains localized', (tester) async {
    final port = FakeHistoryPort()
      ..items = [historyItem('a')]
      ..displayLanguage = DisplayLanguage.simplifiedChinese;
    await pumpHistory(tester, port);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('标记为符合原意'));
    await tester.pumpAndSettle();
    expect(find.text('已标记为符合原意。'), findsOneWidget);
    expect(find.text('Đã đánh dấu Đúng ý.'), findsNothing);
  });

  testWidgets('sheet owns and closes Bloc while pending IO completes safely', (
    tester,
  ) async {
    final port = FakeHistoryPort()..loadGate = Completer();
    final bloc = await pumpHistory(tester, port);
    expect(bloc.state.loading, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(bloc.isClosed, isTrue);
    port.loadGate!.complete(port.items);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(port.calls, ['load']);
  });
}
