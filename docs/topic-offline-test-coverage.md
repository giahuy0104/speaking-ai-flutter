# Kiểm thử đầy đủ feature offline Chủ đề

Cập nhật 23/10/2026. Chạy local; không cài/chạy app trên điện thoại.

## Coverage

| Luồng | Test |
| --- | --- |
| Chưa hoàn tất onboarding không chuẩn bị model | `test/app/topic_offline_preparation_app_test.dart` |
| Home bắt đầu chuẩn bị, tải đang chờ vẫn điều hướng được sang Chủ đề | Cùng app test; callback/lifecycle/navigation/service dùng implementation thật, native channel được mock |
| Chờ Wi-Fi, đổi màn hình, resume, gọi trùng, lỗi native rồi phục hồi | App test và `topic_offline_model_preparation_service_test.dart` |
| Opt-out được lưu, đổi lựa chọn rồi resume, dispose ngừng retry | App test, service test, `offline_language_packs_ios_test.dart` |
| Chỉ chuẩn bị en-US, không bật consent hoặc tải thêm bộ dịch | App/service tests; `offline_language_service_test.dart` kiểm tra channel riêng không dùng prepareLocale |
| Android thiếu model + offline không sinh điểm; model cài xong nhận dạng local không gọi backend | Hai test mới trong `lesson_attempt_evaluator_test.dart`, nối preparation service → native channel giả lập → evaluator thật |
| iOS Core lỗi model/network không ghi sai/Sao/tiến độ | Hai test mới trong `lesson_guided_flow_test.dart` |
| Core/Challenge giữ bản thu, chấm lại cùng attempt; MAIN bỏ callback đến muộn | `lesson_guided_flow_test.dart`, `lesson_challenge_screen_test.dart` |
| Nhận dạng local, API fallback/timeout, lựa chọn cuối bài | `lesson_attempt_evaluator_test.dart`, `lesson_completion_choice_recognizer_test.dart`, iOS speech/turn tests |
| Job Android duy nhất, giữ progress, network/storage constraints | `HomiOfflineSpeechModelSchedulingTest.kt` với WorkManager thật trong Robolectric |
| Hủy job giữ partial archive; bật lại có một job; không xóa model đã cài; marker không đủ nếu thiếu file | Ba native test mới cùng file |

## Chạy lại

Từ thư mục `speaking-ai-flutter`:

```sh
flutter test --no-pub test/app/topic_offline_preparation_app_test.dart --reporter expanded
flutter test --no-pub test/features/listening test/features/home test/features/settings test/features/conversation/offline_language_service_test.dart test/core_audio_ios_streaming_speech_input_test.dart test/core_audio_ios_speech_turn_test.dart --reporter expanded
flutter analyze --no-pub
```

Kiểm tra app với cấu hình production (vẫn mock platform, không gọi thiết bị thật):

```sh
flutter test --no-pub --dart-define-from-file=dart_defines.production.json test/app/topic_offline_preparation_app_test.dart --reporter expanded
```

Android native, dùng JDK tương thích dự án:

```sh
JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home' android/gradlew -p android :app:testDebugUnitTest
```

## Kết quả

Thêm **13 test mới**, tất cả qua. Full scoped Flutter: **786 qua / 22 lỗi có sẵn** (780 từ suite mở rộng + 6 app test, không cộng lặp lần chạy production). Native Android: **111/111 qua**. Analyzer sạch.

22 lỗi gồm 10 golden Chủ đề, 9 golden Home, 1 golden History và 2 assertion vị trí nút mây. Rerun 5 file tương ứng trên snapshot HEAD trước offline cho đúng cùng 22 tên lỗi; 21 ảnh failure có chung đường dẫn giống byte-for-byte. Không cập nhật golden hoặc sửa logic runtime trong đợt test này.

## Giới hạn

Đây là kiểm chứng tự động ở mức app/widget/service và Android JVM; không phải end-to-end nhận dạng giọng nói trên phần cứng. iOS native download/NWPath và kết quả ASR được mô phỏng; chính sách tải do Apple quản lý, khả năng offline trên từng iPhone/iOS và âm thanh HOMI vẫn cần người dùng thử. Không có tải model thật trong test. Simulator iOS native bị hạn chế bởi binary MLKitCommon đã ghi nhận ở đợt trước.

Evidence: `../../docs/session-artifacts/2026-10-23-topic-offline-full-tests/summary.md` và các log cùng thư mục.

## Mô phỏng sử dụng khi không có HOMI — 23/10/2026

Theo lựa chọn của user, chạy tự động và báo kết quả; không thêm chế độ giả lập vào app. Thêm 4 test, giữ nguyên code runtime:

| Tình huống mô phỏng mới | Assertion chính |
| --- | --- |
| Model chưa có, người học đã thu âm, đang offline; model sau đó sẵn sàng | Giữ bản thu, không ghi sai/Sao/tiến độ khi chưa chấm được; model sẵn sàng không tự chấm; bấm chấm lại dùng cùng đường dẫn, không thu lần hai, matcher thật cấp Sao; backend không được gọi |
| Model đã có nhưng transcript không khớp câu mẫu | Không cấp Sao hoặc sang câu tiếp; không hiện nút retry lỗi dịch vụ; backend không được gọi |
| MAIN tạm dừng trong khi đang đợi nhận dạng offline | Kết quả đúng đến muộn không ghi Sao/session result hoặc sang câu khác |
| Mic HOMI mất route giữa lúc thu, chỉ còn mic điện thoại; HOMI sau đó kết nối lại | Hủy capture và báo lỗi; lượt thử khi HOMI chưa trở lại không mở recorder điện thoại; khi route và input HOMI trở lại, thu lượt mới thành công bằng input HOMI |

Ba test phiên học dùng `LessonPracticeScreen`, preparation service, offline evaluator và matcher thật; mock media/native model/ASR. Test mic dùng `LessonMediaService` thật với HFP/input/recorder giả lập, tạo file WAV fixture để kiểm tra kết thúc lượt thu. Đây là hai lớp kiểm chứng bổ sung nhau, chưa phải một phiên end-to-end đi xuyên BLE và engine nhận dạng thật. MAIN được mô phỏng qua registry mà dispatcher sử dụng, không phát gói BLE thật.

Chạy lại riêng 4 test mới:

```sh
flutter test --no-pub test/features/listening/lesson_guided_flow_test.dart test/features/listening/lesson_media_service_test.dart --plain-name 'simulated HOMI session:' --reporter expanded
```

Kết quả đợt này: **329/329 test qua** trong 9 file Core/Challenge/media/evaluator/completion-choice/preparation/app/iOS speech/turn, gồm 4 test mới. Analyzer và diff check sạch. Không chạy lại full golden suite trong đợt này; 22 lỗi UI của lượt full trước vẫn được ghi riêng ở trên. Không có thay đổi runtime, cài app, kết nối hoặc test trên điện thoại.

Chi tiết, lệnh chạy 9 file và log: `../../docs/session-artifacts/2026-10-23-topic-offline-simulation/summary.md`.
