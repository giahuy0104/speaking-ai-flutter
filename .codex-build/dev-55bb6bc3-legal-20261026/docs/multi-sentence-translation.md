# Dịch lượt nói nhiều câu

## Phạm vi triển khai

- Phân loại cục bộ sau khi có transcript cuối cùng, sau bước sửa transcript.
- Sau lần debug vivo ngày 20/10/2026, người dùng cho phép nhận thêm mẫu câu hỏi rõ khi ASR thiếu dấu: câu hỏi trực tiếp kết thúc `không/chưa`, tiếp theo là câu hỏi `Bạn/Anh/Chị/Em/Cô/Chú có/đã…không/chưa` hoặc `Có bao nhiêu/Bao nhiêu…`. Giữ nguyên chữ và thứ tự; không thêm dấu hỏi vào transcript. Trích dẫn, ngoặc, dấu ba chấm, lời thuật lại hoặc câu chưa đủ cấu trúc vẫn giữ nguyên.
- Một câu hoặc ranh giới không chắc chắn: giữ nhánh gọi API/phát/cache cũ.
- Nhiều câu: dịch câu đầu, phát ngay khi sẵn sàng; chuẩn bị tối đa một câu kế tiếp. Chỉ sự kiện kết thúc phát mới cho phép chuyển câu. Không dùng timeout 30 giây của luồng cũ để suy ra đã phát xong.
- Không thay backend, timeout API, thời gian im lặng hoặc giới hạn thu **12 giây**.
- Luồng Android/Apple native, HFP và Realtime có final transcript dùng hàng đợi. Batch/upload dự phòng chỉ trả transcript cùng bản dịch/TTS nên giữ đường cũ: không gọi lại API chia câu sau khi backend đã dịch cả lượt.

## Các thành phần

- `sentence_queue.dart`: bộ tách câu bảo thủ, session ID, chỉ số câu, một lookahead, bắt lỗi nền và hủy.
- `sentence_audio_cache.dart` và `sentence_audio_storage_*`: tải HTTP theo stream, tối đa 2 MiB/câu và 8 giây/tải; đóng client khi hủy; kiểm tra SHA-256 nếu có. Native lưu file tạm, Web giữ data URI. Giải phóng sau mỗi câu và khi kết thúc/hủy. Không đụng nguồn của player khi tải trước.
- `conversation_controller.dart`: nối final transcript vào hàng đợi, dùng API hiện có và dịch offline dự phòng; hủy theo generation, hiển thị tiến độ và giữ kết quả.
- `conversation_screen.dart`: nội dung các câu trước, câu hiện tại, nút dừng; hủy hàng đợi khi màn hình bị dispose.
- `conversation_repository.dart`/`next_conversation_repository.dart`: giữ HTTP status và request ID của lỗi để log được mà không log nội dung request hay thông tin xác thực.

## Lịch sử, nghe lại và ngữ cảnh

Mỗi câu tạo một bản ghi API riêng. `benchmark` gửi kèm `sentenceSessionId`, `sentenceIndex` (bắt đầu từ 0) và `sentenceCount`. Không thay schema lịch sử backend; giao diện lịch sử cũ chưa nhóm thành một lượt.

Bản ghi micro toàn lượt chỉ archive **một lần vào bản ghi câu đầu** nếu nền tảng cung cấp recording. Các capture của câu con không chứa recording. Nếu API câu đầu thất bại, không có bản ghi để archive.

Nút nghe lại trên panel phát **câu đang hiển thị cuối cùng**, chỉ hoạt động khi hàng đợi đã dừng. Chưa có nghe lại cả lượt hoặc chọn từng câu cũ. Không có tự thử lại câu lỗi và không tự bỏ qua câu lỗi. API vẫn giữ chính sách retry sẵn có cho phản hồi xác nhận bị hoãn/rate-limit; không thêm retry transport/5xx.

Giữ nguyên `context`, tuổi và cấu hình của lượt cho mọi request. API hiện không nhận bản dịch câu trước/conversation-session tiếp nối trong `processStreamingText`; do đó đại từ, chủ ngữ lược bỏ hoặc ý nghĩa phụ thuộc câu trước có thể dịch sai. Đề xuất riêng: hợp đồng backend nhận ngữ cảnh trước đó và khóa idempotency, đồng thời giữ một parent-turn cho lịch sử. Chưa triển khai các thay đổi này.

## Kiểm thử tự động

Lệnh:

```powershell
flutter test --no-pub test/features/conversation/sentence_queue_test.dart test/sentence_audio_cache_test.dart test/core_audio_streaming_fallback_test.dart test/features/conversation/continuous_translation_session_test.dart test/features/conversation/next_conversation_repository_test.dart
```

Các kiểm thử mới dùng **mock**, không gọi dịch/TTS thật:

- Câu đơn: một request, một lần phát, không có preload bổ sung.
- Ví dụ ba câu: ba request, phát đúng thứ tự, không thiếu/lặp; request câu 2 bắt đầu trước khi câu 1 kết thúc, chưa tạo request câu 3.
- Câu sau chậm: chờ và báo tiến độ; lỗi câu sau chỉ hiển thị khi câu đang phát kết thúc.
- Hủy lúc đang chuẩn bị hoặc phát; lỗi trả về sau hủy được thu nhận, kết quả cũ không xuất hiện ở lượt mới.
- Số thập phân, chữ viết tắt, dấu ba chấm, transcript không dấu câu.
- HTTP lỗi, vượt giới hạn tải và checksum sai; tải bị hủy.
- Bộ kiểm thử hồi quy hiện có kiểm tra MAIN/HFP, ASR, fallback và chính sách retry/lịch sử.

Lần chạy mở rộng: **191 kiểm thử qua**, gồm cả `main_speaking_no_speech_test.dart`, `h20_hardware_diagnostics_test.dart` và `core_audio_playback_completion_test.dart`. Thêm hai ca phân loại lỗi download timeout/network được chạy riêng sau đó. Phân tích toàn repository có lỗi ngoài phạm vi ở dependency `flutter_local_notifications` chưa có trong package config và các script thử nghiệm `tmp`. Các file thay đổi được phân tích riêng: không có lỗi.

## Đo lường: trạng thái thực tế

**Chưa có phép đo trước/sau trên điện thoại/H20. Không kết luận hàng đợi nhanh hơn.**

| Chỉ tiêu | Trước | Sau |
| --- | --- | --- |
| Ngừng nói → âm thanh đầu tiên, câu đơn | Chưa đo thiết bị | Chưa đo thiết bị |
| Ngừng nói → âm thanh đầu tiên, nhiều câu | Chưa đo thiết bị | Chưa đo thiết bị |
| Khoảng nghỉ giữa câu | Chưa đo thiết bị | Có log `gapMs`, chưa đo thiết bị |
| Lỗi / thiếu / phát trùng thực tế | Chưa đo thiết bị | Chưa đo thiết bị |
| Request/phát với mock câu đơn | Nhánh cũ | 1 / 1 |
| Request/phát với mock ba câu | Nhánh cũ dịch toàn lượt | 3 / 3, đúng thứ tự |

Log hàng đợi: `sentence_prepared`, `sentence_playing`, `sentence_failed`, gồm session ID, chỉ số câu và conversation ID khi có. `sentence_playing` ghi `stopToFirstAudioMs` cho câu đầu và `gapMs` cho câu sau. Lỗi API có `requestId`, `httpStatus`, `code` khi backend cung cấp. Log câu đơn vẫn dùng `playback_latency_client`. Thời điểm stop của controller là mốc phần mềm, không thay thế mốc ngừng nói thực tế; muốn đo cả VAD cần đối chiếu bản ghi ngoài.

## Quy trình xác nhận điện thoại/H20

1. Cùng điện thoại, backend, mạng, tốc độ đọc và thiết bị H20, chạy bản trước thay đổi và bản mới. Tối thiểu 20 lượt câu đơn và 20 lượt ba câu cho mỗi bản.
2. Kiểm tra riêng mic/loa điện thoại, H20 HFP và nút MAIN. Dùng ví dụ ba câu trong yêu cầu. Không tăng thời gian thu: ghi nhận nếu vượt 12 giây hoặc ASR ngắt lượt sớm.
3. Ghi âm ngoài để đánh dấu lúc ngừng nói, âm đầu/âm cuối từng câu; đối chiếu log. Tổng hợp median/p95 độ trễ, khoảng nghỉ, số lỗi, số câu thiếu và số phát trùng.
4. Làm chậm mạng trong lúc câu 1 phát: xác nhận “Đang chuẩn bị câu 2/3”, câu 1 không bị ngắt.
5. Ngắt mạng hoặc gây lỗi TTS ở câu 2: câu 1 phải phát hết; báo đúng câu lỗi, không phát câu 3. Nếu fallback offline thành công thì vẫn phát theo thứ tự.
6. Bấm dừng/MAIN dài trong khi phát và tải câu sau; rời màn hình, mở lại và bắt đầu lượt mới. Không nghe câu cũ hoặc thấy nội dung cũ cập nhật.
7. Kiểm tra lịch sử từng câu và recording: chỉ câu đầu có toàn bộ bản thu, không có bản sao cho câu 2/3. Nghe lại panel chỉ phát câu cuối đang hiển thị.
8. Kiểm tra transcript không dấu câu, “3.14”, “Dr. Smith”, “TP. HCM”, dấu ba chấm. Không đoán ranh giới khi thiếu bằng chứng.

Máy phát triển nhận điện thoại vivo 1919 qua USB khi kiểm tra danh sách thiết bị. Trong lần debug trực tiếp sau đó, APK 1.0.11 (75) chạy Android native ASR và transcript hiển thị trên UI chứa `…được không Bạn có thể…được không` nhưng không có dấu câu. Không thấy sự kiện hàng đợi trong các lượt này. Đã thêm regression test bằng đúng transcript đó và log `sentence_classification` với `splitterVersion: 2`; chưa được coi là xác nhận bản sửa trên thiết bị cho đến khi cài lại và quan sát log mới.

Các log thực tế của bản trước sửa ghi stop-to-first-audio 2604, 2944 và 3099 ms cho các lượt khác nhau. Đây là mốc stop phần mềm, không phải phép đo A/B cùng câu và không chứng minh tăng tốc. Một kết quả tiếng Anh hiển thị lời dẫn `You want me to translate…`; Flutter lấy trực tiếp `englishText` từ API và không có chuỗi lời dẫn này trong source. Cần xác minh ở backend dịch (không nằm repository này); chưa sửa backend hay cắt bỏ lời dẫn để che lỗi.

Sau thay đổi heuristic v2: 10 test của `sentence_queue_test.dart` qua; test controller xác nhận transcript vivo 175 ký tự tạo 2 request/phát, đồng thời câu đơn vẫn tạo 1 request. Kiểm thử bổ sung bao phủ câu trích dẫn bằng nháy đơn/nháy kép/ngoặc và mệnh đề gián tiếp. Đây là kiểm thử mock tái hiện dữ liệu thiết bị, chưa phải xác nhận âm thanh của APK mới trên H20.

Đã build và cài cập nhật **1.0.11 (76)** trên vivo qua ADB lúc 17:08 ngày 20/10/2026; kiểm tra package xác nhận versionCode 76. App mở được và log xác nhận tự kết nối BLE/HFP H20. Đang chờ lượt nói thực tế để xác nhận hàng đợi trên bản mới. Lưu ý `pubspec.yaml` hiện ghi `+18` trong khi bản cũ trên điện thoại là 75, nên lệnh build dùng:

```powershell
flutter build apk --release --no-pub --build-number=76 --dart-define-from-file=dart_defines.production.json
```

APK: `build/app/outputs/flutter-apk/app-release.apk`. Không gỡ app hoặc xóa dữ liệu khi cập nhật.

## Giới hạn còn lại

Lượt kiểm tra thực tế build 76 lúc 17:13 ngày 20/10/2026 ghi `splitterVersion: 2`, `characters: 109`, `sentenceCount: 1`. Transcript là `bạn có khả năng đọc số liệu và có hóa quảng cáo được không Bạn có thể tăng doanh thu vào 3 tháng tới được chứ`. Nguyên nhân: heuristic chưa nhận đuôi “chứ”, nên không công nhận câu thứ hai. Bản sửa v3 bổ sung “chứ” ở cuối câu và tại ranh giới, giữ nguyên từ ASR. Regression dùng nguyên văn transcript đã qua, cùng trường hợp đảo thứ tự và chuỗi ba câu. Toàn bộ 11 test splitter/queue và 10 test lọc theo “sentence” đã qua; đây vẫn là kiểm thử tự động, chưa xác nhận phát hai câu trên H20. Build kế tiếp dùng versionCode 77.

Đã cài cập nhật build **77** thành công bằng `adb install -r`, mở app và xác nhận package trên vivo có `versionCode=77`, `lastUpdateTime=2026-10-20 17:24:16`. Phân tích tĩnh các file sửa không có lỗi. Chưa có lượt nói thực tế sau cập nhật để xác nhận hàng đợi/âm thanh trên thiết bị.

- Tách câu bảo thủ có thể giữ nhiều câu thành một đoạn, nhất là câu trần thuật không dấu, ASR viết thường sau dấu chấm, dấu câu thiếu khoảng trắng hoặc viết tắt chưa biết. Mẫu câu hỏi thiếu dấu là heuristic giới hạn, không phải bộ phân tích ngữ nghĩa tiếng Việt tổng quát.
- Trần thu 12 giây có thể cắt mất ví dụ dài. Cần quyết định riêng trước khi đổi trần thu hoặc endpointer.
- API dịch dùng client chung, không có hủy theo request trong interface: bỏ qua kết quả muộn bằng generation. Request đã gửi có thể vẫn tạo lịch sử trên server dù người dùng đã dừng.
- Thiết bị phải hỗ trợ sự kiện completion; nếu không có, hàng đợi báo lỗi thay vì đoán thời gian kết thúc.
- Web data URI, codec âm thanh thực tế, phát qua H20 và chất lượng dịch phụ thuộc ngữ cảnh cần xác nhận trên thiết bị.
- Log thời điểm bắt đầu TTS offline chưa có callback từ voice service nên không có số đo đầu âm chính xác cho nhánh này.
