# Báo cáo hiện trạng ứng dụng Android và luồng Bộ từ vựng

**Ngày kiểm tra:** 14/09/2026  
**Phạm vi:** nhánh hiện tại, APK production hiện có, luồng thêm từ vựng và luồng dịch liên tục trên Android  
**Trạng thái tài liệu:** báo cáo kiểm tra; chưa bao gồm thay đổi sửa lỗi

## 1. Tóm tắt điều hành

Hiện tại có hai kết luận chính:

1. **Bộ từ vựng có vấn đề về UI và nối dependency.** Ô nhập đang hiển thị trong bộ từ vựng chỉ làm nhiệm vụ tìm kiếm. Luồng thêm từ và chọn gợi ý vẫn tồn tại nhưng nằm sau nút `+`. Ngoài ra, provider tạo gợi ý linh hoạt đã được khai báo ở các widget trung gian nhưng chưa được app gốc truyền vào, nên production nhận giá trị `null`.
2. **Dịch liên tục trên Android production mặc định dùng Android SpeechRecognizer.** Cloudflare Batch Chunks không phải đường nhận dạng giọng nói mặc định trong cấu hình production hiện tại. Báo cáo chậm khoảng 4 giây chưa có bằng chứng là do Batch Chunks; độ trễ có thể là tổng của thời gian chốt transcript Android, xử lý dịch/TTS tại backend và tải audio.

Chưa có thay đổi chức năng nào được thực hiện trong đợt kiểm tra này.

## 2. Trạng thái repository và APK hiện tại

| Hạng mục | Giá trị |
|---|---|
| Nhánh | `codex/audio-session-modularization` |
| HEAD | `c7fe7b1` — `fix(device): defer BLE feedback during assistant audio` |
| Phiên bản Flutter | `1.0.5+7` |
| APK production | `build/app/outputs/flutter-apk/app-release.apk` |
| Kích thước APK | `167,642,536 bytes` |
| Thời điểm file APK | `13/09/2026 23:01:44` |
| SHA-256 | `F0567B620811F31B6CF3A8700EA998314F346659350B3F90E25EBABD10C86196` |

Working tree hiện có các thay đổi chưa commit từ công việc micro/voice navigation trước đó:

- `android/app/src/main/kotlin/com/innotrik/aispeaking/AndroidSpeechRecognizerBridge.kt`
- `lib/app/ai_speaking_app.dart`
- `lib/features/voice_navigation/application/voice_navigation_controller.dart`
- `test/features/voice_navigation/voice_navigation_controller_test.dart`

## 3. Hiện trạng Bộ từ vựng

### 3.1. Hành vi hiện tại

Ô nhập trong màn chi tiết bộ từ vựng được tạo bởi `_buildSearchField`. Ô này:

- dùng `_searchController`;
- có nhãn `Tìm từ vựng…`;
- chỉ lọc các mục đã lưu theo `word` và `meaning`;
- không có `onSubmitted`, nút thêm hoặc lời gọi provider gợi ý.

Vì vậy, khi người dùng nhập một từ mới vào ô này, giao diện chỉ trả về trạng thái không tìm thấy từ phù hợp. Đây là hành vi tìm kiếm đúng theo code hiện tại, nhưng không phù hợp với trải nghiệm người dùng mong đợi là nhập để được đề xuất thêm từ.

### 3.2. Luồng thêm từ vẫn còn

Luồng thêm từ hiện nằm sau nút `+` ở header:

1. Mở `_AddVocabularyDialog`.
2. Nhập từ tiếng Anh hoặc tiếng Việt.
3. Dịch nội dung nhập.
4. Chuẩn bị danh sách lựa chọn.
5. Mở `_VocabularySuggestionDialog`.
6. Người dùng chọn nội dung rồi thêm vào hàng chờ.

Do đó chức năng thêm từ không bị xóa hoàn toàn; nó bị tách khỏi ô nhập chính và trở nên khó nhận biết.

### 3.3. Dependency tạo gợi ý chưa được nối đến app production

`VocabularyHomeScreen` hỗ trợ `suggestionProvider`, và `HomeLearningShell` cũng có trường `vocabularySuggestionProvider`. Tuy nhiên, tại nơi app gốc tạo `HomeLearningShell`, trường này không được truyền vào.

Kết quả:

- `widget.suggestionProvider` trong production là `null`;
- danh sách vẫn có thể chứa bản dịch chính;
- một số cụm có gợi ý hard-code trong catalog nội bộ;
- các từ/cụm ngoài catalog không nhận được gợi ý linh hoạt từ AI/provider.

Đây là một lỗi nối dependency thực tế và cần được sửa nếu mục tiêu sản phẩm là luôn đưa ra nhiều đề xuất phù hợp.

### 3.4. Lịch sử liên quan

- Commit `8bdd260` ngày 03/08/2026 tạo thiết kế tách ô tìm kiếm và nút thêm.
- Commit `e445c97` ngày 10/09/2026 thêm luồng chọn đề xuất nhưng chưa nối provider từ app gốc.
- Commit `9cbe62b` ngày 12/09/2026 chủ yếu thay đổi ranh giới dependency âm thanh/kiến trúc; không làm thay đổi hành vi tìm kiếm hoặc thêm từ.

Kết luận: vấn đề không phát sinh trực tiếp từ commit phân bổ lại kiến trúc ngày 12/09. Phần UI đã tách từ trước, còn provider bị thiếu dây nối từ lúc tính năng gợi ý được tích hợp.

### 3.5. Khoảng trống kiểm thử

Các test hiện tại kiểm tra việc:

- bấm nút `+`;
- nhập nội dung trong `add-vocabulary-field`;
- xác nhận dialog gợi ý;
- lưu từ vào store.

Chưa có test cho:

- nhập từ mới trong ô đang hiển thị rồi chuyển sang luồng thêm;
- CTA `Thêm từ này` khi tìm kiếm không có kết quả;
- provider được nối đầy đủ từ `AiSpeakingApp` đến `VocabularyHomeScreen`;
- gợi ý động hoạt động trong cấu hình production.

## 4. Hiện trạng dịch liên tục trên Android

### 4.1. Cấu hình production đang kiểm tra

Các cờ liên quan:

| Cờ | Giá trị |
|---|---|
| `USE_DEMO_BACKEND` | `false` |
| `ENABLE_LEGACY_BLE_AUDIO` | `false` |
| `ENABLE_HFP_AUDIO` | `true` |
| `PREFER_BLE_STREAMING` | `true` |
| `REALTIME_BATCH_FALLBACK` | `true` |
| `ENABLE_VOICE_NAVIGATION` | `true` |

`PREFER_BLE_STREAMING=true` không kích hoạt được audio BLE cũ khi `ENABLE_LEGACY_BLE_AUDIO=false`. Vì vậy trong APK production hiện tại, audio BLE cũ không phải đường thu chính.

### 4.2. Đường xử lý mặc định

Trên Android, app tạo `AndroidStreamingSpeechInput` và khởi tạo `AsrMode.androidStreaming`.

Đường xử lý online thông thường:

```text
Mic điện thoại hoặc H20 qua HFP
        ↓
Android SpeechRecognizer nhận dạng trực tiếp
        ↓
Transcript tiếng Việt
        ↓
POST /api/conversation
        ↓
Backend dịch và chuẩn bị TTS/audio
        ↓
Ứng dụng tải và phát audio kết quả
```

Trong đường này, ứng dụng gửi transcript lên backend; không gửi bản ghi âm qua Cloudflare Batch Chunks để nhận dạng.

### 4.3. Khi nào Cloudflare Batch Chunks được dùng

Batch Chunks có thể được sử dụng khi:

- audio BLE cũ được bật và chọn làm nguồn;
- bộ nhận dạng offline BLE không khả dụng hoặc không đủ chắc chắn;
- một đường realtime cần fallback;
- Android nhận dạng từ file WAV thất bại trong đường offline/recorded-audio đặc biệt;
- nền tảng không có native streaming speech.

`REALTIME_BATCH_FALLBACK=true` chỉ cho phép fallback. Cờ này không ép mọi lượt nói Android chạy qua Batch Chunks.

### 4.4. Phân tích độ trễ khoảng 4 giây

Không tìm thấy delay 4 giây cố định trong luồng dịch liên tục. Delay `Duration(seconds: 4)` duy nhất liên quan trong controller thuộc chức năng kiểm tra mic INNOTRIK/H20 và không nằm trong quy trình dịch.

Sau khi dừng nói, `AndroidStreamingSpeechInput.stop()` có thể chờ:

- khoảng `220 ms` nếu đã có partial transcript ổn định;
- hoặc `500 ms`, sau đó tối đa thêm `700 ms` nếu chưa có transcript dùng được.

Như vậy riêng bước chốt kết quả Android có thể mất tối đa khoảng `1.2 giây`. Sau đó app còn chờ:

1. kiểm tra trạng thái mạng;
2. request `/api/conversation`;
3. backend dịch và tạo/chuẩn bị TTS;
4. tải hoặc preload audio;
5. bắt đầu phát audio.

Do chưa có log từ đúng thiết bị và đúng APK của người kiểm thử, hiện chưa thể khẳng định phần nào trong chuỗi trên chiếm khoảng 4 giây. Tuy nhiên, với cấu hình production đang kiểm tra, chưa có bằng chứng cho thấy nguyên nhân là Cloudflare Batch ASR.

### 4.5. Telemetry đã có nhưng cần lấy từ thiết bị

Code hiện đã gửi/ghi một số số đo hữu ích:

- `asrFirstDeltaMs`;
- `asrFinalAfterStopMs`;
- `audioStartedAfterStopMs`;
- `audioLoadMs`;
- `responseToPlaybackMs`;
- thông tin ASR mode và native speech engine.

Cần lấy log của một lượt chậm trên thiết bị Android để chia chính xác độ trễ thành:

```text
ASR finalize | Backend translation/TTS | Audio loading/playback
```

## 5. Kết quả kiểm thử trong đợt kiểm tra

Đã chạy và đạt:

```text
flutter test test/features/vocabulary/vocabulary_home_screen_test.dart
Kết quả: 6/6 test passed
```

```text
flutter test test/core_audio_streaming_fallback_test.dart \
  --plain-name "standard Android ASR prefers direct streaming over recorded-audio injection"
Kết quả: passed
```

```text
flutter test test/core_audio_streaming_fallback_test.dart \
  --plain-name "BLE without offline ASR falls back directly to Cloudflare Batch Chunks"
Kết quả: passed
```

Các test chứng minh code đang phân biệt đúng hai đường Android native và BLE Batch, nhưng chưa thay thế được phép đo trên thiết bị thật.

## 6. Mức độ ưu tiên và rủi ro

| Vấn đề | Mức độ | Ảnh hưởng |
|---|---|---|
| Ô nhập bộ từ vựng chỉ tìm kiếm, không gợi ý thêm | Cao | Người dùng tưởng chức năng thêm từ đã mất |
| `vocabularySuggestionProvider` không được nối | Cao | Production thiếu gợi ý linh hoạt ngoài catalog |
| Chưa xác định thành phần gây độ trễ 4 giây | Cao | Trải nghiệm dịch liên tục chậm, khó khoanh vùng nguyên nhân |
| Thiếu integration test cấp app cho provider | Trung bình | Lỗi nối dependency có thể tái diễn |
| Thiếu log từ đúng APK/thiết bị tester | Trung bình | Không thể so sánh định lượng với nhánh cũ |

## 7. Hướng xử lý đề xuất

### Ưu tiên 1 — Khôi phục trải nghiệm thêm từ

- Tách rõ hai trạng thái `Tìm kiếm` và `Thêm từ`, hoặc cho ô hiện tại hiển thị CTA `Thêm “...”` khi không có kết quả.
- Khi chọn thêm, tái sử dụng `_showAddDialog`/luồng chuẩn bị đề xuất hiện có.
- Nối provider thật từ `AiSpeakingApp` đến `HomeLearningShell` và `VocabularyHomeScreen`.
- Thêm integration test từ app root, không chỉ test widget độc lập.

### Ưu tiên 2 — Đo chính xác độ trễ Android

- Kiểm thử đúng APK có SHA-256 ghi trong tài liệu này.
- Ghi lại một lượt nhanh và một lượt chậm.
- Xác nhận `asrMode=android_streaming` trong log.
- So sánh `asrFinalAfterStopMs`, thời gian backend và `audioStartedAfterStopMs`.
- Chỉ tối ưu timeout SpeechRecognizer sau khi biết thời gian đang nằm ở ASR hay backend/TTS, tránh giảm độ chính xác nhận dạng giọng trẻ em.

### Tiêu chí hoàn thành đề xuất

- Người dùng có thể nhập từ mới từ màn bộ từ vựng và thấy lựa chọn thêm/gợi ý rõ ràng.
- Provider gợi ý không còn `null` trong runtime production.
- Test cấp app xác nhận luồng thêm từ hoàn chỉnh.
- Android online xác nhận dùng `android_streaming` trong log.
- Có bảng đo trước/sau cho thời gian từ lúc dừng nói đến lúc bắt đầu phát audio.

## 8. Tệp mã liên quan

- `lib/features/vocabulary/presentation/vocabulary_home_screen.dart`
- `lib/features/home/presentation/home_learning_shell.dart`
- `lib/app/ai_speaking_app.dart`
- `lib/features/conversation/presentation/conversation_controller.dart`
- `lib/core/audio/streaming_speech_input.dart`
- `lib/features/conversation/data/next_conversation_repository.dart`
- `test/features/vocabulary/vocabulary_home_screen_test.dart`
- `test/core_audio_streaming_fallback_test.dart`
