# SettingsBloc — chuyển đổi từng module (23/10/2026)

SettingsBloc quản lý theme, ngôn ngữ hiển thị, nhóm tuổi, ngưỡng im lặng VAD và tùy chọn dừng âm thanh khi chạy nền. Các lựa chọn cập nhật UI ngay, sau đó lưu qua repository. Consent vẫn thuộc AppBloc; BLE/HFP và retry vẫn thuộc service/coordinator/controller hiện có.

## Cấu trúc

```text
lib/
  app/di/settings_dependencies.dart
  domain/settings/settings_repository.dart
  data/settings/
    stored_settings_repository.dart
    app_theme_mode_store.dart
    child_age_store.dart
    background_media_settings_store.dart
  presentation/settings/
    bloc/
      settings_bloc.dart
      settings_event.dart
      settings_state.dart
    screen/
      settings_screen.dart
      homi_control_diagnostics_screen.dart
    widgets/
      settings_device_section.dart
      settings_preferences_section.dart
      settings_information_section.dart
      settings_ios_device_details.dart
      settings_recognition_section.dart
      ...
```

Các view được di chuyển thực, không để bản sao hay file export tại đường dẫn cũ. Router/Home/test dùng SettingsScreen trong screen/. Đã gộp SettingsSheet và IosSettingsSheet thành một màn hình, lấy giao diện Android làm chuẩn: theme/ngôn ngữ/tuổi là các hàng mở popup lựa chọn. Không còn màn hình Cài đặt iOS riêng. Widget thành phần nằm trong widgets/. Route Settings vẫn là trang đầy đủ, History vẫn là bottom sheet; các view ngoài Settings giữ cho đợt chuyển module tiếp theo.

`features/settings` đã được loại bỏ hoàn toàn. Persistence media nằm tại `data/settings/background_media_settings_store.dart`; mặc định theo nền tảng và policy lifecycle dùng chung nằm tại `core/audio/background_media_policy.dart`. SettingsBloc sở hữu giá trị tùy chọn, còn Home áp dụng policy vào lifecycle. Các port/model từ feature khác và l10n vẫn được tái sử dụng; chưa tuyên bố toàn source đã thành kiến trúc mới hoàn toàn. Contract dùng lại ThemeMode và DisplayLanguage để tránh đổi kiểu dữ liệu trong đợt này.

## DI và chủ sở hữu

`SettingsDependencies` nhận SettingsRepository, validator tuổi, callback áp dụng ngôn ngữ/tuổi/VAD và kiểm tra trạng thái bận qua constructor. Mặc định dùng StoredSettingsRepository; test thay bằng fake. AiSpeakingApp tạo scope một lần và đóng Bloc khi dispose. Không global singleton hoặc thư viện DI mới.

BlocProvider bọc MaterialApp. BlocBuilder ở root chỉ rebuild khi giá trị theme/ngôn ngữ/tuổi thay đổi. SettingsBloc được truyền rõ qua Home → SettingsBindings → SettingsScreen để trang đang mở nhận state trực tiếp. Android/iOS/web dùng cùng BlocConsumer và SettingsPreferencesSection. Lỗi lưu mới hiển thị Snackbar có Thử lại khi trang đang mở.

ConversationController giữ bản sao ngôn ngữ/tuổi phục vụ runtime cũ, nhưng app không còn cấp DisplayLanguageStore cho controller. Yêu cầu đổi ngôn ngữ từ caller cũ được chuyển vào Bloc; callback apply chỉ cập nhật controller, không ghi storage lần hai. Các caller độc lập không inject Bloc vẫn giữ cơ chế cũ. Tuổi được đẩy tới conversation, voice navigation và web speech bằng adapter hiện có. Chọn tuổi onboarding vẫn là draft; hoàn tất mới gửi event rồi đánh dấu setup complete.

## Persistence và cạnh tranh tác vụ

- Giữ key `innotrik.app-theme-mode.v1`, `innotrik.child-age.v1`; ngôn ngữ vẫn dùng file native `display-language.txt` hoặc web storage cũ. Không reset preference.
- Read fallback của store cũ giữ nguyên; lỗi read bị store xử lý thành default không trở thành lỗi mới trên UI.
- State có loading/saving/loaded và typed failure theo từng trường. Choice của người dùng là giá trị ưu tiên, kể cả khi startup read chưa bắt đầu hoặc trả về muộn.
- Mỗi trường lưu theo thứ tự event; các trường độc lập. Bấm liên tiếp không để write cũ ghi đè lựa chọn mới. Lỗi write cũ không gán lỗi cho lựa chọn mới.
- Lưu thất bại giữ lựa chọn hiện tại và cho retry giá trị mới nhất. Clear tuổi khi revoke consent nằm trong cùng hàng đợi, tránh write đang chờ khôi phục dữ liệu vừa xóa.
- Dispose ngừng emit/callback và giải phóng handler đang chờ. Những write đã nhận vẫn hoàn tất lưu; không hủy persistence giữa chừng.

Không thay API, luồng chấm bài/offline, pairing, MAIN/HFP, nhịp retry hoặc fallback micro. Bộ kiểm tra kiến trúc đã mở rộng sang các thư mục presentation/domain/data mới để việc move không bỏ qua quy tắc phân lớp.

## Kiểm chứng local

Test mới bao gồm: khôi phục dữ liệu, tuổi không hợp lệ, read trước/sau lựa chọn, write liên tiếp, lỗi/retry, clear sau write, dispose khi IO còn chờ; tích hợp trang Settings Android/iOS, đổi theme/ngôn ngữ/tuổi, mở lại trang, đọc lại storage và adapter controller cũ. Test kiến trúc fixture khóa việc gọi channel trực tiếp/import ngược từ các layer mới.

App integration dùng mock native channels và IO file tạm, không mô phỏng radio hoặc microphone thật. Không chạy/cài app trên điện thoại/HOMI.

Evidence và đối chứng baseline: `HOMI/docs/session-artifacts/2026-10-23-settings-bloc/`. Kết quả tổng được ghi trong summary.md và SESSION.md; các test cũ thất bại phải so tên/nguyên nhân với snapshot trước task, không cập nhật golden để làm xanh bộ test.

## Gộp screen, dùng Android làm chuẩn

SettingsScreen chỉ ghép bố cục và nối Bloc/callback. SettingsDeviceSection giữ vòng đời thao tác kết nối/cancel của Android cùng coordinator; SettingsPreferencesSection sở hữu popup lựa chọn; SettingsInformationSection sở hữu link và các thao tác consent. Widget con được tách thành file trong widgets/.

Các khác biệt thật sự của nền tảng vẫn là section: SettingsIosDeviceDetails giữ picker BLE/HFP và chẩn đoán iOS, không chứa header, tùy chọn chung hay một scroll/page thứ hai. Gói offline, VAD, media nền, lịch sử và các hành động iOS được giữ. Không thay transport, nhịp retry hoặc quyền hệ điều hành. Các nhánh Android hardware-test trong view iOS cũ vốn không được render đã bỏ cùng bản view đó; native/controller không đổi.

Kiểm tra bổ sung: cả Android/iOS trên 320×568, text scale 2, VI/ZH, theme sáng/tối; app integration đổi và lưu lựa chọn dùng chung UI, picker HFP có thể hủy, vào chẩn đoán iOS. Golden Settings Android giữ nguyên. Evidence: HOMI/docs/session-artifacts/2026-10-23-settings-screen/.

## VAD và âm thanh nền vào SettingsBloc

- `SettingsVadSilenceChanged` cập nhật `vadSilenceMs`, mặc định 700 ms, clamp 400–1600 ms. Kiểm tra controller bận khi xử lý event; slider vẫn bị khóa khi bận. VAD chỉ có hiệu lực trong phiên, không thêm key lưu, không bị load preferences ghi đè.
- DI nối event VAD tới `ConversationController.applyVadSilence`; caller cũ gọi `setVadSilence` được chuyển về Bloc. Callback apply không dispatch ngược. Controller độc lập không inject delegate vẫn dùng setter cũ.
- `SettingsStopMediaWhenBackgroundedChanged` cập nhật state và lưu qua SettingsRepository → store cũ, key `homi.parent.stop-media-when-backgrounded.v1`. Giữ mặc định tắt Android, bật iOS/web, khôi phục giá trị người dùng đã lưu và fallback read cũ.
- Home đọc giá trị mới nhất từ Bloc tại thời điểm lifecycle đổi. Giữ xử lý hidden/paused/detached và ngoại lệ khóa màn hình Android. Không đổi stop/cancel runtime, MAIN, routing audio hoặc nhịp retry. Caller Home độc lập không inject Bloc vẫn dùng store/callback cũ.
- SettingsScreen đọc state và gửi event; giữ vị trí/điều kiện hiển thị hai tùy chọn (hiện section trên iOS như trước). Root chỉ rebuild theo theme/ngôn ngữ/tuổi; audio preference không dựng lại toàn app.
- Media kế thừa cơ chế lưu theo thứ tự, chống read cũ ghi đè, lỗi lưu và Thử lại. VAD không dùng persistence/loading/saving.

Test bổ sung khóa mặc định/giới hạn/busy/reset của VAD, store key media cũ, nền tảng, read/write cạnh tranh và retry; integration Android/iOS đi qua Settings rồi mở lại; mô phỏng phiên MAIN khi về nền với tùy chọn bật/tắt và màn hình khóa. Evidence: `HOMI/docs/session-artifacts/2026-10-23-settings-audio-bloc/`.

## Module Lịch sử độc lập

HistorySheet đã chuyển sang `presentation/history/screen`, widget con ở `presentation/history/widgets`, state nghiệp vụ thuộc HistoryBloc/Event/State và DI tại app/di/history_dependencies.dart. Settings vẫn mở bottom sheet như trước, nhưng phải inject factory Bloc. Xem [HistoryBloc](history-bloc.md).

## Quản lý gói offline

SettingsOfflineLanguagePacksCard đã chuyển toàn bộ state nghiệp vụ sang OfflineServiceBloc riêng; SettingsBloc không ôm trạng thái tải model. Factory qua SettingsScreen → SettingsRecognitionSection → card, service/Bloc tạo qua OfflineDependencies. Xem [OfflineServiceBloc](offline-service-bloc.md).
