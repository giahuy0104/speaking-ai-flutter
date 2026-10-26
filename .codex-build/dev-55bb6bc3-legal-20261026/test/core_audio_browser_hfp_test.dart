import 'package:ai_speaking_flutter_app/core/audio/audio_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/browser_hfp_audio_control.dart';
import 'package:ai_speaking_flutter_app/core/audio/hfp_audio_control.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recognizes common browser Bluetooth microphone labels', () {
    expect(isLikelyBrowserHfpLabel('AirPods Microphone'), isTrue);
    expect(isLikelyBrowserHfpLabel('INNOTRIK'), isTrue);
    expect(
      isLikelyBrowserHfpLabel('Headset (WH-1000XM5 Hands-Free AG Audio)'),
      isTrue,
    );
    expect(isLikelyBrowserHfpLabel('iPhone Microphone'), isFalse);
    expect(isLikelyBrowserHfpLabel('Default - Microphone Array'), isFalse);
  });

  test('automatic HM-D001 selection ignores an unrelated connected headset', () {
    const devices = <HfpAudioDevice>[
      HfpAudioDevice(id: 'airpods', name: 'AirPods Pro', isConnected: true),
      HfpAudioDevice(id: 'hm-d001', name: 'HM-D001', isConnected: false),
    ];

    expect(selectLikelyHomiHfpDevice(devices, bleDeviceName: 'HM-D001')?.id, 'hm-d001');
    expect(
      selectLikelyHomiHfpDevice(const <HfpAudioDevice>[
        HfpAudioDevice(id: 'airpods', name: 'AirPods Pro', isConnected: true),
      ], bleDeviceName: 'HM-D001'),
      isNull,
    );
  });

  test('connected-only selection waits for the matching HFP profile', () {
    const devices = <HfpAudioDevice>[
      HfpAudioDevice(id: 'paired', name: 'HM-D001', isConnected: false),
      HfpAudioDevice(id: 'live', name: 'HM-D001', isConnected: true),
    ];

    expect(selectLikelyHomiHfpDevice(devices, connectedOnly: true)?.id, 'live');
    expect(
      selectLikelyHomiHfpDevice(devices.take(1), connectedOnly: true),
      isNull,
    );
  });

  test('automatic HM-D001 selection accepts known ODM device names', () {
    const devices = <HfpAudioDevice>[
      HfpAudioDevice(id: 'odm', name: 'INNOTRIK HFP', isConnected: true),
    ];

    expect(selectLikelyHomiHfpDevice(devices)?.id, 'odm');
  });

  test('automatic HFP selection accepts HM-D001 without a BLE name', () {
    const devices = <HfpAudioDevice>[
      HfpAudioDevice(id: 'airpods', name: 'AirPods Pro', isConnected: true),
      HfpAudioDevice(id: 'hm', name: 'HM-D001', isConnected: true),
    ];

    expect(selectLikelyHomiHfpDevice(devices)?.id, 'hm');
    expect(
      selectLikelyHomiHfpDevice(const <HfpAudioDevice>[
        HfpAudioDevice(id: 'other', name: 'HM-D001-OTHER', isConnected: true),
      ]),
      isNull,
    );
  });

  test(
    'ambiguous same-name microphones require selection or saved identity',
    () {
      const devices = [
        HfpAudioDevice(id: 'first', name: 'HM-D001', isConnected: true),
        HfpAudioDevice(id: 'second', name: 'HM-D001', isConnected: true),
      ];
      expect(selectLikelyHomiHfpDevice(devices), isNull);
      expect(
        selectLikelyHomiHfpDevice(devices, preferredDeviceId: 'second')?.id,
        'second',
      );
      expect(
        selectLikelyHomiHfpDevice(
          devices,
          bleDeviceId: 'first',
          preferredDeviceId: 'second',
        )?.id,
        'first',
      );
    },
  );

  test(
    'an unnamed microphone never borrows its identifier as a device name',
    () {
      const device = HfpAudioDevice(
        id: 'HM-D001-looking-id',
        name: '',
        isConnected: true,
      );
      expect(device.displayName, isEmpty);
      expect(selectLikelyHomiHfpDevice([device]), isNull);
    },
  );

  test('automatic HFP selection ignores a disconnected HM-D001', () {
    const devices = <HfpAudioDevice>[
      HfpAudioDevice(id: 'hm-d001', name: 'HM-D001', isConnected: false),
      HfpAudioDevice(id: 'other', name: 'Other headset', isConnected: true),
    ];

    expect(selectLikelyHomiHfpDevice(devices, connectedOnly: true), isNull);
    expect(
      selectLikelyHomiHfpDevice(
        devices,
        bleDeviceName: 'HM-D001',
        connectedOnly: true,
      ),
      isNull,
    );
  });

  test(
    'lists, selects, routes and releases a browser HFP microphone',
    () async {
      final input = _FakeSelectableAudioInput(<SelectableAudioInputDevice>[
        const SelectableAudioInputDevice(
          id: 'phone',
          label: 'iPhone Microphone',
        ),
        const SelectableAudioInputDevice(
          id: 'airpods',
          label: 'AirPods Microphone',
        ),
      ]);
      final control = BrowserHfpAudioControl(enabled: true, audioInput: input);

      await control.initialize();
      final devices = await control.findDevices();
      expect(devices, hasLength(1));
      expect(devices.single.id, 'airpods');

      await control.connect(devices.single);
      expect(input.selectedAudioInputDevice?.id, 'airpods');
      expect(control.status.phase, BluetoothAudioConnectionPhase.ready);

      await control.startAudioRoute();
      expect(control.status.phase, BluetoothAudioConnectionPhase.recording);
      await control.stopAudioRoute();
      expect(control.status.phase, BluetoothAudioConnectionPhase.ready);

      await control.disconnect();
      expect(input.selectedAudioInputDevice, isNull);
      expect(control.status.phase, BluetoothAudioConnectionPhase.idle);
      await control.dispose();
    },
  );

  test(
    'does not claim HFP when the browser only exposes the phone mic',
    () async {
      final input = _FakeSelectableAudioInput(<SelectableAudioInputDevice>[
        const SelectableAudioInputDevice(
          id: 'phone',
          label: 'iPhone Microphone',
        ),
      ]);
      final control = BrowserHfpAudioControl(enabled: true, audioInput: input);

      expect(await control.findDevices(), isEmpty);
      expect(control.status.phase, BluetoothAudioConnectionPhase.idle);
      expect(control.status.message, contains('chưa hiển thị mic Bluetooth'));
      await control.dispose();
    },
  );
}

class _FakeSelectableAudioInput implements SelectableAudioInputControl {
  _FakeSelectableAudioInput(this.devices);

  final List<SelectableAudioInputDevice> devices;

  @override
  SelectableAudioInputDevice? selectedAudioInputDevice;

  @override
  Future<List<SelectableAudioInputDevice>> listAudioInputDevices() async =>
      devices;

  @override
  Future<void> selectAudioInputDevice(
    SelectableAudioInputDevice? device,
  ) async {
    selectedAudioInputDevice = device;
  }
}
