# Kiểm tra và sửa luồng Chủ đề — 18/09/2026

## Sáu lỗi và thay đổi

| Lỗi báo cáo | Thay đổi đã thực hiện |
| --- | --- |
| 1. Lời dẫn vào bài chưa đầy đủ | V4 chọn toàn bộ lời dẫn khớp nội dung hiển thị và đợi đọc xong trước khi vào bài. Khi có audio đầy đủ trong manifest, phát nguyên đoạn; khi không có, giữ cách đọc tên tiếng Anh bằng giọng tiếng Anh. |
| 2. Mic không thu được bản ghi | Android chọn đúng đầu vào H20 hoặc mic điện thoại theo thiết bị đang chọn. Khi mất kết nối, đồng bộ trạng thái ghi âm giữa dịch vụ và màn hình, hiển thị lỗi kết nối cụ thể và cho thử lại. Thả nút khi mic còn đang mở sẽ hủy lượt chờ, tránh khởi động bản ghi ngầm từ callback đến muộn. |
| 3. MAIN lặp câu điều hướng cũ | Dùng câu trong hợp đồng điều hướng đã cập nhật, khớp bản thu hiện có. Khi nhận tiếng vọng hoặc câu chưa rõ, giữ lời hướng dẫn đúng ngữ cảnh hiện tại. |
| 4. Loa chuyển qua lại điện thoại/Bluetooth | Giữ route H20 trong lúc ghi âm và chuyển sang chấm điểm/phản hồi trên Android; thao tác chỉ dừng phát không giải phóng route của mic đang hoạt động. Khi H20 mất kết nối, dừng lượt và báo lỗi. |
| 5. Sai lần đầu còn đọc nghĩa Việt | Luồng thử lại phát lời dẫn → mẫu tiếng Anh → mở mic. Không phát nghĩa Việt hoặc thêm lời mời tiếng Việt phía sau. Nút nghe mẫu và luồng học thông thường vẫn giữ hành vi riêng. |
| 6. Câu đầu/cuối nhắc lại tên bài | Tiếp tục câu qua MAIN bắt đầu trực tiếp luồng mẫu → lời mời → mic; bỏ câu nhắc tên bài. Lùi tại câu đầu cũng vào thẳng luồng mẫu. |

## Bằng chứng kiểm tra

- **212 kiểm thử tập trung đạt**, chạy nối tiếp để tránh nhiễu giữa các ca: [log kiểm thử](D:/Code/HuaMei/App_noi/flutter/20_17th9_v2/speaking-ai-flutter/output/qa-topic-fixes-20260918-focused-serial.log). Bao phủ lời dẫn đầy đủ, giọng đọc tên bài tiếng Anh, điều hướng, thứ tự mẫu/mic, thử lại, mất route và thả nút khi recorder còn đang mở.
- Phân tích Dart trên **9 tệp mã nguồn/kiểm thử thay đổi: không có vấn đề**. Kiểm tra ranh giới kiến trúc: đạt.
- Lượt chạy toàn bộ ghi nhận **922 đạt, 13 lỗi**, sau đó bị dừng do ca `system Back cannot leave an unfinished Today session` bị treo. Đây không phải kết quả toàn bộ suite đạt: [log toàn bộ](D:/Code/HuaMei/App_noi/flutter/20_17th9_v2/speaking-ai-flutter/output/qa-topic-fixes-20260918-tests.log).
- Đối chiếu bản HEAD trước sửa tái hiện **đúng 13 lỗi và cùng ca Today bị treo**; các lỗi golden có cùng số lượng/tỷ lệ pixel khác biệt. Xem [báo cáo baseline](D:/Code/HuaMei/App_noi/flutter/20_17th9_v2/speaking-ai-flutter/output/qa-baseline-20260918-summary.md). Các kiểm tra hiện có chưa cho thấy hồi quy mới từ bản sửa này; vẫn cần xác nhận âm thanh và mic trên thiết bị thật.

## Phạm vi giữ nguyên

Cấu hình production và pháp lý hiện có được giữ nguyên. Không sửa bộ chấm điểm offline native, nội dung giáo trình, dữ liệu học tập, hoặc logic nghiệp vụ ngoài phạm vi trên. Không cập nhật golden để che các sai khác có sẵn.

## Thiết bị và APK cuối

- Build release hoàn tất với `dart_defines.production.json`; cấu hình pháp lý hiện có được đóng gói.
- APK: `output/apk/HOMI-1.0.8-10-topic-mic-final-20260918.apk`.
- SHA-256: `5836C28020186CE9857250B69F1FF5E7F2B3FB64ACCBDB05AC35485EA1E70117`.
- Cài đè bằng `adb install -r` lên thiết bị `23054RA19C`: thành công. `ceDataInode=1244129` không đổi trước/sau, xác nhận dữ liệu ứng dụng được giữ lại.
- App khởi động lại với PID `17664`, H20 được nhận; không có lỗi crash trong kiểm tra khởi động.
- Kiểm tra thật tạo bản ghi 16 kHz hai kênh từ driver và bản cuối đã chuẩn hóa thành một kênh trước khi phát/chấm: `394284 -> 197164` byte. Màn hình vẫn hiển thị bản ghi 6 giây.
- APK hiện được ký bằng Android debug certificate vì workspace chưa có `android/key.properties`/keystore phát hành. Bản này phù hợp cài kiểm thử trên thiết bị; chưa phải chữ ký để đưa lên kho ứng dụng.
