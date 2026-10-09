# HOMI — sửa các lỗi luồng Android ngày 16/09/2026

## Phạm vi và mức xác nhận

Các bản sửa được tách theo Chủ đề, Bộ từ vựng, Dịch liên tục và lớp tín hiệu mic. Không khôi phục Role-play/Mission hay tạo engine học song song. Những thay đổi có sẵn trong worktree được giữ nguyên.

Kiểm tra tự động: 801/801 test đạt, `flutter analyze` không có lỗi, Android `lintRelease` thành công (0 lỗi, 24 cảnh báo). Cảnh báo chủ yếu về cập nhật thư viện, icon, API guard dư và SharedPreferences; không nâng cấp thư viện ngoài phạm vi sửa lỗi.

Đây không phải chứng nhận đã hết lỗi trên mọi điện thoại. Máy chưa có Android thật/H20 kết nối; thời gian mở mic, nhận diện giọng trẻ và chất lượng âm thanh Bluetooth cần kiểm thử thiết bị thật.

## Đối chiếu 10 phản ánh

| # | Phản ánh | Bản sửa / mức kiểm chứng |
|---|---|---|
| 1 | Lời dẫn “Bài học đang xử lý…” dư | Bỏ lời nói khi command registry hết thời gian chờ. Test xác nhận command chậm không phát lời dẫn này. |
| 2 | Challenge sai lần đầu đọc đáp án như Core | RETRY phát phản hồi rồi lặp câu hỏi và lựa chọn đã được biên soạn trong `challenge.prompt`; không tiết lộ đáp án. GIVE vẫn có lời dẫn và đáp án. Test kiểm tra thứ tự audio. |
| 3 | Cuối bài không điều hướng | Android dùng live command ASR cho completion, tách khỏi bản ghi Core. Nhận số bài đang được hỏi, “học lại”, “đi tiếp”, “tiếp tục”, kết quả Việt/Anh và alternative transcripts. Test thực thi “học lại” và “Bài 2” đến đúng luồng; có test resume lựa chọn và không nhận echo cả câu hỏi là một lựa chọn. |
| 4 | Mic chậm sau ting | Trên Android mở recorder/ASR trước, rồi mới phát ting. VAD và cửa sổ trả lời bắt đầu sau tín hiệu. Test kiểm tra thứ tự; chưa đo latency trên điện thoại thật. |
| 5 | Nói rõ vẫn báo không nghe rõ | Tránh mất từ đầu khi mic chưa sẵn sàng. Detector riêng của lesson giảm calibration 300 → 150 ms, yêu cầu speech 180 → 120 ms, variation 4 → 2 dB. Completion tận dụng partial/alternatives thay vì phải chờ audio round-trip. Không tự chấm đúng khi thiếu transcript. Cần giọng trẻ thật để xác nhận tỉ lệ nhận diện. |
| 6 | Ting không cố định | Đồng bộ thời điểm ting ở Core/Challenge/Review, completion, dịch và MAIN Android. Native thử tạo lại ToneGenerator một lần nếu bộ phát cũ lỗi sau đổi audio route; xử lý lỗi startTone. Cần kiểm tra âm thanh thật trên phone/H20. |
| 7 | Dịch chờ ngắt quá lâu | Chính sách riêng cho live translation: 1 từ ~500 ms; 2–4 từ ~600 ms; 5–8 từ ~700 ms; trên 8 từ ~800 ms sau tín hiệu cuối. Áp dụng cho cả partial và RMS; hoạt động giọng tiếp tục sẽ trì hoãn endpoint. Chế độ không có transcript giữ VAD dự phòng; mạng/ASR vẫn có độ trễ riêng. |
| 8 | Giọng dịch kéo dài, buồn ngủ | Audio dịch đổi playback rate 0,57 → 0,85. TTS Android dự phòng dùng rate 0,85, pitch 1,05 riêng từng câu; lời dẫn khác reset rate/pitch mặc định. Test kiểm tra style không lan sang Core/MAIN. Pitch chỉ làm giọng sáng hơn nhẹ, không thay thế một voice được thu/sinh với sắc thái vui vẻ. |
| 9 | Điều hướng chạm màn hình không theo kịp | Animation chuyển trang giảm 420 → 220 ms. Nút quay lại Bộ từ vựng dùng cùng xử lý rời lượt audio như MAIN: cập nhật UI ngay, dừng cả dynamic vocabulary audio, bỏ callback của queue cũ, chờ cleanup trước lượt mới. Test mô phỏng native stop chậm và xác nhận không phát tiếp nội dung cũ. Chưa có benchmark FPS trên điện thoại thật. |
| 10 | Danh sách hôm nay tự lặp sau 5 câu | Khi hoàn thành, chuyển sang chờ lựa chọn. Automatic resume sau MAIN im lặng không được hiểu là đồng ý học lại; chỉ lựa chọn replay rõ ràng mới phát lại. Test nghe đủ 5 nội dung, kiểm tra lưu trạng thái, không thêm lượt audio khi MAIN timeout/resume. |

Luyện nghe Chủ đề/Review giữ trần ghi âm 6 giây, trailing silence mặc định 700 ms. Hai lần ASR/NO_RESPONSE không hợp lệ vẫn tạm dừng trực tiếp, không thêm lời mời nói lần thứ ba. Kiểm tra hồi quy đã bao gồm các test này.

## Phân chia quản lý

- `listening/domain/v4_completion_flow.dart`: diễn giải lựa chọn theo stage và bài đang được hỏi.
- `listening/presentation/lesson_practice_screen.dart`: sở hữu capture completion, hủy listener/timer/mic khi MAIN hoặc rời màn hình.
- `listening/presentation/lesson_challenge_screen.dart`: RETRY lặp câu hỏi, không dùng sample đáp án của Core.
- `listening/application/lesson_recording_endpoint_detector.dart`: endpoint lesson và xác nhận speech từ native partial.
- `conversation/application/conversation_recording_endpoint_policy.dart`: quy tắc endpoint dịch; không đổi detector dùng chung toàn app.
- `vocabulary/presentation/vocabulary_practice_screen.dart`: completion Today không tự replay.
- `vocabulary/presentation/vocabulary_home_screen.dart`: navigation cleanup và generation guard chống callback queue cũ.
- `core/audio/voice_prompt_service*`, `VoicePromptBridge.kt`: style từng utterance và tín hiệu ready.
- `core/device/active_learning_module.dart`: không chồng lời dẫn busy lên command hợp lệ.

## Checklist trên điện thoại / H20

1. Core đúng/sai hai lượt, Challenge sai hai lượt: có replay của trẻ, đủ feedback, RETRY Challenge lặp câu hỏi/lựa chọn, GIVE có lời dẫn.
2. Cuối bài nói “học lại”, “Bài 2”, “đi tiếp”; im lặng rồi MAIN: vẫn điều hướng, không mở lại mic chấm Core cuối bài.
3. Pause → resume, câu trước/câu tiếp: không phát lời dẫn busy; không có hai mic/audio chạy song song.
4. Không nói hoặc ASR lỗi hai lần: đủ hai cửa sổ trả lời rồi tạm dừng, không mời nói lần ba.
5. Today nghe đủ 5 nội dung → im lặng → MAIN: không tự lặp; chọn nội dung khác thoát được; chủ động “học lại” mới replay.
6. Ngôi sao/ba mẹ đã thêm đang phát: chạm quay lại rồi đổi nhánh; audio cũ dừng, UI theo ngay, checkpoint không bị callback cũ ghi đè.
7. Mic phone và H20: nói một từ ngay sau ting, câu ngắn, câu dài, ngắt giữa câu; đối chiếu việc mất từ đầu/ngắt quá sớm.
8. Dịch nghe ở rate 0,85: không kéo dài như bản cũ; đối chiếu audio online và TTS fallback. Đo riêng silence, ASR finalize, mạng và thời gian tải audio.

## Log kiểm tra

- `output/apk/qa-20260916-tests.log`
- `output/apk/qa-20260916-lint.log`
- `output/apk/qa-20260916-build.log`
- `output/apk/qa-20260916-build-retry.log`

## APK production đã đóng gói

- File: `deliverables/HOMI-1.0.8-production-flow-fixes-20260916.apk`.
- Build thành công ngày 16/09/2026 lúc 01:14 (UTC+7), dung lượng 167.673.388 byte.
- Package `com.innotrik.aispeaking`, version `1.0.8`, versionCode `10`; tên/version vẫn giống bản trước, hãy phân biệt bằng file ngày 16/09 và SHA-256.
- SHA-256: `77F8652AC76198122ED34F723874B52BA913148BC9AD5A07252CBE31F82E95A9`. File deliverable và file build có hash giống nhau.
- Chữ ký APK v2 hợp lệ, cùng certificate SHA-256 với APK ngày 15/09: `362043498df62b55e62e8f8775166195d84440c796680236ca4fb5035cda576b`.
- minSdk 24, targetSdk 36; manifest không bật cleartext traffic.
- Kiểm tra binary `lib/arm64-v8a/libapp.so`: có đủ Privacy/Terms/Support URL trong production defines; không còn câu “Bài học đang xử lý, con thử lại sau một chút nhé”. Việc nhúng URL không thay thế kiểm tra nội dung/pháp lý của các trang đó.

Lần build đầu bị JVM thiếu native memory. Lần chạy lại giới hạn tài nguyên JVM theo lệnh build (không đổi cấu hình app) đã thành công trong 317,7 giây. Không sử dụng APK cũ làm kết quả mới.

## Smoke test APK thật — phạm vi giới hạn

- Pixel 8 emulator khởi động được ở lần thử thứ hai; lần đầu bị từ chối do thiếu bộ nhớ commit của máy Windows.
- `adb install -r` với đúng file deliverable trả về `Success`; không gỡ package hay xóa dữ liệu cũ.
- Khởi chạy package: có PID ứng dụng và `MainActivity` là activity foreground.
- Đã xem màn thiết lập phụ huynh, dialog pháp lý và ba liên kết Privacy/Terms/Support ở cuối dialog. Ảnh lưu tại `output/apk/qa-20260916-home.png`, `qa-20260916-legal.png`, `qa-20260916-legal-bottom.png`.
- Tại thời điểm kiểm tra, log `AndroidRuntime:E` không có crash ứng dụng. Emulator có dialog ANR của **System UI**; đóng dialog thì HOMI hiển thị được. Sau đó emulator mất kết nối trước khi hoàn tất kiểm tra các màn học.

Không tính buổi emulator này là kiểm thử đầu-cuối đã đạt. Các luồng completion/retry/Today/navigation được xác nhận bằng test tự động; checklist giọng nói/âm thanh thiết bị thật và smoke đầy đủ trên máy Android ổn định vẫn cần thực hiện.
