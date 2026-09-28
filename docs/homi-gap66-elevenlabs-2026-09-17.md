# HOMI — bổ sung 66 audio cố định bằng Eleven v3

## Phạm vi và kết quả

Đã tạo mới 66 câu tiếng Việt còn thiếu từ báo cáo kiểm tra runtime ngày 17/09/2026. Không tạo lại những file đã có. Không sửa nội dung câu, quyết định điều hướng, logic học, ghi âm, chấm điểm hoặc lưu tiến độ.

| Cấu hình | Giá trị |
|---|---|
| Model | `eleven_v3` |
| Voice Việt | `5CVDNcIPiOYgRUQuxXd7` |
| Tốc độ Việt | `0.9x` |
| Voice Anh giữ nguyên | `Nhs7eitvQWFTQBsf0yiT` |
| Tốc độ Anh giữ nguyên | `0.75x` |
| Số file mới | 66, tất cả là tiếng Việt |
| Tổng dung lượng MP3 | 5.565.916 byte |
| Thời lượng từng file | 0,968–8,519 giây |
| Số ký tự đầu vào | 4.648 |
| Tổng `character-cost` do API trả về | 2.557; không phải giá tiền |

Nguồn được tạo ở tốc độ trung tính `voice_settings.speed=1.0`. Công cụ riêng áp dụng `ffmpeg atempo=0.9` một lần, giữ cao độ. Ứng dụng phát file hoàn chỉnh ở tốc độ bình thường, không giảm thêm lần thứ hai. Mỗi file có receipt ghi request, voice, model, tốc độ, duration, SHA-256 và request ID.

## Tách tạo audio khỏi ứng dụng

- Công cụ: `tool/build_homi_gap66_audio.mjs`; không được import từ Dart.
- Đọc API key trực tiếp từ file ngoài repository. Không sao chép key vào source, manifest, receipt hoặc APK.
- Chỉ gửi những câu cố định trong plan sang ElevenLabs; không gửi bản ghi, tiến độ hoặc dữ liệu cá nhân của người dùng.
- Plan, audio nguồn, receipt và audio staging nằm trong `deliverables/homi-gap66-2026-09-17/`.
- Lệnh `generate` không sửa `assets/` hoặc `lib/`. Chỉ `install --group ...` mới sao chép MP3 đã kiểm chứng và kích hoạt đúng nhóm trong manifest.
- App chỉ nhận `assets/data/homi_gap66_audio.json` và MP3 trong `assets/audio/MAIN/GAP66/`; không gọi ElevenLabs lúc chạy.
- File mới được bundle trong APK, không cần tải Cloudinary để phát 66 câu này. Các audio cũ giữ nguyên nguồn phát.
- Mỗi request trả phí chạy tuần tự. Nếu một request không rõ kết quả, công cụ dừng và giữ ledger; không tự retry gây tính phí trùng.

API được dùng theo [tài liệu Create speech chính thức của ElevenLabs](https://elevenlabs.io/docs/api-reference/text-to-speech/convert): gửi văn bản và cấu hình model/voice tới endpoint tạo speech; đầu ra được lưu riêng trước khi tích hợp.

## 7 nhóm rollout và rollback

Tất cả nhóm đã được tích hợp lần lượt và bật mặc định trong mã nguồn mới. Đây là **công tắc khi build**, không phải nút bật/tắt trong giao diện ứng dụng.

| Nhóm | Số câu | `--dart-define` để tắt riêng |
|---|---:|---|
| Chọn Level / Chủ đề | 5 | `HOMI_GAP66_LEVEL_SELECTION=false` |
| Học lại Chủ đề đã hoàn thành | 10 | `HOMI_GAP66_TOPIC_REPLAY=false` |
| Không hiểu khi chọn học lại Chủ đề | 10 | `HOMI_GAP66_TOPIC_REPLAY_RECOVERY=false` |
| MAIN theo màn hình | 4 | `HOMI_GAP66_ACTIVE_SCREEN=false` |
| Phản hồi không hiểu điều hướng | 7 | `HOMI_GAP66_NAVIGATION_RECOVERY=false` |
| Phản hồi không hiểu trong Từ vựng | 14 | `HOMI_GAP66_VOCABULARY_RECOVERY=false` |
| Phản hồi không hiểu khi hoàn thành bài/chủ đề/level | 16 | `HOMI_GAP66_COMPLETION_RECOVERY=false` |

Tắt toàn bộ **gói mới**, giữ nguyên các gói cũ:

```powershell
flutter build apk --release --dart-define-from-file=dart_defines.production.json --dart-define=HOMI_GAP66_AUTHORED_AUDIO=false
```

Ví dụ chỉ tắt nhóm chọn Level/Chủ đề:

```powershell
flutter build apk --release --dart-define-from-file=dart_defines.production.json --dart-define=HOMI_GAP66_LEVEL_SELECTION=false
```

`HOMI_ASSISTANT_AUTHORED_AUDIO=false` là công tắc có sẵn để tắt toàn bộ authored lookup trong voice prompt service. Không đồng nghĩa vô hiệu mọi URI audio trực tiếp của chương trình học; các công tắc chương trình học cũ vẫn giữ nguyên.

Khi nhóm bị tắt, thiếu manifest/file, checksum sai, không giải mã/phát được hoặc timeout, wrapper gọi TTS cũ với nguyên văn câu và locale. Không sửa bộ phân giải câu để bỏ dấu câu hoặc thay lời nhắc; vì vậy quyết định học và nhận dạng lệnh không thay đổi.

## Kiểm chứng

- 66 file giải mã được bằng FFmpeg, khớp SHA-256 và receipt; duration sau xử lý khớp source duration / 0,9 trong sai số cho phép của MP3.
- Không trùng ánh xạ câu/locale với MAIN hoặc CURRICULUM đã có.
- Chạy resolver thật của Flutter với I/O native/CDN giả lập: **2.329 câu × 3 đường phát = 6.987 lượt, 0 fallback TTS** trong điều kiện tài nguyên tốt. Bằng chứng: `deliverables/homi-gap66-2026-09-17/resolver-execution.json`.
- Kiểm kê nội dung hiện tại: **2.109/2.109 cặp câu/locale** trong tập kịch bản có audio; danh sách thiếu từ 66 xuống 0. Không khẳng định mọi nhánh app đã được kiểm chứng trên điện thoại.
- Test mới kiểm tra file bundle, 198 lượt cho riêng 66 câu trên ba đường phát, rollback độc lập từng nhóm, manifest/file bị thiếu, file hỏng, playback lỗi và câu động không có trong kho.
- **9/9 lượt build-time test pass** cho công tắc toàn gói, công tắc toàn bộ authored prompts và 7 công tắc nhóm; xem `switch-*.log`.
- Hash **195 file nguồn/dữ liệu bảo vệ** không thay đổi so với trước khi tạo audio, gồm logic học, thu âm, chấm điểm, tiến độ, MAIN/CURRICULUM cũ và nội dung bài học. Phần production thay đổi chỉ ở cấu hình chọn nguồn audio, manifest mới và đăng ký assets.
- Lượt regression song song ban đầu: 264 pass, 1 fail ở test `two silent active-module windows dispatch STOP rather than resume`. Test này dùng fake voice service và chờ thời gian thực 120 ms; không đi qua factory mới. Giữ nguyên log gốc; kết quả chạy lại tuần tự được ghi riêng, không sửa logic để làm test pass.
- Chạy lại nguyên bộ regression chọn lọc với `--concurrency=1`: **265/265 test pass** (`regression-sequential.log`). Không thay đổi test điều hướng có timer. Analyze ba file Dart mới/thay đổi: không có lỗi/cảnh báo.

Đây là xác minh metadata, giải mã, đóng gói và đường phát; không thay thế việc nghe duyệt phát âm từng file hoặc chạy toàn bộ kịch bản trên thiết bị H20. Lượt này không tự cài đè ứng dụng trên điện thoại.

## APK release đã build và kiểm tra

- Đường dẫn: `build/app/outputs/flutter-apk/app-release.apk`.
- Package: `com.innotrik.aispeaking`, version `1.0.8`, versionCode `2012`.
- Build bằng `--release --build-number=2012 --dart-define-from-file=dart_defines.production.json`; giữ URL backend thật và các URL/chính sách đã cấu hình.
- Build thành công; APK khoảng 154,4 MB, gói mới thêm khoảng 5,6 MB MP3.
- Đọc trực tiếp ZIP APK: đủ 66 file, 66 checksum khớp; không có artifact staging, receipt hoặc tên file API key.
- APK SHA-256: `ec6d53ee30dfca4ab5a4faf789e118ed60331a1b8387e612db2017d21d77c421`.
- Bằng chứng: `deliverables/homi-gap66-2026-09-17/apk-verification.json`, `build-release.log`.
- Kiểm tra lại bằng `./tool/verify_homi_gap66_apk.ps1`.
- Chưa cài APK mới lên điện thoại trong lượt này; bản đang dùng không bị thay đổi.

## Cách chạy lại công cụ

Plan đã đóng băng nên không chạy `prepare` lần nữa. Kiểm tra không tốn API:

```powershell
node tool/build_homi_gap66_audio.mjs verify
```

Tạo phần staging còn thiếu (file có receipt hợp lệ được tái sử dụng, không gọi API lại):

```powershell
node tool/build_homi_gap66_audio.mjs generate --api-key-file C:/Users/DELL/Documents/api_key_elevanlabs.txt
```

Tích hợp một nhóm đã tạo xong:

```powershell
node tool/build_homi_gap66_audio.mjs install --group gap66-level-selection
```

Các nhóm dùng ID như `gap66-active-screen`, `gap66-topic-replay`, `gap66-topic-replay-recovery`, `gap66-navigation-recovery`, `gap66-vocabulary-recovery`, `gap66-completion-recovery`.

## Những phần vẫn giữ TTS theo thiết kế

- Dịch offline và nội dung phụ huynh nhập là văn bản động, không thể tạo trước đầy đủ trong một kho 66 câu.
- Audio dịch online/lịch sử vẫn do backend hoặc cache hiện tại cung cấp; gói này không đổi provider backend.
- Fallback TTS khi tắt gói hoặc tài nguyên lỗi vẫn được giữ theo yêu cầu. Không quảng bá ứng dụng là hoàn toàn không có TTS.
- Các luồng compatibility cũ không được xác lập là luồng hiện tại vẫn được ghi riêng trong audit, không âm thầm tạo thêm hàng trăm file hoặc phát sinh chi phí ngoài gói này.
