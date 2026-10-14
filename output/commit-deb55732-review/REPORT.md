# Đánh giá đồng bộ commit deb55732

**Kết luận: có thể tích hợp phần cập nhật audio, nhưng chưa phù hợp để merge/cherry-pick nguyên trạng.** Chỉ thực hiện kiểm tra và mô phỏng bằng Git objects; chưa đổi nhánh, merge, cherry-pick, commit hay push vào nhánh làm việc.

Commit: `deb55732ad886c42aa83d0477f24edbfe15c96a1` — `add audio v1`, ngày 13/10/2026. Nhánh hiện tại: `add-audio-android-13th10`, HEAD `a494c9e535dea79e82dd500d3c737388b84c8018`.

## Quan hệ lịch sử và xung đột

- Hai phía phân nhánh từ `ee32bf5218334de24bd0e3d72129498f261334d6`. HEAD có 50 commit riêng, phía commit được hỏi có 63 commit riêng. Không thể fast-forward.
- Mô phỏng merge toàn bộ lịch sử vào HEAD: **17 file xung đột**, gồm Android BLE, app, MAIN, màn hình học và tests.
- Mô phỏng áp dụng riêng commit với parent của commit làm merge base: **4 file xung đột trên HEAD đã commit** — `assistant_core_audio.json`, `audio_pack_index.json`, `listening_common_audio.json`, `topic_content_identity_test.dart` (modify/delete).
- Workspace còn thay đổi chưa commit của việc bỏ Level và ba audio vừa nhập. Có 5 file trùng phạm vi commit. Ghép văn bản ba chiều riêng từng file với nội dung đang sửa cho thấy `audio_pack_index.json` xung đột 2 vùng. Đây chỉ là kiểm tra từng file, không thay thế một lần tích hợp toàn bộ và chạy test.

## Nội dung và tính toàn vẹn

- Commit thay 821 file: cập nhật **795 MP3**, xóa **6 MP3**, sửa manifest/tests và thêm biên nhận import. Riêng commit này không sửa `lib/`, `android/`, `ios/`.
- Đã đọc trực tiếp Git blobs: **17 manifest, 4.011 entry, 2.877 file audio duy nhất**. Không thiếu file, không sai SHA-256/size theo manifest; checksum manifest trong pack index cũng khớp.
- `listening_lessons.json` giống workspace khi chuẩn hóa CRLF/LF; nội dung bài học không bị đổi bởi commit được kiểm tra.
- Ba file người dùng vừa cung cấp có cùng SHA-256 với các bản được giữ trên nhánh nguồn; không cần nhập lại chúng.

## Những điểm phải giữ hoặc điều chỉnh

1. **Giữ audio hoàn thành khóa học.** Commit xóa `listening.milestone.course.vi` và MP3 tương ứng, đồng thời thêm test yêu cầu TTS cho key này. App hiện tại vẫn gọi key đó khi hoàn thành khóa; nhận nguyên thay đổi sẽ làm mất bản thu ở bước này. `listening.completion.lesson.2_to_1.vi` cũng bị xóa dù đang được manifest hiện tại bật; cần giữ hoặc rà soát nhánh tương thích trước khi loại bỏ. Bốn file xóa còn lại là Level và hiện đã tắt.

2. **Giữ key và câu chữ đã đồng bộ ở workspace.** Nhánh nguồn dùng `assistant.topic.choose_course_relearn.vi`, workspace dùng `assistant.topic.course_relearn.vi`. Câu choose10 trong manifest nguồn có thêm chữ “muốn”, còn bản thu thực tế và câu app hiện tại là “Bạn chọn Chủ đề số mấy?”. Sao chép nguyên manifest nguồn có thể làm kiểm tra text/key không khớp và rơi về TTS.

3. **Giữ trạng thái tắt audio Level.** Snapshot nguồn còn 6 entry GAP66 nhắc Level được bật. Delta riêng commit không nhất thiết bật lại chúng khi ghép đúng; tuy nhiên không được thay nguyên manifest lên bản đã bỏ Level.

4. **Tính lại cân bằng âm lượng.** Cả 795 file audio thay đổi đều có gain theo đường dẫn trong bảng hiện tại; commit không cập nhật `audio_loudness.json`. Kiểm tra mẫu với cùng chính sách đo cho thấy gain cần thay đổi, ví dụ lời menu MAIN lệch 1,14 dB và một prompt Challenge lệch 1,41 dB. Bảng theo đường dẫn không tự nhận biết bytes đã thay.

5. **Tạo lại metadata/index sau ghép.** Giữ ba audio mới, các key đang dùng, trạng thái enabled và file cần giữ; chỉ cập nhật metadata của đúng bản thu được thay. Sau đó cập nhật checksum, dung lượng, số lượng và version gói. Tests import GAP66 cần dùng receipt mới cho hai bản thu GAP66 thay thế.

## Cách tích hợp đề xuất

Giữ nền Android và thay đổi bỏ Level hiện tại. Nhập có chọn lọc 795 bản thu cùng metadata tương ứng; giữ các audio đang dùng thay vì nhận việc xóa toàn bộ 6 file. Giữ ba audio mới với key/text hiện tại và các entry Level đã tắt. Đo lại loudness, tạo lại pack index rồi chạy kiểm thử audio/điều hướng/hoàn thành/resume. Không cần lấy toàn bộ 63 commit của nhánh nguồn chỉ để cập nhật audio.

Chưa chạy build hoặc kiểm thử ứng dụng trên một cây mã đã tích hợp vì bước này mới là đánh giá trước đồng bộ. SHA-256 chứng minh tính toàn vẹn file theo manifest, không chứng minh lời thu của toàn bộ 795 file khớp nội dung hoặc chất lượng nghe.

Bằng chứng: [review.json](D:/Code/HuaMei/App_noi/flutter/23_23th9/speaking-ai-flutter/output/commit-deb55732-review/review.json), [mô phỏng riêng commit](D:/Code/HuaMei/App_noi/flutter/23_23th9/speaking-ai-flutter/output/commit-deb55732-review/single_commit-simulation.txt), [mô phỏng merge lịch sử](D:/Code/HuaMei/App_noi/flutter/23_23th9/speaking-ai-flutter/output/commit-deb55732-review/whole_history-simulation.txt), [mẫu đo âm lượng](D:/Code/HuaMei/App_noi/flutter/23_23th9/speaking-ai-flutter/output/commit-deb55732-review/gain-samples.json).
