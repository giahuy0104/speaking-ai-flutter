# Đồng bộ nội dung và luồng iOS — 2026-09-19

## Phạm vi đã cập nhật

iOS và Android dùng chung Flutter cho nội dung, điều hướng và tiến độ. Không
sao chép một bộ dữ liệu iOS độc lập; không đổi ID bài học, xóa tiến độ hoặc
ghi âm cũ. Đây là đồng bộ tính năng trong code, không phải dịch vụ chuyển dữ
liệu người dùng giữa hai điện thoại.

| Hạng mục | Cách dùng trên iOS | Kiểm chứng tự động |
| --- | --- | --- |
| Nội dung chủ đề | Cùng 50 chủ đề, 109 bài, 565 mục Core; gồm patch 4 chủ đề chữ/số, tái sử dụng audio cũ | Repository tải asset thực trên Android/iOS; so sánh nội dung, ID, câu hỏi, đáp án và audio |
| Chủ đề/luyện nghe | Cùng nhóm tuổi, Level, mở bài, Core → Challenge → lựa chọn cuối bài, học lại/tiếp tục | Test điều hướng MAIN theo tuổi/chủ đề và chọn Học lại/Bài 2 trên iOS |
| Bộ từ vựng | Cùng Ba mẹ đã thêm, Ngôi sao, Luyện lại, âm thanh và dữ liệu được lưu | Widget test ba mục và Back/hủy hàng đợi audio trên cả hai nền tảng |
| Trợ lý MAIN | Dùng chung bộ nhận ý định, chọn từ vựng/chủ đề, tạm dừng/tiếp tục và chuyển sang dịch | Test cùng luồng với hai TargetPlatform; các test cancellation/ownership của MAIN |
| Luyện phát âm | Apple Speech → đối chiếu đáp án cục bộ; im lặng không tự tính sai | Core/Challenge/Review, no-response, quyền mic, lỗi native, callback muộn |
| Lựa chọn cuối bài | Apple Speech tiếng Việt cả foreground/background đã được chuẩn bị hợp lệ; không recorder thứ hai | Không gọi media recorder; nhấn MAIN khi đang mở/dừng mic không để kết quả cũ can thiệp |
| Ghi âm bài học | WAV PCM16, giữ sample rate/channel thực, lưu và phát lại cục bộ | Swift tests được khai báo trong RunnerTests; cần Codemagic/Xcode chạy |
| Dịch | Giữ Apple Speech + dịch văn bản/API hoặc model offline hiện có | Các test iOS speech/offline translation và chuyển từ MAIN sang dịch |

## Các khác biệt nền tảng giữ có chủ đích

- Không đưa API chấm audio Android sang iPhone. Lỗi nhận giọng nói trong luồng
  chấm bài không âm thầm kích hoạt một recorder/backend khác.
- Lỗi mic/Apple Speech ở lựa chọn cuối bài vẫn cho phép chạm nút để chọn.
- Dịch/trợ lý có chính sách API, consent và fallback riêng sẵn có; không suy ra
  toàn ứng dụng offline hoặc tuyệt đối không gửi audio chỉ từ việc chấm bài cục bộ.
- iOS dùng MAIN chủ động; không tự bật vòng wake-word luôn nghe của Android.
- Học nền/khóa màn hình vẫn theo cơ chế iOS hiện có: microphone phải được chuẩn
  bị hợp lệ khi foreground, có quyền và route phù hợp. Không giả lập khả năng
  hệ điều hành không cung cấp; cần kiểm chứng trên iPhone thật.
- Nút H20 chưa có bằng chứng firmware vẫn là UNKNOWN. Mô phỏng trong Settings
  không chứng minh nhận được nút vật lý.

## Audio thiếu: giữ TTS theo xác nhận của người dùng

16 câu cố định thiếu asset được liệt kê trong
`test/support/approved_assistant_tts_fallbacks.dart`. Runtime vẫn dùng fallback
native TTS sẵn có, không đổi lời thoại, không sinh/download audio mới và không
ánh xạ sang file khác lời. `assistant_audio_inventory_test.dart` vẫn chặn câu
thiếu ngoài danh sách, mapping trùng và asset/hash/receipt không hợp lệ.

`assistant_approved_tts_fallback_test.dart` kiểm tra đầy đủ danh sách trên
Android và iOS với ba route: mặc định, loa điện thoại và thiết bị đã chọn. Mỗi
câu phải gọi TTS đúng một lần; không gọi phát file, tải audio hay upload audio.
Các tiêu đề động tiếp tục đi qua cơ chế TTS hiện có của ứng dụng.

## Build và nghiệm thu

Kiểm tra tại workspace Windows ngày 2026-09-19: **1.196 test trong bộ `test/`
đạt**, `flutter analyze --no-pub` không có lỗi/cảnh báo và kiểm tra ranh giới
kiến trúc đạt. Hai test inventory từng chặn Codemagic đã đạt, không bị bỏ qua.
Chưa chạy Swift/XCTest, simulator hoặc iPhone/H20 thật trong lượt này.

1. Chạy `flutter analyze`, `dart run tool/check_architecture_boundaries.dart`
   và `flutter test`. Không bỏ hai test inventory cũ khỏi CI.
2. Trên Codemagic chạy `ios-bootstrap` để build simulator và RunnerTests.
   Windows không biên dịch được Swift/Xcode; TargetPlatform.iOS trong widget
   test chỉ xác nhận hành vi Flutter, không thay thế chạy native.
3. Khi bootstrap đạt, chạy `ios-app-store` với signing/privacy configuration
   có sẵn. Xem `docs/ios-app-store-release.md`. Chưa tự kích hoạt build/upload.
4. TestFlight: kiểm tra từng mục bảng trên bằng mic iPhone và H20; kiểm tra từ
   chối quyền, mất Bluetooth, mất mạng, thiếu model, MAIN giữa lượt, Back và
   khóa/mở màn hình. Xác minh đúng một cue, đúng thiết bị phát và không để mic
   của lượt cũ ảnh hưởng lượt mới.

Không thêm dependency, đổi API contract/backend, tạo audio mới hoặc xóa dữ liệu
người dùng trong lượt đồng bộ này.
