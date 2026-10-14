# Kiểm tra TTS trong intro chủ đề và bài học

**Cập nhật sau audit:** 13 trường hợp dưới đây đã được sửa; xem `output/intro-audio-fix/REPORT.md`. Nội dung bên dưới giữ lại kết quả trước khi sửa để đối chiếu.

Ngày 14/10/2026. Kiểm tra working tree hiện tại trên nhánh `add-audio-android-13th10`, HEAD `a494c9e535dea79e82dd500d3c737388b84c8018`, bao gồm các thay đổi chưa commit. Không áp dụng commit `deb55732ad886c42aa83d0477f24edbfe15c96a1` trong đợt kiểm tra này.

## Kết quả

Ba trợ lý kiểm tra độc lập tuyến mở chủ đề, toàn bộ intro bài học và registry/pipeline audio. Kiểm thử bổ sung chạy màn hình `LessonIntroScreen` thật với factory audio thật, ghi lại lời gọi native qua kênh giả lập.

| Phạm vi | Tổng | Có gọi TTS | Toàn bộ dùng MP3 |
|---|---:|---:|---:|
| Intro học mới, cấu hình Android | 109 | 13 | 96 |
| Intro học mới, cấu hình iOS | 109 | 13 | 96 |
| Trong đó: bài đầu tiên của chủ đề | 50 | 3 | 47 |
| Prompt học tiếp/học lại và biến thể, qua factory | 246 | 0 | 246 |

Hai cấu hình Android và iOS có cùng 13 bài bị TTS. Mỗi bài gọi TTS hai lần: phần dẫn tiếng Việt rồi tên bài tiếng Anh. Hook mở cảnh và câu “Bắt đầu nhé.” vẫn dùng MP3. Tổng cộng 26 lượt TTS nếu mở mới cả 13 bài một lần, tương ứng 16 đoạn văn bản/ngôn ngữ duy nhất.

**Cả 13 MP3 intro đầy đủ đã tồn tại và hợp lệ.** Chưa thể kết luận cần thu mới 13 intro: vấn đề hiện tại là nhánh phát tách đoạn không sử dụng các file đầy đủ đó.

## Danh sách tái hiện

Mở bài ở trạng thái học mới; trạng thái học tiếp/học lại dùng nhánh khác.

| Tuổi | Chủ đề | Bài | Tên bài được đọc bằng TTS | ID |
|---|---:|---:|---|---|
| 3–5 | 2 | 3 | Count With Me | c35-l1-t02-b03 |
| 3–5 | 5 | 1 | Animal Names | c35-l2-t05-b01 |
| 3–5 | 9 | 2 | What to Wear? | c35-l3-t09-b02 |
| 3–5 | 10 | 2 | Happy Day | c35-l3-t10-b02 |
| 6–7 | 3 | 2 | Animal Abilities | c67-l1-t03-b02 |
| 6–7 | 7 | 2 | In Class | c67-l3-t07-b02 |
| 6–7 | 9 | 2 | Where Are We? | c67-l3-t09-b02 |
| 8–10 | 1 | 1 | Time & Tasks | c810-l1-t01-b01 |
| 8–10 | 2 | 2 | Classroom Talk | c810-l1-t02-b02 |
| 8–10 | 5 | 1 | Weather Choices | c810-l2-t05-b01 |
| 11–12 | 6 | 2 | Stay Safe | c1112-l2-t06-b02 |
| 13–15 | 7 | 2 | Ask for Info | c1315-l3-t07-b02 |
| 13–15 | 8 | 2 | My Order | c1315-l3-t08-b02 |

Ba đoạn tiếng Việt bị TTS là `Bài này là`, `Chủ đề 1. Bài đầu tiên là`, `Chủ đề 5. Bài đầu tiên là`. Cộng với 13 tên tiếng Anh ở bảng trên thành 16 đoạn duy nhất.

Ba trường hợp mở đầu chủ đề là 3–5 tuổi/chủ đề 5 và 8–10 tuổi/chủ đề 1, chủ đề 5. Ví dụ Animal Names: TTS “Chủ đề 5. Bài đầu tiên là” → TTS “Animal Names” → MP3 `ban-doan-xem-con-gi.mp3` → MP3 `assistant.main.start_now.vi.mp3`.

## Nguyên nhân trong mã

- `lib/features/listening/presentation/lesson_intro_screen.dart:250–284`: khi intro mới có hook audio riêng, tách thành lead → hook → start cue rồi return trước nhánh full-intro.
- `:259`: lead không có audio key. Registry có tìm theo textHash, nhưng cả lead đầy đủ lẫn các đoạn con đều không khớp audio đang bật.
- `:349–369`: chia lead thành tiếng Việt và tên tiếng Anh để phát TTS theo locale.
- `:473–483`: full-intro key vẫn được tạo đúng, nhưng nhánh hook phía trên không sử dụng nó.

Catalog có 18 bài entry loại hook; chỉ 13 bài có hook MP3 riêng. Năm bài còn lại vẫn phát MP3 intro đầy đủ, nên không tính cả 18 là lỗi.

## Tuyến chủ đề và các nhánh khác

Chạm và điều hướng MAIN/giọng nói hội tụ tại `TopicListeningScreen._openTopic` rồi tới `TopicLessonListScreen` và `LessonIntroScreen`. Không có bộ phát intro chủ đề riêng; lời “Chủ đề N. Bài đầu tiên là…” thuộc intro bài số 1. MAIN trả prompt rỗng khi chuyển quyền cho màn chủ đề để tránh đọc trùng.

Các màn tạo service với owner `listeningLesson`, nạp đúng common và năm age packs. Không thấy nhầm owner hoặc cấu hình làm mất toàn bộ MP3.

246 trường hợp qua factory gồm 109 resume, 109 relearn, 12 biến thể còn thiếu sao, 5 song-resume, 10 topic-resume và 1 challenge-resume: tất cả gọi phát MP3, không gọi TTS. Kiểm tra tĩnh thêm xác nhận 10/10 câu xác nhận học lại chủ đề có MP3 đang bật, đúng text và file.

Manifest có đủ 109 intro, 109 resume, 109 relearn, 5 song-resume và 13 hook; file/checksum/kích thước/thời lượng hợp lệ. Hash intro được tạo từ ba đoạn VI–EN–VI phân cách NUL, không phải hash toàn câu runtime; đây là quy ước của generator, không phải nguyên nhân TTS.

## Hướng xử lý

Ưu tiên sửa nhánh mở mới của 13 bài để lời dẫn dùng audio có sẵn hoặc audio tách phù hợp, đồng thời giữ âm thanh mở cảnh và tránh đọc hook hai lần. Nếu giữ thiết kế tách đoạn hiện tại, có thể cần 13 bản lời dẫn ghép Việt–Anh, hoặc 16 đoạn dùng lại gồm 3 tiền tố và 13 tên bài. Đây là số đoạn chưa có mapping phù hợp với nhánh hiện tại, không phải số intro đầy đủ còn thiếu.

Chưa sửa mã ứng dụng trong đợt audit này. Các thay đổi có từ công việc trước được giữ nguyên.

## Bằng chứng và giới hạn

- `fresh-android.json`, `fresh-iOS.json`: từng bài và chuỗi sự kiện MP3/TTS thực tế tại ranh giới native.
- `resume-relearn-runtime.json`: 246 prompt và sự kiện phát.
- `intro_runtime_probe_test.dart`: probe màn hình/factory, progress trong bộ nhớ, không ghi tiến độ người dùng.
- `lesson-agent.json`, `lesson_inventory.py`: inventory tĩnh toàn bộ bài.
- `registry-agent.json`: kết quả kiểm tra registry và audio.
- `runtime-probe.log`: lần chạy gộp; Android hoàn tất 109 bài, iOS và test kế tiếp gặp vấn đề cache Future giữa các fake-async zone của test harness.
- `runtime-ios.log`, `runtime-resume.log`: chạy riêng từng test trong process mới, đều pass. Có thể tái hiện với `flutter test --no-pub output/intro-deep-audit/intro_runtime_probe_test.dart --plain-name 'TargetPlatform.iOS'` và `--plain-name 'observe all resume/relearn'`; dùng `TargetPlatform.android` để chạy riêng Android.

Kiểm thử xác nhận lựa chọn MP3/TTS và bytes asset trong ứng dụng; chưa nghe hoặc kiểm tra decoder/loa trên thiết bị Android/iOS thật. Lỗi tải file, decoder hoặc timeout trên thiết bị vẫn có thể gây fallback TTS ở những trường hợp khác; chưa có bằng chứng các lỗi đó xảy ra trong đợt này.
