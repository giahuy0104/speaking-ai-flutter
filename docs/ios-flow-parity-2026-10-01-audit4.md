# Kiểm tra Android/iOS bằng ba trợ lý AI — 01-10-2026, lượt bốn

Android đang ổn được lấy làm chuẩn. Ba trợ lý rà riêng học/Từ vựng,
MAIN/Giao tiếp/lifecycle và audio native; người điều phối kiểm tra dịch
offline, Settings, CI và ghép hồi quy. Giữ mọi sửa đổi đã có trong workspace.

## Những khoảng trống đã sửa thêm

| Luồng | Lỗi xác minh | Thay đổi |
| --- | --- | --- |
| Core/Challenge | Partial Apple đến trước start bị mất ở Core; Challenge có transcript nhưng phải chờ cap khi giọng nhỏ | Giữ partial theo generation, dùng bằng chứng nhận giọng để endpoint sau im lặng |
| Core/Review sau MAIN | Start cũ báo lỗi sau khi resume, rồi hủy listener/endpoint của lượt mới | Kiểm quyền sở hữu trước cleanup |
| Challenge mở H20 | Timeout ngoài 8 giây ngắn hơn budget native-ready 9 giây | iOS cho 12 giây, Android giữ 8 giây |
| Học nền | Start hoàn tất muộn có thể bật phiên sau khi tắt voice; start lỗi chặn lần thử sau; re-enable có thể đụng stop chưa xong | Generation, stop tuần tự, re-enable chờ cleanup và reset start khi lỗi; iOS detached không khôi phục |
| Dịch offline iOS | Plugin không đăng ký trên iOS, runtime không inject translator, Settings chỉ chuẩn bị speech | Tích hợp ML Kit native cho iPhone, nối Việt–Anh/Anh–Việt vào Giao tiếp/Thêm từ vựng, tải Wi-Fi sau consent và kiểm lại consent sau các bước chờ |
| Độ lớn lời trợ lý | Native iOS bỏ qua xử lý độ lớn của Android | TTS render cục bộ và clip ngắn được đo theo gated RMS −21 dBFS, sample peak ceiling −1 dBFS, tối đa +28 dB; giữ ownership đến khi phát xong |
| Native interruption | Awaited lời trợ lý có thể hoàn tất như thành công khi bị gián đoạn | Trả lỗi interruption; callback/file của lượt bị hủy không phát vào lượt mới |
| Lời trợ lý qua loa điện thoại | `forcePhoneSpeaker` bị bỏ qua khi H20 vẫn kết nối | TTS/clip tôn trọng route được yêu cầu; cùng policy chờ và giám sát HFP, giữ ngoại lệ graph HFP nền đã được chuẩn bị |
| Build ML Kit | SDK không có arm64 simulator slice; việc bỏ SDK trên toàn iOS làm mất offline | Chỉ simulator dùng adapter unavailable; sau XCTest buộc cài SDK thật và build device release; Swift stub từ chối device build |

Bridge dịch không tự tải model khi dịch, không gửi text sang API thay thế.
English được ML Kit tích hợp sẵn trên iOS; không tạo/download/delete English
RemoteModel. Model tiếng Việt tải qua Wi-Fi theo lựa chọn phụ huynh. Native
callbacks tải model đồng thời trả đúng một lần. Settings phân biệt model dịch
đã sẵn sàng với khả năng offline Apple Speech phụ thuộc thiết bị.

Review chéo phát hiện helper Pods dùng `pod update <tên>` trên checkout sạch
chưa có lockfile; đã sửa sang `pod install` lần đầu, chỉ update khi plugin
đã nằm trong lock. Helper kiểm tra podspec thực tế sau lệnh, không chỉ kiểm tra
biến môi trường. Cả bootstrap và App Store đều compile SDK device trước release.

## Kiểm chứng trên Windows

| Kiểm tra | Kết quả |
| --- | --- |
| Flutter logic/widget test cùng bộ lọc CI, 137 file | **1.357/1.357 đạt** |
| Core/Challenge/Review tập trung | 167/167 đạt; 5 tình huống mới đã tái hiện fail trước sửa |
| Lifecycle học nền | 14/14 đạt |
| Service offline iOS/Android | 9/9 đạt |
| Settings offline iOS | 3/3 đạt: model có sẵn, bật tải Wi-Fi, tắt khi Apple preparation còn pending |
| Python helper Pods + chọn simulator | 8/8 + 5/5 đạt |
| Flutter analyze | Không có issue sau khi ghép toàn bộ thay đổi |
| Kiến trúc và diff whitespace | Đạt |
| Swift/XCTest/SDK device | Đã khai báo trong CI; **chưa chạy trên Windows** |

Log: `.codex_tmp/ios-parity-nongolden-tests-2026-10-01-audit4.log`,
`.codex_tmp/ios-audit4-analyze-final.log`. Không chạy lại hay thay ảnh mẫu ở
lượt này; 5 golden lỗi sẵn ở Home/quyền đã được xác minh trên baseline trong
[báo cáo trước](ios-flow-parity-2026-09-30.md).

## Chưa thể kết luận đồng bộ hoàn toàn

- Cần Codemagic/macOS xác nhận Swift, plugin module, Pods device và XCTest.
- Cần iPhone/H20 đo độ lớn, độ trễ TTS render, interruption và route. Clip dài,
  format không hỗ trợ hoặc decode quá budget vẫn phát bản gốc ở gain 0 dB;
  Android đôi khi có fallback +8 dB chưa đo.
- iOS vẫn dừng khi mất tuyến HFP; Android có phục hồi 5 giây. Chưa sao chép
  recovery vì chưa xác minh cách phục hồi capture graph mà không chuyển mic.
- Apple Speech/chấm cục bộ khác engine Android; wake-word iOS chủ động, học
  nền/khóa màn và nút vật lý H20 vẫn cần chứng cứ thiết bị/firmware.
- 5 hook SFX không có bản gốc trên cả hai nền tảng vẫn là thiếu nội dung chung.
- Mã ở working tree; chưa commit/push/build/upload TestFlight. Chưa có số build
  tester cung cấp để xác nhận bản đang cài đã chứa các sửa đổi.

Nghiệm thu bằng bản iOS từ cùng revision với Android: Core → Challenge →
lựa chọn cuối bài, lần nhận sao đầu tiên, hook, từ vựng ba mục, MAIN/Dừng/
Câu trước/Câu sau/Nghe lại, mất/kết nối lại H20 giữa lời dẫn/ting/ghi âm,
chủ động phát loa điện thoại khi H20 kết nối, tắt voice khi start còn pending,
chuẩn bị model rồi bật Airplane Mode thử dịch hai chiều và Thêm từ vựng.

Tham chiếu API: [Google ML Kit iOS translation](https://developers.google.com/ml-kit/language/translation/ios),
[English built-in model](https://developers.google.com/ml-kit/reference/swift/mlkittranslate/api/reference/Classes/TranslateRemoteModel),
[Apple PCM synthesis](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer/write(_:tobuffercallback:)).
