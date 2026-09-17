# HOMI — bổ sung 28 audio ElevenLabs, 16/09/2026

## Đã hoàn thành phần tạo và tích hợp audio

- Tạo mới **28/28 file MP3**, đúng 28 câu/biến thể thiếu đã được duyệt trong lần rà soát.
- Nhà cung cấp **ElevenLabs**, model **`eleven_v3`**; cả 28 câu là tiếng Việt.
- Voice tiếng Việt **`5CVDNcIPiOYgRUQuxXd7`**, tốc độ đầu ra **0.9x**.
- Cấu hình tiếng Anh vẫn giữ **`Nhs7eitvQWFTQBsf0yiT`**, **0.75x**; không tạo thêm câu tiếng Anh ngoài phạm vi.
- Tổng text gửi: **1.306 ký tự**. Có 28 receipt/request ID từ nhà cung cấp, không tự động gọi lại yêu cầu sinh audio.
- 28 file mới: **1.602.839 byte**, tổng thời lượng **98,297 giây**.
- MAIN tăng từ 191 lên **219** audio; CURRICULUM giữ **2.641**; tổng **2.860**.
- Kiểm kê hữu hạn hiện tại: **2.062/2.062 text–locale có audio khớp, 0 còn thiếu**. Không áp dụng con số này cho nội dung phát sinh tự do.

## Cách tạo và gắn

Đã dùng [API Create speech chính thức của ElevenLabs](https://elevenlabs.io/docs/api-reference/text-to-speech/convert). Mỗi câu được gửi riêng, model/voice/language được khai báo rõ. Tốc độ nguồn API được đặt 1.0, sau đó dùng FFmpeg `atempo=0.9` giữ cao độ đúng một lần. Thời lượng đầu ra được kiểm tra so với thời lượng nguồn / 0.9. Khi app phát MP3, không giảm tốc thêm.

Giữ nguyên lời thoại và dấu câu runtime, bao gồm hai câu dùng “Bi cô”. Không tự đổi tên/xưng hô trong code. Mỗi file được kiểm tra giải mã MP3, SHA-256, receipt, thời lượng rồi mới khai báo trong pubspec và bật manifest. ID mới: `GAP28-001`…`GAP28-028`.

API key chỉ được đọc từ file bên ngoài dự án, gửi tới endpoint ElevenLabs; không đưa vào manifest, receipt hoặc mã ứng dụng.

## Kiểm chứng

- **75 test đạt**, gồm kiểm kê MAIN/CURRICULUM, MAIN flow, từ vựng, audio wrapper và hai test riêng cho 28 câu.
- Test riêng dùng asset bundle thật xác nhận đủ 28 file và receipt đúng model/voice/speed/text.
- **84 lượt gọi wrapper**: 28 câu × 3 đường phát (thông thường, thiết bị đã chọn, loa điện thoại) đều dùng đúng bytes audio; không gọi TTS trong các ca này. Câu chưa có trong kho vẫn fallback bình thường.
- Phân tích tĩnh test mới: không có lỗi/cảnh báo.
- Kiểm tra lại toàn bộ 2.860 audio trong kho: không có lỗi checksum/file/giới hạn runtime; 1.311 liên kết giáo trình trực tiếp vẫn hợp lệ.
- Dấu vân tay toàn bộ `lib`, giáo trình, manifest CURRICULUM và từng entry MAIN cũ không đổi so với trước đợt bổ sung.
- Công cụ làm mới danh mục assistant đã được bổ sung bảo toàn các entry của đợt này, tránh lần quét literal sau làm mất các câu có số biến thể.
- Kiểm tra vòng đời audio web bằng mock: completion, stop, callback cũ, lỗi autoplay và giải phóng Blob URL đều đạt; chưa build lại bản web trong đợt này.

## APK mới

Build Android debug thành công: [app-debug.apk](D:/Code/HuaMei/App_noi/flutter/18_16th9/speaking-ai-flutter/build/app/outputs/flutter-apk/app-debug.apk), **454.591.809 byte**.

Kiểm tra trực tiếp gói APK sau build: đủ **2.860/2.860 audio** khớp checksum, đủ **28/28 câu mới** và 28 entry được bật trong manifest đóng gói. Quét 3.768 file giải nén trong APK không tìm thấy API key; không có receipt sinh audio bị đóng gói. [Kết quả kiểm tra APK](D:/Code/HuaMei/App_noi/flutter/18_16th9/speaking-ai-flutter/deliverables/homi-gap28-apk-verification.json).

Build có cảnh báo phiên bản SDK XML của bộ công cụ Android, nhưng kết thúc thành công; không thay SDK hoặc cấu hình build ngoài phạm vi yêu cầu.

Đây là kiểm thử tự động và đối chiếu dữ liệu, không phải xác nhận đã nghe kiểm định từng câu trên thiết bị thật.

## Phạm vi không thay đổi

Không sửa điều khiển MAIN/BLE, nhận giọng, chấm điểm, logic học, tiến độ, nhạc hay giọng ghi âm của trẻ. Không sửa lựa chọn clip intro/resume. Câu dịch tự do và dữ liệu ba mẹ thêm vẫn giữ đường phát hiện có. Không tắt TTS dự phòng.

Việc cập nhật assets trong source/APK không tự cập nhật app đã cài. Chưa cài bản mới lên điện thoại và chưa build iOS trên Windows.

## Tệp bàn giao

- [Manifest MAIN](D:/Code/HuaMei/App_noi/flutter/18_16th9/speaking-ai-flutter/assets/data/main_assistant_audio.json).
- [Danh sách 28 câu và baseline](D:/Code/HuaMei/App_noi/flutter/18_16th9/speaking-ai-flutter/deliverables/homi-gap28-audio-plan.json).
- [Kết quả tạo, request ID, checksum](D:/Code/HuaMei/App_noi/flutter/18_16th9/speaking-ai-flutter/deliverables/homi-gap28-generation-result.json).
- [Danh sách câu cập nhật](D:/Code/HuaMei/App_noi/flutter/18_16th9/speaking-ai-flutter/deliverables/homi-speech-inventory.csv).
- [Test 28 câu](D:/Code/HuaMei/App_noi/flutter/18_16th9/speaking-ai-flutter/test/homi_gap28_audio_test.dart).

Nguồn ElevenLabs chưa đổi tốc độ và receipt nằm trong `deliverables/main_assistant_audio_sources/`; chỉ MP3 đầu ra được khai báo đóng gói, không đóng gói các nguồn/receipt này.

Kiểm tra lại mà không dùng API:

```powershell
node tool/fill_homi_gap28_audio.mjs --verify
flutter test test/homi_gap28_audio_test.dart
node tool/audit_homi_audio.mjs
```

`--generate` chỉ dành cho tiếp tục đợt này nếu cần; file đã có được xác minh và tái sử dụng. Yêu cầu từng chạy nhưng không chắc kết quả sẽ bị chặn thay vì tự tạo lại. Không chạy lại `--prepare` cho đợt đã được đóng danh sách.
