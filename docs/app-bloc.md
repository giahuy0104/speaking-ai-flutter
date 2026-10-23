# AppBloc — phạm vi đầu tiên (23/10/2026)

AppBloc sở hữu trạng thái khởi động, quyền sử dụng app theo consent/chế độ hạn chế và quyết định onboarding/Home. `ready` nghĩa là hoàn tất thiết lập app, không có nghĩa HOMI đã kết nối.

## Cấu trúc

```text
lib/presentation/app/bloc/
  app_bloc.dart
  app_event.dart
  app_state.dart
lib/app/di/
  app_dependencies.dart
```

Ba file Bloc/Event/State dùng `part`/`part of`, cùng cách tổ chức DeviceBloc. `AppDependencies` inject `AppStartupLoader`, callback resume và callback báo lỗi qua constructor; mỗi AiSpeakingApp sở hữu một scope, đóng khi dispose. Không global singleton hay package DI bổ sung. `AiSpeakingApp.appDependenciesFactory` cho phép thay scope để test/wrap loader; app vẫn là bên dispose scope được trả về.

`BlocProvider.value` bọc `MaterialApp`; `BlocBuilder` rebuild giao diện khi state app thay đổi. Giữ navigatorKey, router, observer và cơ chế chọn `home` hiện có. Không đẩy route mới chỉ để biểu diễn ready.

## State

| Giá trị | Ý nghĩa |
|---|---|
|initial|Trước tác vụ khởi tạo sau frame đầu|
|initializing|Đang đọc profile/consent/setup đã lưu|
|onboardingRequired|Chưa đủ điều kiện hoàn tất thiết lập|
|ready|Có profile hợp lệ, đã hoàn tất thiết lập và có consent hoặc chọn hạn chế|
|initializationFailed|Loader gặp lỗi chưa được xử lý; UI hiển thị nút thử lại|

Trường kèm theo: `usageMode` full/limited, `privacyConsentGranted`, `failure` có kiểu. Full không tự đồng nghĩa quyền micro/Bluetooth đã được cấp. Snapshot bootstrap chỉ truyền kết quả kiểm tra profile, không lưu bản sao tuổi/settings vào AppState. Consent hợp lệ được ưu tiên hơn cờ limited cũ khi đọc storage, như trước.

Đã bỏ bốn biến mutable ở widget: startupProfileLoading, privacyConsentGranted, limitedModeSelected, parentSetupCompleted. Các getter tương thích đọc từ AppBloc. Theme, ngôn ngữ, tuổi, ngưỡng VAD và tùy chọn dừng âm thanh nền đã chuyển sang [SettingsBloc](settings-bloc.md); tuổi đang chọn trong onboarding vẫn là draft ở view. Model consent, quyền OS, microphone, trạng thái DeviceBloc và feature controller giữ chủ sở hữu cũ. AppState không nhân bản các giá trị Settings.

## Event và thứ tự xử lý

- `AppStarted`: gọi loader inject một lần, chống khởi tạo trùng; ready/onboarding đã ổn định thì không tải lại đè lựa chọn người dùng.
- `AppConsentGranted`, `AppLimitedModeSelected`, `AppConsentRevoked`: gửi sau khi thao tác lưu/xóa cũ hoàn tất.
- `AppOnboardingCompleted`: UI vẫn kiểm tra tuổi, consent/mode và HOMI theo điều kiện cũ trước khi ghi completion rồi gửi event. Bloc kiểm tra profile/access nhưng không sở hữu điều kiện Bluetooth.
- `AppOnboardingReopened`: sau khi clear limited/completion trong storage, quay về onboarding, không tự grant consent.
- `AppResumed`: gọi callback hiện có; không đổi ready thành một trạng thái resumed, không đọc lại consent hoặc tự thêm lượt retry thiết bị.

Các command có Future hoàn tất sau khi Bloc xử lý, để background work/permission refresh tiếp tục với state mới theo thứ tự cũ. Revision guard bỏ kết quả bootstrap cũ sau thay đổi consent. Dispose giải phóng lượt khởi tạo đang chờ; callback muộn không phát state mới.

Loader hiện vẫn là adapter `_loadStartupProfile` trong AiSpeakingApp: chờ initializeDeviceConnectionPreferences, đọc các store song song, validate tuổi/config consent, truyền tuổi cho controller và giữ fallback cũ khi đọc profile thất bại. Sau khi Bloc nhận snapshot, `_initializeStartupSetup` tiếp tục background work, đồng bộ retry và permission refresh như trước. Đây là di chuyển state cấp app; chưa di chuyển toàn bộ persistence/controller sang kiến trúc mới.

## Giới hạn và kiểm thử

Không thay Bluetooth/audio, nhịp retry, protocol native, gọi API/chấm bài, model download hay chính sách không fallback mic khi mất MAIN. Không cần thêm state thiết bị vào AppBloc. Lỗi đọc store vốn được fallback về onboarding vẫn giữ fallback; `initializationFailed` dành cho lỗi loader chưa được xử lý, không phải mọi lỗi mạng/profile/thiết bị.

Test mới:16 unit/DI +6 app integration. Bao phủ fresh/stored/full/limited, profile hoặc consent không hợp lệ, completion gate, reopen/revoke, failure/retry, double-start, late result/dispose, resume, DI isolation. App integration dùng AiSpeakingApp thật, native channels giả lập; có6 ca mới và bổ sung assertion cho4 case kết nối Android/iOS service/legacy hiện có.

Lệnh local:

```sh
flutter test --no-pub test/app/bloc
flutter test --no-pub --dart-define-from-file=dart_defines.production.json test/app/bluetooth_power_setup_app_test.dart --plain-name AppBloc
flutter analyze --no-pub
```

Evidence đầy đủ: `../docs/session-artifacts/2026-10-23-app-bloc/summary.md`. Bộ regression app còn15 lỗi overflow20px có sẵn; đã chạy cùng bộ trên bản sao working tree trước task (bao gồm thay đổi diagnostic từ lượt trước), không chỉ so với HEAD. Không cập nhật golden hoặc sửa UI ngoài phạm vi. Không chạy trên điện thoại/HOMI; test local không xác nhận hành vi radio thật.
