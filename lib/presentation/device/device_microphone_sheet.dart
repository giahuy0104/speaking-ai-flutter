import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/device/device_display_name.dart';
import '../../domain/device/device_connection.dart';
import '../../l10n/display_language.dart';
import 'bloc/device_bloc.dart';

class DeviceMicrophoneSheet extends StatelessWidget {
  const DeviceMicrophoneSheet({
    super.key,
    required this.request,
    required this.language,
  });
  final DeviceState request;
  final DisplayLanguage language;
  @override
  Widget build(BuildContext context) => BlocBuilder<DeviceBloc, DeviceState>(
    builder: (context, state) {
      final enabled =
          state.attempt == request.attempt &&
          state.stage == DeviceStage.choosingMicrophone &&
          state.snapshot.mainReady;
      return SafeArea(
        top: false,
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .75,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  key: const Key('parent-homi-microphone-list'),
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  children: [
                    Text(
                      language.choose('Chọn micro HOMI', '选择 HOMI 麦克风'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      language.choose(
                        'Chọn micro của thiết bị HOMI đang sử dụng.',
                        '请选择正在使用的 HOMI 设备的麦克风。',
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final microphone in request.microphones)
                      ListTile(
                        enabled: enabled,
                        leading: const Icon(Icons.headset_mic_rounded),
                        title: Text(
                          localizedDeviceName(
                            microphone.name,
                            language,
                            deviceId: microphone.id,
                          ),
                        ),
                        subtitle: Text(
                          microphone.connected
                              ? language.choose('Đang kết nối', '已连接')
                              : language.choose('Đã ghép đôi', '已配对'),
                        ),
                        onTap: enabled
                            ? () => Navigator.of(context).pop(microphone)
                            : null,
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    key: const Key('parent-homi-microphone-cancel'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(language.choose('Để sau', '稍后')),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
