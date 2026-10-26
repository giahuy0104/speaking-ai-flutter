import 'dart:async';

import 'package:ai_speaking_flutter_app/app/device_connection_action_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _dialog = Key('device-connection-action-dialog');
const _cancel = Key('device-connection-action-cancel');
const _retry = Key('device-connection-action-retry');
const _action = Key('protected-action');

void main() {
  testWidgets('background connection changes never open a dialog', (
    tester,
  ) async {
    final harness = await _pumpHarness(tester);

    for (final value in DeviceConnectionActionState.values) {
      harness.state.value = value;
      await tester.pump();
      expect(find.byKey(_dialog), findsNothing);
    }
    expect(harness.results, isEmpty);
    expect(harness.retryCalls, 0);
    expect(harness.cancelCalls, 0);
  });

  testWidgets('a ready device permits the action without a dialog', (
    tester,
  ) async {
    final harness = await _pumpHarness(
      tester,
      initialState: DeviceConnectionActionState.ready,
    );

    await tester.tap(find.byKey(_action));
    await tester.pump();

    expect(harness.results, <bool>[true]);
    expect(find.byKey(_dialog), findsNothing);
    expect(harness.retryCalls, 0);
  });

  testWidgets('a failed round asks to reconnect only after an action', (
    tester,
  ) async {
    final harness = await _pumpHarness(tester);
    await _openGate(tester);

    expect(find.text('Cần kết nối thiết bị'), findsOneWidget);
    expect(find.byKey(_cancel).hitTestable(), findsOneWidget);
    expect(find.byKey(_retry).hitTestable(), findsOneWidget);
    expect(harness.results, isEmpty);
    expect(harness.retryCalls, 0);
    expect(harness.cancelCalls, 0);
  });

  testWidgets('an active round shows progress and permits a fresh retry', (
    tester,
  ) async {
    final retryCompleted = Completer<void>();
    final harness = await _pumpHarness(
      tester,
      initialState: DeviceConnectionActionState.searching,
      onRetry: () => retryCompleted.future,
    );
    await _openGate(tester);

    expect(find.text('Đang tìm thiết bị'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byKey(_retry));
    await tester.pump();
    expect(harness.retryCalls, 1);
    expect(tester.widget<FilledButton>(find.byKey(_retry)).onPressed, isNull);
    expect(find.byKey(_cancel).hitTestable(), findsOneWidget);

    retryCompleted.complete();
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byKey(_retry)).onPressed,
      isNotNull,
    );
  });

  testWidgets(
    'finishing a failed round replaces progress with reconnect guidance',
    (tester) async {
      final harness = await _pumpHarness(
        tester,
        initialState: DeviceConnectionActionState.searching,
      );
      await _openGate(tester);

      harness.state.value = DeviceConnectionActionState.unavailable;
      await tester.pump();

      expect(find.text('Cần kết nối thiết bị'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byKey(_retry).hitTestable(), findsOneWidget);
      expect(harness.results, isEmpty);
    },
  );

  testWidgets('retry is single flight and successful readiness resumes once', (
    tester,
  ) async {
    final retryCompleted = Completer<void>();
    final harness = await _pumpHarness(
      tester,
      onRetry: () => retryCompleted.future,
    );
    await _openGate(tester);

    // A second tap before the next frame must not restart the radio again.
    final retryButton = tester.widget<FilledButton>(find.byKey(_retry));
    retryButton.onPressed!();
    retryButton.onPressed!();
    await tester.pump();
    expect(harness.retryCalls, 1);
    expect(find.text('Đang tìm thiết bị'), findsOneWidget);

    harness.state.value = DeviceConnectionActionState.ready;
    await tester.pump();
    await tester.pump();
    expect(harness.results, <bool>[true]);
    expect(find.byKey(_dialog), findsNothing);
    expect(harness.cancelCalls, 0);

    retryCompleted.complete();
    await tester.pump();
    expect(harness.results, <bool>[true]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'cancel closes immediately even while transport cancellation is pending',
    (tester) async {
      final cancellation = Completer<void>();
      final harness = await _pumpHarness(
        tester,
        initialState: DeviceConnectionActionState.searching,
        onCancel: () => cancellation.future,
      );
      await _openGate(tester);

      await tester.tap(find.byKey(_cancel));
      await tester.pump();
      expect(harness.results, <bool>[false]);
      expect(harness.cancelCalls, 1);
      expect(find.byKey(_dialog), findsNothing);
      expect(find.byKey(_action).hitTestable(), findsOneWidget);

      harness.state.value = DeviceConnectionActionState.ready;
      cancellation.complete();
      await tester.pump();
      expect(harness.results, <bool>[false]);
      expect(find.byKey(_dialog), findsNothing);
    },
  );

  testWidgets(
    'late retry completion after Cancel cannot resume the abandoned action',
    (tester) async {
      final retryCompleted = Completer<void>();
      final harness = await _pumpHarness(
        tester,
        onRetry: () => retryCompleted.future,
      );
      await _openGate(tester);
      await tester.tap(find.byKey(_retry));
      await tester.pump();

      await tester.tap(find.byKey(_cancel));
      await tester.pump();
      harness.state.value = DeviceConnectionActionState.ready;
      retryCompleted.complete();
      await tester.pump();

      expect(harness.results, <bool>[false]);
      expect(harness.cancelCalls, 1);
      expect(find.byKey(_dialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'repeated actions share one dialog and only the original can continue',
    (tester) async {
      final harness = await _pumpHarness(tester);
      await _openGate(tester);

      final duplicate = await harness.gate.ensureConnected(harness.context);
      expect(duplicate, isFalse);
      expect(find.byKey(_dialog), findsOneWidget);

      harness.state.value = DeviceConnectionActionState.ready;
      await tester.pump();
      expect(harness.results, <bool>[true]);
      expect(harness.cancelCalls, 0);
    },
  );

  testWidgets(
    'system Back cancels the action and later readiness stays silent',
    (tester) async {
      final harness = await _pumpHarness(tester);
      await _openGate(tester);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(harness.results, <bool>[false]);
      expect(harness.cancelCalls, 1);
      harness.state.value = DeviceConnectionActionState.ready;
      await tester.pump();
      expect(find.byKey(_dialog), findsNothing);
      expect(harness.results, <bool>[false]);
    },
  );

  testWidgets(
    'late success preserves a newer page without resuming the old action',
    (tester) async {
      final harness = await _pumpHarness(tester);
      await _openGate(tester);
      unawaited(
        harness.navigatorKey.currentState!.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Newer page')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      harness.state.value = DeviceConnectionActionState.ready;
      await tester.pumpAndSettle();

      expect(find.text('Newer page').hitTestable(), findsOneWidget);
      expect(find.byKey(_dialog), findsNothing);
      expect(harness.results, <bool>[false]);
      expect(harness.cancelCalls, 1);
    },
  );

  testWidgets(
    'a transient ready update does not close a still-disconnected prompt',
    (tester) async {
      final harness = await _pumpHarness(tester);
      await _openGate(tester);

      harness.state.value = DeviceConnectionActionState.ready;
      harness.state.value = DeviceConnectionActionState.unavailable;
      await tester.pump();

      expect(find.byKey(_dialog), findsOneWidget);
      expect(find.text('Cần kết nối thiết bị'), findsOneWidget);
      expect(harness.results, isEmpty);
    },
  );

  testWidgets('failed retry clears its spinner and can be tried again', (
    tester,
  ) async {
    final harness = await _pumpHarness(
      tester,
      onRetry: () => Future<void>.error(StateError('radio unavailable')),
    );
    await _openGate(tester);

    await tester.tap(find.byKey(_retry));
    await tester.pump();
    expect(find.text('Cần kết nối thiết bị'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byKey(_retry)).onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(_retry));
    await tester.pump();
    expect(harness.retryCalls, 2);
    expect(harness.results, isEmpty);
  });

  testWidgets(
    'disposing a pending gate resolves false and ignores further requests',
    (tester) async {
      final harness = await _pumpHarness(tester);
      await _openGate(tester);

      harness.gate.dispose();
      await tester.pump();
      expect(harness.results, <bool>[false]);
      expect(harness.cancelCalls, 1);
      expect(find.byKey(_dialog), findsNothing);
      harness.state.value = DeviceConnectionActionState.ready;
      expect(await harness.gate.ensureConnected(harness.context), isFalse);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _openGate(WidgetTester tester) async {
  await tester.tap(find.byKey(_action));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<_Harness> _pumpHarness(
  WidgetTester tester, {
  DeviceConnectionActionState initialState =
      DeviceConnectionActionState.unavailable,
  Future<void> Function()? onRetry,
  Future<void> Function()? onCancel,
}) async {
  final harness = _Harness(initialState, onRetry: onRetry, onCancel: onCancel);
  addTearDown(() async {
    harness.gate.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    harness.state.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: harness.navigatorKey,
      home: Scaffold(
        body: Builder(
          builder: (context) {
            harness.context = context;
            return TextButton(
              key: _action,
              onPressed: () async {
                harness.results.add(
                  await harness.gate.ensureConnected(context),
                );
              },
              child: const Text('Start protected action'),
            );
          },
        ),
      ),
    ),
  );
  return harness;
}

class _Harness {
  _Harness(
    DeviceConnectionActionState initialState, {
    Future<void> Function()? onRetry,
    Future<void> Function()? onCancel,
  }) : state = ValueNotifier(initialState) {
    gate = DeviceConnectionActionGate(
      state: state,
      onRetry: () async {
        retryCalls += 1;
        await onRetry?.call();
      },
      onCancel: () async {
        cancelCalls += 1;
        await onCancel?.call();
      },
    );
  }

  final ValueNotifier<DeviceConnectionActionState> state;
  final navigatorKey = GlobalKey<NavigatorState>();
  final results = <bool>[];
  late final DeviceConnectionActionGate gate;
  late BuildContext context;
  int retryCalls = 0;
  int cancelCalls = 0;
}
