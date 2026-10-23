import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/app/device_connection_feedback_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('iOS reconnect notice stays small and does not block taps', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Stack(
            children: <Widget>[
              Positioned.fill(
                child: TextButton(
                  onPressed: () => taps += 1,
                  child: const Text('Continue'),
                ),
              ),
              const Center(child: IosBleReconnectNotice()),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Đang kết nối lại HM-D001…'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('ios-ble-reconnect-notice')),
        matching: find.byType(ModalBarrier),
      ),
      findsNothing,
    );
    await tester.tapAt(
      tester.getCenter(find.byKey(const Key('ios-ble-reconnect-notice'))),
    );
    expect(taps, 1);
  });

  testWidgets('shows HOMI progress while H20 transports are connecting', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const DeviceConnectionFeedbackOverlay(
          stage: DeviceConnectionFeedbackStage.connecting,
        ),
      ),
    );

    expect(find.text('Đang kết nối thiết bị'), findsOneWidget);
    expect(find.byKey(const Key('device-connection-progress')), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('shows success only after MAIN control and H20 mic connect', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const DeviceConnectionFeedbackOverlay(
          stage: DeviceConnectionFeedbackStage.connected,
        ),
      ),
    );

    expect(find.text('Đã kết nối thiết bị'), findsOneWidget);
    expect(
      find.byKey(const Key('device-connection-success-icon')),
      findsOneWidget,
    );
    expect(find.textContaining('Nút MAIN và micro HM-D001'), findsOneWidget);
  });
}
