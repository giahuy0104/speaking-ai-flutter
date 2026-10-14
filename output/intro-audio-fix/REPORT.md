# Đã sửa intro còn dùng TTS — 14/10/2026

Đã sửa 13 intro mở mới được phát hiện trong đợt audit. Luồng mới là MP3 lời dẫn Việt–Anh → MP3 hook mở cảnh → MP3 “Bắt đầu nhé.”. Giữ nguyên hook và không phát thêm intro đầy đủ gây lặp nội dung.

## Thay đổi

- Thêm 13 asset `listening.lesson.<id>.intro_lead.vi.mp3` vào thư mục listening-common đã được khai báo trong pubspec.
- Các file được ghép từ hai đoạn gốc tiếng Việt và tiếng Anh trong cache tạo intro. Trước khi nhập, script tái tạo toàn bộ intro từ ba đoạn và so sánh PCM với MP3 intro hiện có: cả 13 đều trùng chính xác. Không tạo giọng mới hoặc gọi API.
- `LessonIntroScreen` dùng `ListeningAudioKeys.lessonIntroLead` cho phần dẫn trước hook; vẫn giữ cơ chế dự phòng hiện có khi audio không khả dụng.
- Cập nhật manifest listening-common lên v2, text/hash/checksum/kích thước/thời lượng, pack index và gain âm lượng của 13 file.
- Cập nhật generator và source text của index builder để lần tạo lại không làm mất các lời dẫn này. Script offline tái tạo: `python tool/compose_listening_intro_leads.py`, cần cache gốc và ffmpeg/ffprobe.
- Cố định LF cho manifest/index bằng `.gitattributes` để checksum không đổi theo checkout Windows/Unix; chuẩn hóa đường dẫn trong kiểm thử loudness cho Windows. Các manifest khác chỉ chuẩn hóa xuống dòng, không đổi nội dung JSON.

## Kiểm chứng

- Kiểm thử `test/lesson_intro_audio_test.dart` chạy màn hình intro thật và factory audio thật cho 109 bài trên mỗi cấu hình Android/iOS, tổng 218 lượt mở. Cả 218 đều khớp chính xác chuỗi checksum MP3 dự kiến, không gọi TTS. Trong mỗi cấu hình, 13 bài dùng lead → hook → start cue và 96 bài dùng full-intro MP3.
- Kiểm thử guided flow hiện có, bao gồm học tiếp, hook, dự phòng khi audio lỗi và dừng intro, đã pass. Test Animal Names được cập nhật để bắt buộc phát lead MP3 đúng một lần và không đọc TTS tên bài.
- Audit toàn bộ pack index/file/checksum và bộ kiểm thử loudness pass.
- Dart analyzer trên các file Dart liên quan: không có vấn đề. Parser PowerShell và `git diff --check` pass.

Lần chạy đầu có ba lỗi kiểm thử: đối chiếu đường dẫn Windows, checksum manifest do CRLF, và biến override nền tảng của test mới chưa được khôi phục trước khi Flutter kiểm tra invariant. Đã xử lý cả ba và chạy lại nhóm liên quan: 9/9 pass; bộ guided flow 110 test đã pass ở lần đầu. Xem `tests.log`, `tests-rerun.log`, `analyze.log` và `composition-receipts.json`.

Chưa build/cài bản mới lên điện thoại hoặc kiểm tra loa/decoder trên thiết bị thật. Kiểm thử ở đây quan sát lựa chọn MP3/TTS và dữ liệu âm thanh gửi xuống native thông qua mock channel. Chưa commit/push hoặc đồng bộ commit deb55732.
