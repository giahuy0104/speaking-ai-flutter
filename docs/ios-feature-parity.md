# Đồng bộ nội dung và luồng iOS — cập nhật 2026-10-01

Đợt rà soát theo phản hồi tester ngày 30-09 đã sửa phần bàn giao ghi âm/âm thanh
iOS, Challenge, callback điều hướng cũ và khôi phục 13 hook bị bỏ khi chuyển
thư viện audio. Xem [báo cáo thay đổi và ca nghiệm thu](ios-flow-parity-2026-09-30.md).
Lượt rà tiếp theo bổ sung dịch offline iOS, đồng bộ độ lớn lời trợ lý và sửa
race của Core/Challenge/Review/học nền. Xem [báo cáo lượt bốn](ios-flow-parity-2026-10-01-audit4.md).

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
| Dịch | Apple Speech + dịch văn bản/API; thêm ML Kit Việt–Anh/Anh–Việt cục bộ cho iPhone khi đã chuẩn bị model | Test iOS dịch/Thêm từ vựng offline không gọi API, tải Wi-Fi, trạng thái Settings và hủy tải mới sau khi tắt; native cần build/nghiệm thu |
| Độ lớn lời trợ lý | TTS và clip ngắn được đo RMS/peak rồi phát PCM cục bộ theo cùng target Android | XCTest meter/WAV/cancellation đã thêm, chưa chạy trên Windows; clip không đo được vẫn phát ở gain 0 dB |

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

Kiểm tra tại workspace Windows ngày 2026-10-01, lượt bốn: **1.357/1.357 test chức năng
không dùng ảnh mẫu đạt**, `flutter analyze --no-pub` sạch; kiểm tra ranh giới
kiến trúc và `git diff --check` đạt. Hai test inventory từng chặn Codemagic
vẫn được chạy. Các file có golden cho kết quả 50 đạt, 5 baseline Home/quyền
onboarding lệch ảnh mẫu; xem báo cáo để biết phạm vi và log. Chưa chạy
Swift/XCTest, simulator hoặc iPhone/H20 thật trong lượt này.

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

Lượt bốn thêm dependency native `GoogleMLKit/Translate ~> 9.0.0` trên iPhone;
không đổi API contract/backend, tạo audio nội dung mới hoặc xóa dữ liệu người dùng.

### Simulator trên Mac Apple Silicon

ML Kit Translate có binary cho iPhone arm64 nhưng không có slice arm64
simulator. Plugin iOS nay được đăng ký với hai chế độ build rõ ràng: bản iPhone
link SDK thật; simulator trả lỗi unavailable cho dịch/tải model. Không chỉnh
nhãn binary device thành simulator. `prepare_ios_translation_pods.py` cài Pods
trên checkout sạch, buộc cập nhật podspec khi đổi SDK và xác nhận dependency
thực tế. Stub Swift không biên dịch được cho thiết bị/IPA.

CI build và chạy RunnerTests trên iPhone simulator arm64 từ danh sách
destination hợp lệ của Xcode; không bỏ qua test khi thiếu simulator. Danh sách
destination được lưu trong artifact `build/ios/test-results/destinations.log`.
Sau simulator/XCTest, cả hai workflow cài lại Pods device rồi build release
unsigned để kiểm tra SDK thật; App Store workflow xác nhận lại trước IPA.

Kiểm tra cục bộ: `python -B -m unittest discover -s tool -p
test_select_ios_test_simulator.py` (5 ca) và `test_prepare_ios_translation_pods.py`
(8 ca). Cần Codemagic/macOS để xác nhận build và
RunnerTests thực tế; kiểm tra trên Windows không chứng minh linker đã qua.
