# Audio bài học ElevenLabs — 2026-09-16

## Phạm vi đã tích hợp

- 109 bài học, 50 chủ đề, 5 nhóm tuổi trong catalog hiện tại.
- 601 câu mẫu, đủ 1.202 audio Anh–Việt; 109 liên kết audio giới thiệu.
- Câu hỏi thử thách, đáp án, mission, role-play, hook, micro-objective và các biến thể hữu hạn của lời giới thiệu/học tiếp/học lại/tiến độ theo bài hiện tại.
- Đối chiếu cả manifest v4 và catalog chạy thực tế: catalog có thêm 16 câu hỏi khác nhau không nằm trong manifest v4 cũ; đã bổ sung audio cho chúng.
- 5 bài hát giữ nguyên liên kết bản nhạc có sẵn, không chuyển tên bài hát thành giọng đọc.
- 12 định nghĩa có tham số trong manifest nguồn không được đọc nguyên văn ký hiệu template. Các biến thể cụ thể thuộc catalog hiện tại được lập danh sách riêng.

Inventory cuối cùng có 2.649 cặp nội dung/ngôn ngữ: 8 dùng lại audio MAIN và 2.641 file trong `assets/audio/CURRICULUM/` (163.526.940 byte, khoảng 167 phút). Cộng với 191 file MAIN của đợt trước, hai manifest có 2.832 file.

Trong 2.641 file bài học: 2.198 được tái sử dụng từ bộ ElevenLabs tương thích có sẵn; 443 được tạo/ghép thêm. Có 297 yêu cầu tạo đoạn âm thanh mới, không phải 443 yêu cầu: các đoạn trùng nhau được tái sử dụng. Tổng văn bản các yêu cầu mới là 4.692 ký tự; đây không phải cam kết về đơn vị tính phí của nhà cung cấp.

## Giọng và tốc độ

| Ngôn ngữ | Voice ID | Tốc độ |
| --- | --- | --- |
| Anh | `Nhs7eitvQWFTQBsf0yiT` | 0,75x |
| Việt | `5CVDNcIPiOYgRUQuxXd7` | 0,9x |

Model `eleven_v3`. Tốc độ được xử lý một lần bằng FFmpeg `atempo`, giữ cao độ; app phát file ở 1x. Các đoạn Anh–Việt ghép sử dụng giọng tương ứng. Bộ tái sử dụng phải khai báo cùng model, voice, tốc độ và phương pháp atempo; nội dung được đối chiếu chính xác bằng văn bản/ngôn ngữ. Đây là kiểm tra metadata và tính toàn vẹn, không phải chứng nhận đã nghe duyệt từng bản thu.

## Cách gắn và bảo vệ tính năng khác

- Catalog chỉ đổi trường URL audio và nhãn `audioProvider`; mã bài/câu, nội dung, thứ tự, luật chấm và bài hát không đổi. Không di chuyển hoặc xóa tiến độ học.
- `curriculum_audio.json` là manifest bổ sung của dịch vụ audio hiện hữu. Tìm chính xác nội dung/ngôn ngữ; thiếu/lỗi/không khớp thì dùng TTS dự phòng.
- Audio vẫn đi qua cơ chế điều phối lượt phát sẵn có. Dừng, rời màn hình hoặc chuyển MAIN hủy lượt cũ; không phát lại TTS của lượt đã hủy.
- Thử thách lấy thời hạn chờ theo độ dài bản thu để không bật micro sau mốc cố định 10 giây khi audio chưa xong. Không thay đổi quy tắc nhận đáp án/chấm điểm.
- Kiểm tra SHA-256 trước phát lời dẫn; file phải dưới 2 MiB và 45 giây. Mỗi MP3 được giải mã kiểm tra trước khi kích hoạt lần đầu. Khi chạy lại batch, bytes phải khớp receipt đã xác minh.
- Manifest runtime và APK không cần API key. Key nằm ngoài repository, chỉ gửi đến API ElevenLabs khi tạo bản thu. Không đưa raw source hoặc receipt vào assets được đóng gói.

## Những câu dịch phát sinh: chưa bật ElevenLabs động

Các câu dịch mới, không biết trước khi người dùng nói, **chưa được chuyển sang ElevenLabs trong đợt này**. Chức năng dịch và cơ chế TTS hiện tại được giữ nguyên. Không nhúng API key vào Flutter/APK/Web.

App đang cấu hình URL backend Railway. Có nhiều checkout backend trên máy; chưa xác nhận checkout nào tương ứng production và chưa triển khai thay đổi server. Cần xác nhận backend cùng hạn mức tạo audio tự động trước khi bật phần này.

Hướng triển khai tiếp theo: backend nhận nội dung dịch, kiểm tra quyền/hạn mức, tra cache theo nội dung + ngôn ngữ + model + voice + tốc độ; chỉ tạo khi thiếu, lưu file bền vững và trả URL cho app. Chặn yêu cầu trùng đang chạy; giữ TTS dự phòng khi hết hạn mức/lỗi; không tạo lại cache hàng loạt qua luồng warmup hiện có. Không tự mua thêm credit hoặc nâng gói.

## Tái chạy an toàn

```powershell
# Chỉ kiểm kê, không đọc key và không gọi tạo audio.
node tool/prepare_curriculum_audio.mjs

# Cập nhật plan khi batch không chạy.
node tool/prepare_curriculum_audio.mjs --write
node tool/build_curriculum_audio.mjs

# Chỉ chạy sau khi đã xem danh sách thiếu; có thể tiêu hao API.
node tool/build_curriculum_audio.mjs --apply --api-key-file "C:/path-outside-repo/elevenlabs-key.txt"
```

Plan: `deliverables/curriculum_audio_plan.json`. Receipt: `deliverables/curriculum_audio_receipts/`. Nguồn: `deliverables/curriculum_audio_sources/`. Công cụ import hiện dùng thư mục bộ thu có sẵn `D:/Code/HuaMei/App_noi/Tao_audio_15th9`; sửa cấu hình đường dẫn khi chuyển máy.

Batch tuần tự, ghi receipt/checksum rồi kích hoạt từng file. Không tự retry yêu cầu tính phí khi kết quả không chắc chắn; kiểm tra lịch sử nhà cung cấp trước khi thử lại. Retry rename của file manifest chỉ là thao tác đĩa cục bộ.

## Tắt riêng gói bài học

Build với `--dart-define=HOMI_CURRICULUM_AUTHORED_AUDIO=false` sẽ bỏ manifest bổ sung và các URI trực tiếp thuộc thư mục CURRICULUM, để dùng luồng dự phòng. MAIN vẫn hoạt động. Không cần reset tiến độ.

Thay đổi bundle không tự cập nhật APK đã cài hoặc web đã triển khai. Chưa cài lên thiết bị, chưa deploy production. Gói offline làm dung lượng cài đặt tăng; cần nghe kiểm tra trên điện thoại/Bluetooth và duyệt chất lượng trước phát hành.

## Xác minh

- 690 kiểm thử đạt: core audio, kiểm kê MAIN/bài học, điều hướng giọng nói, bài học, từ vựng và hội thoại/dịch.
- Kiểm thử riêng với `HOMI_CURRICULUM_AUTHORED_AUDIO=false` đạt: URI bài học bị tắt và câu thử thách quay về TTS.
- Phân tích toàn bộ `lib` cùng các test audio/bài học được bổ sung hoặc chỉnh trong đợt này: không có lỗi/cảnh báo.
- Catalog sau khi bỏ riêng các trường audio khớp hoàn toàn với bản trước thay đổi.
- Đối chiếu đủ text/locale, nội dung, receipt và SHA-256 của mọi file đóng gói; kiểm thử lời thử thách dài chờ phát xong mới mở micro đạt.
- Bài kiểm tra ảnh chuẩn giữ nguyên ảnh đã duyệt; media fake được giữ ở trạng thái đang phát để ảnh không phụ thuộc việc catalog dùng URL local hay TTS.
- Browser lifecycle test đạt: hoàn tất/dừng/lượt cũ/lỗi autoplay và giải phóng Blob URL.
- Android debug build thành công: `build/app/outputs/flutter-apk/app-debug.apk`, 444.248.026 byte.
- Audit APK: 2.832 audio đúng SHA-256; quét 3.740 mục không rỗng, không có API key đã cung cấp hoặc file nguồn/receipt/script tạo audio.
- Web production build thành công: `build/web`. Audit 2.832 audio đúng SHA-256 và 3.201 file không chứa key đã cung cấp hoặc nguồn/receipt audio.
- Quét 8.136 file được git theo dõi hoặc không bị ignore trong workspace: không có bản sao API key đã cung cấp.
- Công cụ kiểm kê báo 2.649/2.649 output đã tồn tại, không còn mục cần tạo; resume vẫn xác minh receipt/hash, không chỉ kiểm tra tên file.

Không có xác nhận biên dịch iOS trên máy Windows. Kiểm thử tự động và kiểm tra decode/hash không thay thế việc nghe duyệt hoặc thử micro/Bluetooth trên thiết bị thật.
