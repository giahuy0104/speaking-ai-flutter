# HOMI: 19 câu cố định còn thiếu MP3 (19/09/2026)

Đợt này chỉ thêm 19 bản thu tiếng Việt cho các câu cố định đã xuất hiện trong kiểm kê MAIN hiện hành. Không sửa nội dung câu, logic nhận lệnh, bài học, dịch, lưu tiến độ hoặc các gói audio cũ.

- Nguồn câu: `deliverables/audio-runtime-audit-2026-09-19/homi-speech-audit-summary.json`.
- MP3 mới: `assets/audio/MAIN/GAP19/`; manifest riêng: `assets/data/homi_gap19_audio.json`.
- Giọng: ElevenLabs `eleven_v3`, voice `5CVDNcIPiOYgRUQuxXd7`, tiếng Việt. Nguồn tạo ở tốc độ 1.0; FFmpeg `atempo=0.9` đúng một lần; ứng dụng phát ở 1.0x.
- 19 file, tổng 827.135 byte. Đầu vào 735 ký tự; API báo tổng `character-cost` 403 (không phải số tiền). Khóa API được đọc từ tệp ngoài repository, không nằm trong ứng dụng hoặc receipt.
- Công cụ `tool/build_homi_gap19_audio.mjs` tạo tuần tự, không tự retry khi kết quả yêu cầu không rõ. Nguồn và receipt nằm trong `deliverables/homi-gap19-2026-09-19/`, không được bundle vào ứng dụng.

Ứng dụng nạp gói mới qua `createVoicePromptService`, sau ba manifest cũ. Để quay về TTS cho riêng 19 câu, build với `--dart-define=HOMI_GAP19_AUTHORED_AUDIO=false`. Nếu gói thiếu, MP3 lỗi, SHA-256 sai hoặc không phát được, bộ phát chung vẫn fallback về TTS. Các câu động vẫn giữ đường phát cũ.

Kiểm tra đã chạy:

- Cả 19 file giải mã được; SHA-256, duration, tốc độ, receipt và đường dẫn bundle khớp.
- Test của gói mới kiểm tra 19 câu trên ba đường phát (thường, thiết bị được chọn, loa điện thoại), cùng việc giữ MP3 cũ và TTS cho câu động. Chạy cả khi bật và tắt công tắc đều qua.
- 166 test liên quan audio curriculum và voice navigation qua; `flutter analyze` trên các file Dart mới/sửa không có vấn đề.
- Kiểm kê lại tập 2.061 cặp câu/ngôn ngữ hiện hành: 2.061 có audio hợp lệ, 0 còn thiếu ánh xạ; `deliverables/audio-runtime-audit-2026-09-19-after-gap19/homi-speech-audit-summary.json`.

Giới hạn: kiểm kê nhánh bằng kịch bản và đọc mã, không chứng minh mọi câu động hoặc mọi trường hợp trên điện thoại. Chưa nghe duyệt từng file trên thiết bị thật và chưa cài APK mới. Bốn assertion của hai test cũ (`assistant_audio_inventory_test.dart`, `core_audio_main_assistant_audio_prompt_service_test.dart`) đang kỳ vọng manifest/lời nhắc cũ trước thay đổi luồng MAIN; chúng không được sửa trong đợt thêm MP3 này.
